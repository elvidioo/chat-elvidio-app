import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _serviceId = 'com.elvidio.chat.nearby';

class _NearbyMessage {
  final String id;
  final String from;
  final String? text;
  final String? filePath;
  final bool mine;

  _NearbyMessage({
    required this.id,
    required this.from,
    required this.mine,
    this.text,
    this.filePath,
  });
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
  String statusText = '';

  final peers = <String, String>{}; // endpointId -> nom unique (connectés)
  final endpointNames = <String, String>{}; // endpointId -> nom unique
  final requested = <String>{};
  final messages = <_NearbyMessage>[];
  final seen = <String>{};

  final pendingFiles = <int, String>{}; // payloadId -> uri ou chemin reçu
  final fileSenders = <int, String>{}; // payloadId -> endpointId
  final fileNames = <int, String>{}; // payloadId -> nom du fichier
  final doneFiles = <int>{};

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
      setState(() => statusText =
          'Autorise la localisation et le Bluetooth pour trouver les téléphones proches.');
      return;
    }

    try {
      if (!await nearby.checkLocationEnabled()) {
        await nearby.enableLocationServices();
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
      setState(() => statusText =
          'Impossible de démarrer (Bluetooth et localisation activés ?).');
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
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final id = data['id'].toString();
      if (!seen.add(id)) return; // déjà reçu : on évite les boucles
      messages.add(_NearbyMessage(
        id: id,
        from: shortName(data['from'].toString()),
        text: data['text']?.toString(),
        mine: false,
      ));
      refresh();
      // Relais : on transmet aux autres téléphones connectés.
      broadcast(bytes, except: fromEndpoint);
    } catch (_) {}
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

    messages.add(_NearbyMessage(
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
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (peers.isEmpty) {
      toast('Personne de connecté pour le moment.');
      return;
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
    seen.add(id);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'id': id,
      'from': uniqueName,
      'text': text.length > 2000 ? text.substring(0, 2000) : text,
    })));
    broadcast(bytes);
    messages.add(_NearbyMessage(
      id: id,
      from: 'Moi',
      text: text,
      mine: true,
    ));
    input.clear();
    refresh();
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
      messages.add(_NearbyMessage(
        id: 'mine-${DateTime.now().microsecondsSinceEpoch}',
        from: 'Moi',
        filePath: file.path,
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
      appBar: AppBar(title: const Text('Mode proche (sans internet)')),
      body: started ? chatBody() : welcomeBody(),
    );
  }

  Widget welcomeBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi_tethering, size: 64, color: Color(0xFF00E5FF)),
          const SizedBox(height: 16),
          const Text(
            'Discute avec les téléphones proches, sans internet. '
            'Les autres doivent ouvrir le Mode proche aussi.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: nickname,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Ton pseudo',
              border: OutlineInputBorder(),
            ),
          ),
          FilledButton(onPressed: start, child: const Text('Démarrer')),
        ],
      ),
    );
  }

  Widget chatBody() {
    final shown = messages.reversed.toList();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1B1D2E),
          child: Text(
            peers.isEmpty
                ? statusText
                : 'Connectés (${peers.length}) : '
                    '${peers.values.map(shortName).join(', ')}',
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('Aucun message pour le moment.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: shown.length,
                  itemBuilder: (context, index) => bubble(shown[index]),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                IconButton(
                  onPressed: sendPhoto,
                  icon: const Icon(Icons.photo),
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Message hors ligne...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => sendText(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sendText,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget bubble(_NearbyMessage m) {
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: m.mine ? const Color(0xFF006B78) : const Color(0xFF292B3D),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!m.mine)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  m.from,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00E5FF),
                  ),
                ),
              ),
            if (m.filePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
            if (m.text != null && m.text!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(m.text!),
              ),
          ],
        ),
      ),
    );
  }
}
