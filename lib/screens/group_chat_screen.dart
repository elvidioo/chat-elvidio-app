import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../media.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'group_info_screen.dart';
import 'video_screen.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _db = Supabase.instance.client;
  final _text = TextEditingController();
  late final String uid = _db.auth.currentUser!.id;
  final Map<String, String> _names = {};
  bool _sending = false;

  dynamic get gid => widget.group['id'];
  String get groupName => widget.group['name']?.toString() ?? 'Groupe';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final r = await _db
          .from('group_members')
          .select('user_id, profiles(pseudo)')
          .eq('group_id', gid);
      for (final m in r) {
        _names[m['user_id'].toString()] =
            (m['profiles'] as Map?)?['pseudo']?.toString() ?? 'Utilisateur';
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _name(String id) => id == uid
      ? 'Vous'
      : (_names[id] ?? Repo.I.names[id] ?? 'Utilisateur');

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _insert(Map<String, dynamic> row) async {
    await _db.from('group_messages').insert({'group_id': gid, ...row});
  }

  Future<void> _sendText() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _insert({'content': content});
      _text.clear();
    } catch (_) {
      _toast('Envoi impossible. Réessaie.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _upload(List<int> bytes, String name, {String? type}) async {
    if (bytes.length > 50 * 1024 * 1024) {
      _toast('Fichier trop lourd (50 Mo maximum).');
      return;
    }
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db.storage.from('media').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: type),
        );
    await _insert({
      'media_url': _db.storage.from('media').getPublicUrl(path),
      'media_name': name,
    });
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(Icons.photo, color: AppColors.cyan),
            title: const Text('Photo'),
            onTap: () => Navigator.pop(c, 'photo'),
          ),
          ListTile(
            leading: Icon(Icons.videocam, color: AppColors.violet),
            title: const Text('Vidéo'),
            onTap: () => Navigator.pop(c, 'video'),
          ),
          ListTile(
            leading: Icon(Icons.insert_drive_file, color: AppColors.primary),
            title: const Text('Document'),
            onTap: () => Navigator.pop(c, 'doc'),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    try {
      setState(() => _sending = true);
      if (choice == 'doc') {
        final f = await openFile();
        if (f != null) await _upload(await f.readAsBytes(), f.name);
      } else {
        final picker = ImagePicker();
        final f = choice == 'video'
            ? await picker.pickVideo(
                source: ImageSource.gallery,
                maxDuration: const Duration(minutes: 2))
            : await picker.pickImage(
                source: ImageSource.gallery, maxWidth: 1280, imageQuality: 70);
        if (f != null) await _upload(await f.readAsBytes(), f.name, type: f.mimeType);
      }
    } catch (e) {
      _toast('Envoi du fichier impossible ($e)');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _media(String url, String? name, bool mine) {
    if (isAudioUrl(url)) return AudioBubble(url: url, mine: mine);
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
          child: const Center(
            child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
          ),
        ),
      );
    }
    if (isImageUrl(url)) {
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
          child: Image.network(url, width: 220, fit: BoxFit.cover),
        ),
      );
    }
    final n = fileNameOf(url, name);
    return FileBubble(
      name: n,
      mine: mine,
      onTap: () async {
        try {
          await openRemoteFile(url, n);
        } catch (_) {
          _toast('Ouverture impossible.');
        }
      },
    );
  }

  DateTime? _at(Map<String, dynamic> m) =>
      DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal();

  bool _same(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return false;
    if (a['sender'] != b['sender']) return false;
    final ta = _at(a);
    final tb = _at(b);
    if (ta == null || tb == null) return true;
    return ta.difference(tb).abs().inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupInfoScreen(group: widget.group),
              ),
            );
            if (mounted) {
              _loadMembers();
              setState(() {});
            }
          },
          child: Row(children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.groups, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(groupName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: Repo.I.groupMessages,
              builder: (context, all, _) {
                final msgs =
                    all.where((m) => m['group_id'] == gid).toList();
                if (msgs.isEmpty) {
                  return Center(
                    child: Text('Écris le premier message \u{1F44B}',
                        style: TextStyle(color: AppColors.muted)),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                    final newer = i > 0 ? msgs[i - 1] : null;
                    final mine = m['sender'] == uid;
                    final time = _at(m);
                    final olderTime = older == null ? null : _at(older);
                    final showHeader = time != null &&
                        (olderTime == null ||
                            time.difference(olderTime).inMinutes >= 30);
                    final url = m['media_url']?.toString() ?? '';
                    final text = m['content']?.toString() ?? '';
                    final sid = m['sender'].toString();
                    return Column(children: [
                      if (showHeader) TimeHeader(time),
                      GestureDetector(
                        onLongPress: text.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: text));
                                _toast('Message copié');
                              },
                        child: ChatBubble(
                          mine: mine,
                          sender: (!mine && !(!showHeader && _same(m, older)))
                              ? _name(sid)
                              : null,
                          text: text,
                          media: url.isEmpty
                              ? null
                              : _media(url, m['media_name']?.toString(), mine),
                          avatarName: mine ? null : _name(sid),
                          avatarId: mine ? null : sid,
                          joinedAbove: !showHeader && _same(m, older),
                          joinedBelow: _same(m, newer),
                        ),
                      ),
                    ]);
                  },
                );
              },
            ),
          ),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          Composer(
            controller: _text,
            onSend: _sendText,
            onAttach: _attach,
            sending: _sending,
          ),
        ],
      ),
    );
  }
}
