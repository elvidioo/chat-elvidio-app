import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets.dart';

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
  late final Stream<List<Map<String, dynamic>>> stream = supabase
      .from('messages')
      .stream(primaryKey: ['id']).order('created_at', ascending: false);
  bool sending = false;

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> sendMessage() async {
    final content = messageController.text.trim();
    if (content.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await supabase.from('messages').insert({
        'sender': uid,
        'receiver': widget.receiverId,
        'content': content,
      });
      messageController.clear();
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
      await supabase.from('messages').insert({
        'sender': uid,
        'receiver': widget.receiverId,
        'content': '\u{1F44D}',
      });
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

      await supabase.from('messages').insert({
        'sender': uid,
        'receiver': widget.receiverId,
        'media_url': url,
      });
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
              leading: const Icon(Icons.photo, color: AppColors.cyan),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(sheet);
                sendMedia(video: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.violet),
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
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.surface2),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Erreur de chargement.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Du plus récent au plus ancien (liste inversée).
                final messages = snapshot.data!
                    .where((m) =>
                        (m['sender'] == uid &&
                            m['receiver'] == widget.receiverId) ||
                        (m['sender'] == widget.receiverId &&
                            m['receiver'] == uid))
                    .toList();
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
                        const Text(
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

                    return Column(
                      children: [
                        if (showHeader) TimeHeader(time),
                        ChatBubble(
                          mine: item['sender'] == uid,
                          text: item['content']?.toString(),
                          media: (mediaUrl != null && mediaUrl.isNotEmpty)
                              ? mediaBubble(mediaUrl)
                              : null,
                          avatarName: item['sender'] == uid
                              ? null
                              : widget.receiverName,
                          joinedAbove: !showHeader && sameGroup(item, older),
                          joinedBelow: sameGroup(item, newer),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (sending) const LinearProgressIndicator(minHeight: 2),
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
