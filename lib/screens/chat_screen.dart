import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
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
    return isVideoUrl(media) ? '\u{1F3A5} Vidéo' : '\u{1F4F7} Photo';
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
            ListTile(
              leading: Icon(Icons.reply, color: AppColors.primary),
              title: const Text('Répondre'),
              onTap: () {
                Navigator.pop(sheet);
                setState(() => replyTo = m);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> sendMessage() async {
    final content = messageController.text.trim();
    if (content.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await supabase.from('messages').insert(withReply({
        'sender': uid,
        'receiver': widget.receiverId,
        'content': content,
      }));
      messageController.clear();
      replyTo = null;
    } catch (_) {
      toast('Envoi impossible. Réessaie.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
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

      final bytes = await file.readAsBytes();
      if (bytes.length > maxMediaBytes) {
        toast('Fichier trop lourd (50 Mo maximum).');
        return;
      }

      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await supabase.storage.from('media').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: file.mimeType),
          );
      final url = supabase.storage.from('media').getPublicUrl(path);

      await supabase.from('messages').insert(withReply({
        'sender': uid,
        'receiver': widget.receiverId,
        'media_url': url,
      }));
      replyTo = null;
    } catch (_) {
      toast('Envoi du fichier impossible. Réessaie.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
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
          ],
        ),
      ),
    );
  }

  Widget mediaBubble(String url) {
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
        title: Row(
          children: [
            Avatar(name: widget.receiverName, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.receiverName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.surface2),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: Repo.I.messages,
              builder: (context, all, _) {
                // Du plus récent au plus ancien (liste inversée).
                final lastMineIndexHolder = <int>[];
                final messages = all
                    .where((m) =>
                        (m['sender'] == uid &&
                            m['receiver'] == widget.receiverId) ||
                        (m['sender'] == widget.receiverId &&
                            m['receiver'] == uid))
                    .toList();
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
                        Avatar(name: widget.receiverName, size: 80),
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
                            onLongPress: () => messageActions(item),
                            child: ChatBubble(
                              mine: isMine,
                              text: item['content']?.toString(),
                              media: (mediaUrl != null && mediaUrl.isNotEmpty)
                                  ? mediaBubble(mediaUrl)
                                  : null,
                              avatarName: isMine ? null : widget.receiverName,
                              quoteName: quoted == null ? null : nameOf(quoted),
                              quoteText: quoted == null
                                  ? (item['reply_to'] != null
                                      ? 'Message indisponible'
                                      : null)
                                  : describe(quoted),
                              status: status,
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
          Composer(
            controller: messageController,
            onSend: sendMessage,
            onAttach: pickMedia,
            onLike: sendLike,
            sending: sending,
          ),
        ],
      ),
    );
  }
}
