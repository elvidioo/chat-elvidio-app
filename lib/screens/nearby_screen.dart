import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../relay.dart';
import '../theme.dart';
import '../widgets.dart';

const _serviceId = 'com.elvidio.chat.nearby';

class _NearbyMessage {
  final String id;
  final String from;
  final String? text;
  final String? filePath;
  final bool mine;
  final DateTime at;

  _NearbyMessage({
    required this.id,
    required this.from,
    required this.mine,
    this.text,
    this.filePath,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'text': text,
        'filePath': filePath,
        'mine': mine,
        'at': at.toIso8601String(),
      };

  factory _NearbyMessage.fromJson(Map<String, dynamic> j) => _NearbyMessage(
        id: j['id'].toString(),
        from: j['from'].toString(),
        text: j['text']?.toString(),
        filePath: j['filePath']?.toString(),
        mine: j['mine'] == true,
        at: DateTime.tryParse(j['at']?.toString() ?? ''),
      );
}

/// Mode proche : messagerie sans internet entre téléphones (Bluetooth / Wi-Fi
/// Direct via Nearby Connections). Les textes sont relayés de proche en proche.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final nearby = Nearby();
  final picker = ImagePicker();
  final nickname = TextEditingController();
  final input = TextEditingController();

  late String uniqueName;
  bool started = false;
  bool failed = false;
  String statusText = '';

  final peers = <String, String>{}; // endpointId -> nom unique (connectés)
  final endpointNames = <String, String>{}; // endpointId -> nom unique
  final requested = <String>{};
  final messages = <_NearbyMessage>[];
  final seen = <String>{};
  final engine = RelayEngine();
  final outbox = <RelayPacket>[]; // messages envoyés sans voisin : relancés à la connexion
  final relayed = <String, int>{}; // id -> nombre de téléphones atteints

  final pendingFiles = <int, String>{}; // payloadId -> uri ou chemin reçu
  final fileSenders = <int, String>{}; // payloadId -> endpointId
  final fileNames = <int, String>{}; // payloadId -> nom du fichier
  final doneFiles = <int>{};

