import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../media.dart';
import '../media_url.dart';
import '../report.dart';
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
    Repo.I.activeGroup = gid;
    _loadMembers();
  }

  @override
  void dispose() {
    if (Repo.I.activeGroup == gid) Repo.I.activeGroup = null;
    _recTimer?.cancel();
    _recorder.dispose();
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

  // ---- Messages vocaux ----
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recSeconds = 0;
  Timer? _recTimer;

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Autorise le microphone pour envoyer un vocal.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      _recSeconds = 0;
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSeconds++);
      });
      setState(() => _recording = true);
    } catch (e) {
      _toast('Enregistrement impossible : $e');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (!send || path == null || _recSeconds < 1) return;
    try {
      setState(() => _sending = true);
      await _upload(await File(path).readAsBytes(), 'vocal.m4a',
          type: 'audio/mp4');
    } catch (e) {
      _toast('Envoi du vocal impossible ($e)');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _recordingBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(children: [
          IconButton(
            onPressed: () => _stopRecording(send: false),
            icon: const Icon(Icons.delete, color: Colors.redAccent),
          ),
          const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Enregistrement  ${formatDuration(Duration(seconds: _recSeconds))}',
              style: TextStyle(color: AppColors.text),
            ),
          ),
          IconButton(
            onPressed: () => _stopRecording(send: true),
            icon: Icon(Icons.send_rounded, color: AppColors.primary, size: 28),
          ),
        ]),
      ),
    );
  }

  // ---- Réactions ----
  Future<void> _react(Map<String, dynamic> m, String emoji) async {
    final id = (m['id'] as num).toInt();
    final mine = Repo.I.groupReactions.value[id]?[uid];
    try {
      if (mine == emoji) {
        await _db
            .from('group_message_reactions')
            .delete()
            .eq('message_id', id)
            .eq('user_id', uid);
      } else {
        await _db.from('group_message_reactions').upsert(
          {'message_id': id, 'user_id': uid, 'emoji': emoji},
          onConflict: 'message_id,user_id',
        );
      }
    } catch (_) {
      _toast('Réaction impossible.');
    }
  }

  String _reactionText(Map<String, dynamic> m) {
    final r = Repo.I.groupReactions.value[(m['id'] as num).toInt()];
    if (r == null || r.isEmpty) return '';
    final counts = <String, int>{};
    for (final e in r.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} ${e.value}' : e.key)
        .join('  ');
  }

  Future<void> _edit(Map<String, dynamic> m) async {
    final ctrl = TextEditingController(text: m['content']?.toString() ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value.isEmpty || value == m['content']) return;
    try {
      await _db.rpc('edit_group_message',
          params: {'mid': (m['id'] as num).toInt(), 'new_content': value});
    } catch (_) {
      _toast('Modification impossible.');
    }
  }

  void _actions(Map<String, dynamic> m) {
    final text = m['content']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheet) => SafeArea(
        child: Wrap(children: [
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
                      _react(m, e);
                    },
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ),
              ],
            ),
          ),
          if (m['sender'] != uid)
            ListTile(
              leading: Icon(Icons.flag_outlined, color: AppColors.muted),
              title: const Text('Signaler ce message'),
              onTap: () {
                Navigator.pop(sheet);
                showReportDialog(context,
                    kind: 'group_message',
                    targetUser: m['sender'].toString(),
                    targetId: (m['id'] as num).toInt());
              },
            ),
          if (m['sender'] == uid &&
              text.isNotEmpty &&
              (m['media_url']?.toString() ?? '').isEmpty)
            ListTile(
              leading: Icon(Icons.edit, color: AppColors.primary),
              title: const Text('Modifier'),
              onTap: () {
                Navigator.pop(sheet);
                _edit(m);
              },
            ),
          if (text.isNotEmpty)
            ListTile(
              leading: Icon(Icons.copy, color: AppColors.primary),
              title: const Text('Copier'),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: text));
                _toast('Message copié');
              },
            ),
        ]),
      ),
    );
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
            child: InteractiveViewer(child: SignedImage(url)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SignedImage(url, width: 220, fit: BoxFit.cover),
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
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [Repo.I.groupMessages, Repo.I.groupReactions]),
              builder: (context, _) {
                final all = Repo.I.groupMessages.value;
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
                        onLongPress: () => _actions(m),
                        child: ChatBubble(
                          mine: mine,
                          sender: (!mine && !(!showHeader && _same(m, older)))
                              ? _name(sid)
                              : null,
                          text: text,
                          reactions: _reactionText(m),
                          status: m['edited_at'] != null ? 'modifié' : null,
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
          if (_recording) _recordingBar() else Composer(
            controller: _text,
            onSend: _sendText,
            onAttach: _attach,
            onMic: _startRecording,
            sending: _sending,
          ),
        ],
      ),
    );
  }
}
