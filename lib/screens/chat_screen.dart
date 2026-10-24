import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../media.dart';
import '../presence.dart';
import '../repo.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'contact_profile_screen.dart';
import 'video_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
  });

  final String receiverId;
  final String receiverName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const maxMediaBytes = 50 * 1024 * 1024;

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();
  final messageController = TextEditingController();
  late final String uid = supabase.auth.currentUser!.id;
  bool sending = false;
  final List<Map<String, dynamic>> outbox = [];
  Map<String, dynamic>? replyTo;
  int _lastMarked = -1;

  @override
  void initState() {
    super.initState();
    Repo.I.activePeer = widget.receiverId;
    Repo.I.messages.addListener(markRead);
    markRead();
  }

  /// Marque comme lus les messages reçus de ce contact (si l'option est active).
  void markRead() {
    if (!AppSettings.I.readReceipts.value) return;
    final unread = Repo.I.messages.value
        .where((m) =>
            m['sender'] == widget.receiverId &&
            m['receiver'] == uid &&
            m['read_at'] == null)
        .length;
    if (unread == 0 || unread == _lastMarked) return;
    _lastMarked = unread;
    supabase
        .rpc('mark_read', params: {'peer': widget.receiverId})
        .then((_) {}, onError: (_) {
      _lastMarked = -1;
    });
  }

  Future<void> confirmBlock() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Bloquer ${widget.receiverName} ?'),
        content: const Text(
            'Cette personne sera retirée de tes amis et ne pourra plus t\'écrire. Tu pourras la débloquer dans Paramètres.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bloquer')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Repo.I.blockUser(widget.receiverId);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      toast('Blocage impossible. Réessaie.');
    }
  }

  Map<String, dynamic>? byId(dynamic id) {
    if (id == null) return null;
    for (final m in Repo.I.messages.value) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  String describe(Map<String, dynamic> m) {
    final text = m['content']?.toString() ?? '';
    if (text.isNotEmpty) return text;
    final media = m['media_url']?.toString() ?? '';
    if (media.isEmpty) return '';
    return mediaLabel(media);
  }

  String nameOf(Map<String, dynamic> m) =>
      m['sender'] == uid ? 'Vous' : widget.receiverName;

  Map<String, dynamic> withReply(Map<String, dynamic> row) {
    final r = replyTo;
    if (r != null) row['reply_to'] = r['id'];
    return row;
  }

  void messageActions(Map<String, dynamic> m) {
    final text = m['content']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in const [
                    '\u{1F44D}',
                    '\u2764\uFE0F',
                    '\u{1F602}',
                    '\u{1F62E}',
                    '\u{1F622}',
                    '\u{1F64F}',
                  ])
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(sheet);
                        react(m, e);
                      },
                      child: Text(e, style: const TextStyle(fontSize: 30)),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.reply, color: AppColors.primary),
              title: const Text('Répondre'),
              onTap: () {
                Navigator.pop(sheet);
                setState(() => replyTo = m);
              },
            ),
            if ((m['media_url']?.toString() ?? '').isNotEmpty)
              ListTile(
                leading: Icon(Icons.download, color: AppColors.primary),
                title: const Text('Télécharger'),
                onTap: () {
                  Navigator.pop(sheet);
                  final u = m['media_url'].toString();
                  download(u, fileNameOf(u, m['media_name']?.toString()));
                },
              ),
            if (text.isNotEmpty)
              ListTile(
                leading: Icon(Icons.copy, color: AppColors.primary),
                title: const Text('Copier'),
                onTap: () {
                  Navigator.pop(sheet);
                  Clipboard.setData(ClipboardData(text: text));
                  toast('Message copié');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget replyBar() {
    final r = replyTo;
    if (r == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Réponse à ${nameOf(r)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  describe(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => replyTo = null),
          ),
        ],
      ),
    );
  }

  void toast(String text) {
    if (!mounted) return;
    final t = text.length > 180 ? text.substring(0, 180) : text;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// Le message s'affiche tout de suite ("Envoi…"), puis part en arrière-plan.
  Future<void> sendMessage() async {
    final content = messageController.text.trim();
    if (content.isEmpty) return;
    final local = <String, dynamic>{
      'id': -DateTime.now().microsecondsSinceEpoch,
      'sender': uid,
      'receiver': widget.receiverId,
      'content': content,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'reply_to': replyTo?['id'],
      '_pending': true,
    };
    messageController.clear();
    LivePresence.I.setTyping(null);
    setState(() {
      outbox.insert(0, local);
      replyTo = null;
    });
    await deliver(local);
  }

  Future<void> deliver(Map<String, dynamic> local) async {
    if (mounted) setState(() => local['_failed'] = false);
    try {
      await supabase.from('messages').insert({
        'sender': uid,
        'receiver': widget.receiverId,
        'content': local['content'],
        if (local['reply_to'] != null) 'reply_to': local['reply_to'],
      });
      if (mounted) setState(() => outbox.remove(local));
    } catch (_) {
      if (mounted) setState(() => local['_failed'] = true);
    }
  }

  Future<void> react(Map<String, dynamic> m, String emoji) async {
    final id = (m['id'] as num).toInt();
    if (id < 0) return;
    final mine = Repo.I.reactions.value[id]?[uid];
    try {
      if (mine == emoji) {
        await supabase
            .from('message_reactions')
            .delete()
            .eq('message_id', id)
            .eq('user_id', uid);
      } else {
        await supabase.from('message_reactions').upsert(
          {'message_id': id, 'user_id': uid, 'emoji': emoji},
          onConflict: 'message_id,user_id',
        );
      }
    } catch (_) {
      toast('Réaction impossible.');
    }
  }

  String reactionText(Map<String, dynamic> m) {
    final id = (m['id'] as num).toInt();
    final r = Repo.I.reactions.value[id];
    if (r == null || r.isEmpty) return '';
    final counts = <String, int>{};
    for (final e in r.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} ${e.value}' : e.key)
        .join('  ');
  }

  Future<void> sendLike() async {
    if (sending) return;
    setState(() => sending = true);
    try {
      await supabase.from('messages').insert(withReply({
        'sender': uid,
        'receiver': widget.receiverId,
        'content': '\u{1F44D}',
      }));
      replyTo = null;
    } catch (_) {
      toast('Envoi impossible. Réessaie.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> uploadAndSend(List<int> bytes, String name,
      {String? contentType}) async {
    if (bytes.length > maxMediaBytes) {
      toast('Fichier trop lourd (50 Mo maximum).');
      return;
    }
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await supabase.storage.from('media').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: contentType),
        );
    final url = supabase.storage.from('media').getPublicUrl(path);
    await supabase.from('messages').insert(withReply({
      'sender': uid,
      'receiver': widget.receiverId,
      'media_url': url,
      'media_name': name,
    }));
    replyTo = null;
  }

  Future<void> sendMedia({required bool video}) async {
    if (sending) return;
    try {
      final file = video
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 2),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1280,
              imageQuality: 70,
            );
      if (file == null) return;
      setState(() => sending = true);
      await uploadAndSend(await file.readAsBytes(), file.name,
          contentType: file.mimeType);
    } catch (e) {
      toast('Envoi du fichier impossible. Réessaie. ($e)');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> sendDocument() async {
    if (sending) return;
    try {
      final picked = await openFile();
      if (picked == null) return;
      setState(() => sending = true);
      await uploadAndSend(await picked.readAsBytes(), picked.name);
    } catch (e) {
      toast('Envoi du document impossible. Réessaie. ($e)');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  // ---- Messages vocaux ----
  final recorder = AudioRecorder();
  bool recording = false;
  int recSeconds = 0;
  Timer? recTimer;
  String? recPath;

  Future<void> startRecording() async {
    try {
      if (!await recorder.hasPermission()) {
        toast('Autorise le microphone pour envoyer un vocal.');
        return;
      }
      final dir = await getTemporaryDirectory();
      recPath = '${dir.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: recPath!);
      recSeconds = 0;
      recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => recSeconds++);
      });
      setState(() => recording = true);
    } catch (e) {
      toast('Enregistrement impossible : $e');
    }
  }

  Future<void> stopRecording({required bool send}) async {
    recTimer?.cancel();
    String? path;
    try {
      path = await recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => recording = false);
    if (!send || path == null || recSeconds < 1) return;
    try {
      setState(() => sending = true);
      final bytes = await File(path).readAsBytes();
      await uploadAndSend(bytes, 'vocal.m4a', contentType: 'audio/mp4');
    } catch (e) {
      toast('Envoi du vocal impossible. Réessaie. ($e)');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Widget recordingBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            IconButton(
              onPressed: () => stopRecording(send: false),
              icon: const Icon(Icons.delete, color: Colors.redAccent),
            ),
            const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enregistrement  ${formatDuration(Duration(seconds: recSeconds))}',
                style: TextStyle(color: AppColors.text),
              ),
            ),
            IconButton(
              onPressed: () => stopRecording(send: true),
              icon: Icon(Icons.send_rounded, color: AppColors.primary, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  void pickMedia() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.photo, color: AppColors.cyan),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(sheet);
                sendMedia(video: false);
              },
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: AppColors.violet),
              title: const Text('Vidéo'),
              onTap: () {
                Navigator.pop(sheet);
                sendMedia(video: true);
              },
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file, color: AppColors.primary),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(sheet);
                sendDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> download(String url, String name) async {
    toast('Téléchargement…');
    try {
      final ok = await saveToPhone(url, name);
      if (ok) toast('Fichier enregistré');
    } catch (_) {
      toast('Téléchargement impossible.');
    }
  }

  Widget mediaBubble(String url, String? name, bool mine) {
    if (isAudioUrl(url)) return AudioBubble(url: url, mine: mine);
    if (!isVideoUrl(url) && !isImageUrl(url)) {
      final n = fileNameOf(url, name);
      return FileBubble(
        name: n,
        mine: mine,
        onTap: () async {
          try {
            await openRemoteFile(url, n);
          } catch (_) {
            toast('Ouverture impossible.');
          }
        },
      );
    }
    if (isVideoUrl(url)) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VideoScreen(url: url)),
        ),
        child: Container(
          width: 210,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
              SizedBox(height: 6),
              Text(
                'Vidéo · toucher pour lire',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          url,
          width: 220,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 220,
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 220,
            height: 80,
            child: Center(child: Text('Image indisponible')),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    LivePresence.I.setTyping(null);
    recTimer?.cancel();
    recorder.dispose();
    Repo.I.activePeer = null;
    Repo.I.messages.removeListener(markRead);
    messageController.dispose();
    super.dispose();
  }

  DateTime? createdAt(Map<String, dynamic> m) =>
      DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal();

  bool sameGroup(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return false;
    if (a['sender'] != b['sender']) return false;
    final ta = createdAt(a);
    final tb = createdAt(b);
    if (ta == null || tb == null) return true;
    return ta.difference(tb).abs().inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContactProfileScreen(
                userId: widget.receiverId,
                name: widget.receiverName,
                onMessage: () => Navigator.pop(context),
              ),
            ),
          ),
          child: Row(
          children: [
            Avatar(
              name: widget.receiverName,
              size: 38,
              userId: widget.receiverId,
              showOnline: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge(
                    [LivePresence.I.online, LivePresence.I.typingToMe]),
                builder: (context, _) {
                  final typing =
                      LivePresence.I.typingToMe.value.contains(widget.receiverId);
                  final on = LivePresence.I.online.value.contains(widget.receiverId);
                  DateTime? lastSeen;
                  for (final p in Repo.I.profiles) {
                    if (p['id'].toString() == widget.receiverId) {
                      lastSeen = DateTime.tryParse(p['last_seen']?.toString() ?? '');
                    }
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.receiverName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      if (typing || on || lastSeen != null)
                        Text(
                          typing
                              ? 'est en train d\'écrire…'
                              : (on ? 'En ligne' : lastSeenText(lastSeen)),
                          style: TextStyle(
                            fontSize: 12,
                            color: typing
                                ? AppColors.primary
                                : (on ? AppColors.online : AppColors.muted),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'block') confirmBlock();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'block', child: Text('Bloquer')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.surface2),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable:
                  Listenable.merge([Repo.I.messages, Repo.I.reactions]),
              builder: (context, _) {
                final all = Repo.I.messages.value;
                // Du plus récent au plus ancien (liste inversée).
                final lastMineIndexHolder = <int>[];
                final messages = [
                  ...outbox,
                  ...all.where((m) =>
                        (m['sender'] == uid &&
                            m['receiver'] == widget.receiverId) ||
                        (m['sender'] == widget.receiverId &&
                            m['receiver'] == uid)),
                ];
                for (var i = 0; i < messages.length; i++) {
                  if (messages[i]['sender'] == uid) {
                    lastMineIndexHolder.add(i);
                    break;
                  }
                }
                final lastMine =
                    lastMineIndexHolder.isEmpty ? -1 : lastMineIndexHolder[0];
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(name: widget.receiverName, size: 80, userId: widget.receiverId),
                        const SizedBox(height: 12),
                        Text(
                          widget.receiverName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dis bonjour \u{1F44B}',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final item = messages[index];
                    final older =
                        index + 1 < messages.length ? messages[index + 1] : null;
                    final newer = index > 0 ? messages[index - 1] : null;
                    final mediaUrl = item['media_url']?.toString();
                    final time = createdAt(item);
                    final olderTime = older == null ? null : createdAt(older);
                    final showHeader = time != null &&
                        (olderTime == null ||
                            time.difference(olderTime).inMinutes >= 30);

                    final quoted = byId(item['reply_to']);
                    final isMine = item['sender'] == uid;
                    String? status;
                    var isRead = false;
                    if (isMine) {
                      isRead = item['read_at'] != null &&
                          AppSettings.I.readReceipts.value;
                      status = isRead ? '\u2713\u2713' : '\u2713';
                      if (index == lastMine) {
                        status = isRead ? '\u2713\u2713 Vu' : '\u2713 Envoyé';
                      }
                      if (item['_pending'] == true) {
                        status = item['_failed'] == true
                            ? 'Non envoyé \u00B7 toucher pour réessayer'
                            : 'Envoi…';
                      }
                    }

                    return Column(
                      children: [
                        if (showHeader) TimeHeader(time),
                        Dismissible(
                          key: ValueKey('m${item['id']}'),
                          direction: DismissDirection.startToEnd,
                          confirmDismiss: (_) async {
                            setState(() => replyTo = item);
                            return false;
                          },
                          background: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Icon(Icons.reply, color: AppColors.muted),
                            ),
                          ),
                          child: GestureDetector(
                            onTap: item['_failed'] == true
                                ? () => deliver(item)
                                : null,
                            onLongPress: item['_pending'] == true
                                ? null
                                : () => messageActions(item),
                            child: ChatBubble(
                              mine: isMine,
                              text: item['content']?.toString(),
                              media: (mediaUrl != null && mediaUrl.isNotEmpty)
                                  ? mediaBubble(mediaUrl, item['media_name']?.toString(), isMine)
                                  : null,
                              avatarName: isMine ? null : widget.receiverName,
                              avatarId: isMine ? null : widget.receiverId,
                              quoteName: quoted == null ? null : nameOf(quoted),
                              quoteText: quoted == null
                                  ? (item['reply_to'] != null
                                      ? 'Message indisponible'
                                      : null)
                                  : describe(quoted),
                              status: status,
                              reactions: item['_pending'] == true
                                  ? null
                                  : reactionText(item),
                              read: isRead,
                              joinedAbove:
                                  !showHeader && sameGroup(item, older),
                              joinedBelow: sameGroup(item, newer),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (sending) const LinearProgressIndicator(minHeight: 2),
          replyBar(),
          if (recording) recordingBar() else Composer(
            controller: messageController,
            onSend: sendMessage,
            onAttach: pickMedia,
            onLike: sendLike,
            onMic: startRecording,
            onTyping: () => LivePresence.I.setTyping(widget.receiverId),
            sending: sending,
          ),
        ],
      ),
    );
  }
}