  // ---------- Historique enregistré sur le téléphone ----------
  Future<File> historyFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/nearby_history.json');
  }

  Future<void> loadHistory() async {
    try {
      final f = await historyFile();
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      final loaded = list
          .map((e) => _NearbyMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        messages.insertAll(0, loaded);
        seen.addAll(loaded.map((m) => m.id));
      });
    } catch (_) {}
  }

  Future<void> saveHistory() async {
    try {
      final f = await historyFile();
      final last = messages.length > 500
          ? messages.sublist(messages.length - 500)
          : messages;
      await f.writeAsString(jsonEncode(last.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  void remember(_NearbyMessage m) {
    messages.add(m);
    saveHistory();
  }

  Future<void> clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Effacer l\'historique ?'),
        content: const Text(
            'Les messages du Mode proche seront supprimés de ce téléphone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    messages.clear();
    await saveHistory();
    refresh();
  }

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  String shortName(String unique) {
    final i = unique.lastIndexOf('#');
    return i > 0 ? unique.substring(0, i) : unique;
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> start() async {
    final base = nickname.text.trim().isEmpty ? 'Anonyme' : nickname.text.trim();
    uniqueName = '$base#${1000 + Random().nextInt(9000)}';
    setState(() {
      started = true;
      failed = false;
      statusText = 'Autorisations...';
    });

    final results = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    if (!(results[Permission.location]?.isGranted ?? false)) {
      setState(() {
        failed = true;
        statusText =
            'Autorise la localisation et le Bluetooth pour trouver les téléphones proches.';
      });
      return;
    }

    try {
      final gpsOn = await Permission.location.serviceStatus.isEnabled;
      if (!gpsOn) {
        setState(() {
          failed = true;
          statusText =
              'Active la localisation (GPS) du téléphone, puis appuie sur Réessayer.';
        });
        return;
      }
    } catch (_) {}

    try {
      await nearby.startAdvertising(
        uniqueName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: onInitiated,
        onConnectionResult: onResult,
        onDisconnected: onDisconnected,
        serviceId: _serviceId,
      );
      await nearby.startDiscovery(
        uniqueName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          // Un seul des deux téléphones lance la connexion (nom le plus petit).
          if (uniqueName.compareTo(name) < 0 &&
              !peers.containsKey(id) &&
              requested.add(id)) {
            endpointNames[id] = name;
            try {
              nearby.requestConnection(
                uniqueName,
                id,
                onConnectionInitiated: onInitiated,
                onConnectionResult: onResult,
                onDisconnected: onDisconnected,
              );
            } catch (_) {
              requested.remove(id);
            }
          }
        },
        onEndpointLost: (id) {
          if (id != null) requested.remove(id);
        },
        serviceId: _serviceId,
      );
      setState(() => statusText = 'Recherche de téléphones proches...');
    } catch (e) {
      setState(() {
        failed = true;
        statusText =
            'Impossible de démarrer (Bluetooth et localisation activés ?).';
      });
    }
  }

  void onInitiated(String id, ConnectionInfo info) {
    endpointNames[id] = info.endpointName;
    nearby.acceptConnection(
      id,
      onPayLoadRecieved: onPayload,
      onPayloadTransferUpdate: onTransferUpdate,
    );
  }

  void onResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      peers[id] = endpointNames[id] ?? id;
      statusText = 'Connecté';
      flushOutbox();
    } else {
      requested.remove(id);
    }
    refresh();
  }

  void onDisconnected(String id) {
    peers.remove(id);
    requested.remove(id);
    refresh();
  }

  void onPayload(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final raw = utf8.decode(payload.bytes!, allowMalformed: true);
      if (raw.startsWith('{')) {
        handleText(endpointId, payload.bytes!, raw);
      } else {
        // Nom d'un fichier : "payloadId:nom.jpg"
        final i = raw.indexOf(':');
        final pid = i > 0 ? int.tryParse(raw.substring(0, i)) : null;
        if (pid != null) {
          fileNames[pid] = raw.substring(i + 1);
          finishFile(pid);
        }
      }
    } else if (payload.type == PayloadType.FILE) {
      pendingFiles[payload.id] = payload.uri ?? payload.filePath ?? '';
      fileSenders[payload.id] = endpointId;
    }
  }

  void onTransferUpdate(String endpointId, PayloadTransferUpdate update) {
    if (update.status == PayloadStatus.SUCCESS) {
      doneFiles.add(update.id);
      finishFile(update.id);
    }
  }

  void handleText(String fromEndpoint, Uint8List bytes, String raw) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final decision = engine.receive(fromEndpoint, raw, now, onAccept: (p) {
      if (seen.contains(p.id)) return;
      seen.add(p.id);
      remember(_NearbyMessage(
        id: p.id,
        from: shortName(p.from),
        text: p.text,
        mine: false,
        at: DateTime.fromMillisecondsSinceEpoch(
            p.createdMs > 0 ? p.createdMs : now),
      ));
      refresh();
      // Relais limité en nombre de sauts, jamais vers l'expéditeur.
      if (engine.shouldForward(p, now)) {
        broadcast(Uint8List.fromList(p.nextHop().encode()),
            except: fromEndpoint);
      }
    });
    if (decision == RelayDecision.rateLimited) {
      statusText = 'Trop de messages reçus d\'un téléphone : ignorés.';
    }
  }

  Future<void> finishFile(int pid) async {
    if (!pendingFiles.containsKey(pid) ||
        !fileNames.containsKey(pid) ||
        !doneFiles.contains(pid)) {
      return;
    }
    final source = pendingFiles.remove(pid)!;
    final name = fileNames.remove(pid)!;
    final sender = fileSenders.remove(pid);
    doneFiles.remove(pid);

    final dir = await getApplicationDocumentsDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dest = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe';

    var ok = false;
    try {
      ok = await nearby.copyFileAndDeleteOriginal(source, dest);
    } catch (_) {}
    if (!ok) {
      try {
        await File(source).copy(dest);
        ok = true;
      } catch (_) {}
    }
    if (!ok) return;

    remember(_NearbyMessage(
      id: 'file-$pid-${DateTime.now().microsecondsSinceEpoch}',
      from: shortName(endpointNames[sender] ?? 'Inconnu'),
      filePath: dest,
      mine: false,
    ));
    refresh();
  }

  void broadcast(Uint8List data, {String? except}) {
    for (final id in peers.keys) {
      if (id == except) continue;
      try {
        nearby.sendBytesPayload(id, data);
      } catch (_) {}
    }
  }

  void sendText() {
    var text = input.text.trim();
    if (text.isEmpty) return;
    if (text.length > RelayPacket.maxTextLength) {
      text = text.substring(0, RelayPacket.maxTextLength);
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
    seen.add(id);
    engine.seen.add(id);
    final packet = RelayPacket(
      id: id,
      from: uniqueName,
      text: text,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (peers.isEmpty) {
      // Pas de voisin : le message attend et partira dès qu'un téléphone se connecte.
      outbox.add(packet);
      if (outbox.length > 50) outbox.removeAt(0);
      toast('Personne à portée : le message partira dès qu\'un téléphone se connecte.');
    } else {
      relayed[id] = peers.length;
      broadcast(Uint8List.fromList(packet.encode()));
    }
    remember(_NearbyMessage(id: id, from: 'Moi', text: text, mine: true));
    input.clear();
    refresh();
  }

  /// Renvoie les messages en attente (non expirés) au nouveau voisin.
  void flushOutbox() {
    final now = DateTime.now().millisecondsSinceEpoch;
    outbox.removeWhere((p) => p.isExpired(now));
    if (outbox.isEmpty || peers.isEmpty) return;
    for (final p in List<RelayPacket>.from(outbox)) {
      relayed[p.id] = peers.length;
      broadcast(Uint8List.fromList(p.encode()));
    }
    outbox.clear();
  }

  Future<void> sendPhoto() async {
    if (peers.isEmpty) {
      toast('Personne de connecté pour le moment.');
      return;
    }
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (file == null) return;
      final fileName = file.path.split('/').last;
      for (final id in peers.keys.toList()) {
        final pid = await nearby.sendFilePayload(id, file.path);
        await nearby.sendBytesPayload(
          id,
          Uint8List.fromList(utf8.encode('$pid:$fileName')),
        );
      }
      var saved = file.path;
      try {
        final dir = await getApplicationDocumentsDirectory();
        saved = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        await File(file.path).copy(saved);
      } catch (_) {
        saved = file.path;
      }
      remember(_NearbyMessage(
        id: 'mine-${DateTime.now().microsecondsSinceEpoch}',
        from: 'Moi',
        filePath: saved,
        mine: true,
      ));
      refresh();
    } catch (_) {
      toast('Envoi de la photo impossible.');
    }
  }

  @override
  void dispose() {
    if (started) {
      try {
        nearby.stopAdvertising();
        nearby.stopDiscovery();
        nearby.stopAllEndpoints();
      } catch (_) {}
    }
    nickname.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('À proximité'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              tooltip: 'Effacer l\'historique',
              icon: const Icon(Icons.delete_outline),
              onPressed: clearHistory,
            ),
        ],
      ),
      body: started ? chatBody() : welcomeBody(),
    );
  }

  Widget welcomeBody() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                const RadarPulse(size: 220),
                const SizedBox(height: 24),
                const Text(
                  'Sans internet',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Discute avec les téléphones proches, sans internet. '
                  'Les autres doivent ouvrir le Mode proche aussi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: nickname,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    hintText: 'Ton pseudo',
                    counterText: '',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                GradientButton(label: 'Démarrer', onPressed: start),
                const SizedBox(height: 24),
                _infoCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoCard() {
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pour échanger', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          line(Icons.bluetooth, 'Bluetooth et localisation activés sur les deux téléphones.'),
          line(Icons.phone_android, 'L\'autre personne ouvre aussi « À proximité ».'),
          line(Icons.social_distance, 'Portée limitée (quelques dizaines de mètres). Un message peut passer de téléphone en téléphone, sans garantie.'),
          line(Icons.lock_open, 'Les messages de ce mode ne sont pas chiffrés et ne sont pas envoyés au serveur : ils restent sur les téléphones.'),
        ],
      ),
    );
  }

  Widget peersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.surface2)),
      ),
      child: peers.isEmpty
          ? Row(
              children: [
                Icon(Icons.radar, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    outbox.isEmpty
                        ? statusText
                        : '$statusText · ${outbox.length} message(s) en attente',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
                if (failed)
                  TextButton(onPressed: start, child: const Text('Réessayer')),
              ],
            )
          : SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: peers.values.map((unique) {
                  final name = shortName(unique);
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Avatar(name: name, size: 24),
                        const SizedBox(width: 6),
                        Text(name),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            Icon(Icons.portable_wifi_off, size: 64, color: AppColors.muted)
          else
            const RadarPulse(size: 170),
          const SizedBox(height: 16),
          Text(
            failed
                ? 'Impossible de chercher des téléphones.'
                : peers.isEmpty
                    ? 'Recherche de téléphones proches...'
                    : 'Connecté. Dis bonjour 👋',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget chatBody() {
    final shown = messages.reversed.toList();
    return Column(
      children: [
        peersBar(),
        Expanded(
          child: shown.isEmpty
              ? emptyState()
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: shown.length,
                  itemBuilder: (context, index) => bubble(shown[index]),
                ),
        ),
        Composer(
          controller: input,
          onSend: sendText,
          onAttach: sendPhoto,
          hint: 'Message hors ligne...',
          attachIcon: Icons.photo_library_rounded,
          onLike: () {
            input.text = '\u{1F44D}';
            sendText();
          },
        ),
      ],
    );
  }

  Widget bubble(_NearbyMessage m) {
    final bubble = ChatBubble(
      mine: m.mine,
      sender: m.mine ? null : m.from,
      avatarName: m.mine ? null : m.from,
      text: m.text,
      time: formatTime(m.at),
      status: m.mine && m.text != null
          ? (outbox.any((p) => p.id == m.id)
              ? 'En attente d\'un voisin'
              : 'Transmis à ${relayed[m.id] ?? 0} tél. (sans garantie de réception)')
          : null,
      media: m.filePath == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(m.filePath!),
                width: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 220,
                  height: 60,
                  child: Center(child: Text('Fichier reçu')),
                ),
              ),
            ),
    );
    final text = m.text;
    if (text == null || text.isEmpty) return bubble;
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Message copié')));
      },
      child: bubble,
    );
  }
}
