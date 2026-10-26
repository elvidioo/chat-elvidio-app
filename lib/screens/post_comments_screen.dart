import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../report.dart';
import '../stories.dart' show agoText;
import '../theme.dart';
import '../widgets.dart';

/// Commentaires d'une publication (mise à jour en direct).
class PostCommentsScreen extends StatefulWidget {
  const PostCommentsScreen({
    super.key,
    required this.postId,
    required this.postAuthor,
  });

  final int postId;
  final String postAuthor;

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final _db = Supabase.instance.client;
  late final String me = _db.auth.currentUser!.id;
  final _text = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  final Map<String, Map<String, dynamic>> _people = {};
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    try {
      _sub = _db
          .from('post_comments')
          .stream(primaryKey: ['id'])
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true)
          .listen((rows) async {
        _comments = List<Map<String, dynamic>>.from(rows);
        await _loadPeople();
        if (mounted) setState(() => _loading = false);
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('post_comments')
          .select('id, post_id, author, content, created_at')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 8));
      _comments = List<Map<String, dynamic>>.from(r);
      await _loadPeople();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPeople() async {
    final ids = _comments
        .map((c) => c['author'].toString())
        .where((id) => !_people.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final ps = await _db.from('profiles').select('id, pseudo, avatar_url').inFilter('id', ids);
      for (final p in ps) {
        _people[p['id'].toString()] = Map<String, dynamic>.from(p);
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final r = await _db
          .from('post_comments')
          .insert({'post_id': widget.postId, 'content': t})
          .select('id, post_id, author, content, created_at')
          .single();
      _text.clear();
      if (!_comments.any((c) => c['id'] == r['id'])) {
        _comments = [..._comments, Map<String, dynamic>.from(r)];
      }
      await _loadPeople();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Commentaire non envoyé. Réessaie dans un instant.')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _options(Map<String, dynamic> c) async {
    final author = c['author'].toString();
    final canDelete = author == me || widget.postAuthor == me;
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Supprimer'),
                onTap: () => Navigator.pop(s, 'delete'),
              ),
            if (author != me)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Signaler'),
                onTap: () => Navigator.pop(s, 'report'),
              ),
          ],
        ),
      ),
    );
    if (v == 'delete') {
      try {
        await _db.from('post_comments').delete().eq('id', c['id']);
        _comments = _comments.where((e) => e['id'] != c['id']).toList();
        if (mounted) setState(() {});
      } catch (_) {}
    } else if (v == 'report' && mounted) {
      showReportDialog(context, kind: 'post', targetUser: author, targetId: widget.postId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Commentaires (${_comments.length})')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? Center(
                        child: Text('Aucun commentaire.\nSois le premier !',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final id = c['author'].toString();
                          final name = id == me
                              ? 'Moi'
                              : (_people[id]?['pseudo']?.toString() ?? 'Utilisateur');
                          final at = DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();
                          return InkWell(
                            onLongPress: () => _options(c),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Avatar(
                                    name: name, size: 38, userId: id,
                                    photoUrl: _people[id]?['avatar_url']?.toString(),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(
                                              child: Text(name,
                                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                                            ),
                                            Text(agoText(at),
                                                style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                          ]),
                                          const SizedBox(height: 2),
                                          LinkText(c['content']?.toString() ?? '',
                                              style: TextStyle(fontSize: 15, color: AppColors.text),
                                              linkColor: AppColors.primary),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Écrire un commentaire…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _sending ? null : _send,
                    icon: Icon(Icons.send_rounded, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
