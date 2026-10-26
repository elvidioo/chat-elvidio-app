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
  Map<String, dynamic>? _replyTo; // commentaire principal auquel on répond
  final _focus = FocusNode();

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
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('post_comments')
          .select('id, post_id, author, content, created_at, parent_id')
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
          .insert({
            'post_id': widget.postId,
            'content': t,
            if (_replyTo != null) 'parent_id': _replyTo!['id'],
          })
          .select('id, post_id, author, content, created_at, parent_id')
          .single();
      _text.clear();
      _replyTo = null;
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
        _comments = _comments
            .where((e) => e['id'] != c['id'] && e['parent_id'] != c['id'])
            .toList();
        if (mounted) setState(() {});
      } catch (_) {}
    } else if (v == 'report' && mounted) {
      showReportDialog(context, kind: 'post', targetUser: author, targetId: widget.postId);
    }
  }

  String _nameOf(String id) =>
      id == me ? 'moi' : (_people[id]?['pseudo']?.toString() ?? 'Utilisateur');

  Widget _tile(Map<String, dynamic> c, bool reply, {Map<String, dynamic>? parent}) {
    final id = c['author'].toString();
    final name = id == me ? 'Moi' : (_people[id]?['pseudo']?.toString() ?? 'Utilisateur');
    final at = DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();
    return InkWell(
      onLongPress: () => _options(c),
      child: Padding(
        padding: EdgeInsets.fromLTRB(reply ? 54 : 12, 6, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(
              name: name, size: reply ? 30 : 38, userId: id,
              photoUrl: _people[id]?['avatar_url']?.toString(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        LinkText(c['content']?.toString() ?? '',
                            style: TextStyle(fontSize: 15, color: AppColors.text),
                            linkColor: AppColors.primary),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 12, 0),
                        child: Text(agoText(at),
                            style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _replyTo = parent ?? c);
                          _focus.requestFocus();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Répondre',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final c in _comments.where((e) => e['parent_id'] == null)) ...[
                            _tile(c, false),
                            for (final r in _comments.where((e) => e['parent_id'] == c['id']))
                              _tile(r, true, parent: c),
                          ],
                        ],
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Réponse à ${_nameOf(_replyTo!['author'].toString())}',
                              style: TextStyle(color: AppColors.muted, fontSize: 13),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _replyTo = null),
                            child: Icon(Icons.close, size: 18, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _replyTo == null ? 'Écrire un commentaire…' : 'Écrire une réponse…',
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
