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
  static const videoExt = ['mp4', 'mov', '3gp', 'webm', 'mkv'];

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

  bool isVideo(String url) {
    final clean = url.split('?').first.toLowerCase();
    return videoExt.any(clean.endsWith);
  }

  Widget mediaBubble(String url) {
    if (isVideo(url)) {
      return GestureDetector(
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          width: 210,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill, size: 48),
              SizedBox(height: 6),
              Text('Vidéo · toucher pour lire'),
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
        borderRadius: BorderRadius.circular(12),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(name: widget.receiverName, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.receiverName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
                        Avatar(name: widget.receiverName, size: 72),
                        const SizedBox(height: 14),
                        Text(
                          'Dis bonjour à ${widget.receiverName} 👋',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final item = messages[index];
                    final mediaUrl = item['media_url']?.toString();
                    final created =
                        DateTime.tryParse(item['created_at']?.toString() ?? '')
                            ?.toLocal();
                    return ChatBubble(
                      mine: item['sender'] == uid,
                      text: item['content']?.toString(),
                      media: (mediaUrl != null && mediaUrl.isNotEmpty)
                          ? mediaBubble(mediaUrl)
                          : null,
                      time: formatTime(created),
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
            sending: sending,
          ),
        ],
      ),
    );
  }
}
