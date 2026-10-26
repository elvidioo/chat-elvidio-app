import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../report.dart';
import '../media_url.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_post_screen.dart';
import 'post_comments_screen.dart';
import 'story_cards.dart';
import 'video_screen.dart';

/// Fil d'actualité : statuts (24 h) et publications de mes amis.
class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final _db = Supabase.instance.client;
  late final String uid = _db.auth.currentUser!.id;
  List<Map<String, dynamic>> _posts = [];
  final Map<String, Map<String, dynamic>> _people = {};
  final Map<int, Map<String, String>> _reacts = {};
  final Map<int, int> _commentCounts = {};
  final _cardsKey = GlobalKey<StoryCardsState>();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('posts')
          .select('id, author, content, media_url, media_name, kind, created_at, expires_at')
          .eq('kind', 'post')
          .order('created_at', ascending: false)
          .limit(60)
          .timeout(const Duration(seconds: 8));
      _posts = List<Map<String, dynamic>>.from(r);
      final ids = _posts.map((p) => p['author'].toString()).toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await _db
            .from('profiles')
            .select('id, pseudo, avatar_url')
            .inFilter('id', ids);
        for (final p in ps) {
          _people[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }
      _error = null;
      await _loadReactions();
      await _loadCommentCounts();
    } catch (_) {
      _error = 'Impossible de charger le fil. Vérifie ta connexion.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadReactions() async {
    try {
      final ids = _posts.map((p) => p['id']).toList();
      if (ids.isEmpty) return;
      final r = await _db
          .from('post_reactions')
          .select('post_id, user_id, emoji')
          .inFilter('post_id', ids);
      _reacts.clear();
      for (final e in r) {
        (_reacts[(e['post_id'] as num).toInt()] ??= {})[e['user_id'].toString()] =
            e['emoji'].toString();
      }
    } catch (_) {}
  }

  Future<void> _loadCommentCounts() async {
    try {
      final ids = _posts.where((p) => p['kind'] == 'post').map((p) => p['id']).toList();
      if (ids.isEmpty) return;
      final r = await _db.rpc('post_comment_counts', params: {'ids': ids});
      _commentCounts.clear();
      for (final e in r as List) {
        _commentCounts[(e['post_id'] as num).toInt()] = (e['n'] as num).toInt();
      }
    } catch (_) {}
  }

  Future<void> _openComments(Map<String, dynamic> p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostCommentsScreen(
            postId: (p['id'] as num).toInt(), postAuthor: p['author'].toString()),
      ),
    );
    await _loadCommentCounts();
    if (mounted) setState(() {});
  }

  /// Liste de ceux qui ont réagi, avec leur réaction.
  void _showReactors(Map<String, dynamic> p) {
    final id = (p['id'] as num).toInt();
    final r = _reacts[id] ?? {};
    if (r.isEmpty) return;
    final ids = r.keys.toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => FutureBuilder<List<dynamic>>(
        future: _db.from('profiles').select('id, pseudo, avatar_url').inFilter('id', ids),
        builder: (c, snap) {
          final profs = {
            for (final e in snap.data ?? const []) e['id'].toString(): e as Map
          };
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('${ids.length} réaction${ids.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final uidR in ids)
                          ListTile(
                            leading: Avatar(
                              name: uidR == uid ? 'Moi' : (profs[uidR]?['pseudo']?.toString() ?? '?'),
                              size: 40, userId: uidR,
                              photoUrl: profs[uidR]?['avatar_url']?.toString(),
                            ),
                            title: Text(uidR == uid
                                ? 'Moi'
                                : (profs[uidR]?['pseudo']?.toString() ?? 'Utilisateur')),
                            trailing: Text(r[uidR] ?? '', style: const TextStyle(fontSize: 26)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _react(Map<String, dynamic> p, String emoji) async {
    final id = (p['id'] as num).toInt();
    final mine = _reacts[id]?[uid];
    try {
      if (mine == emoji) {
        await _db
            .from('post_reactions')
            .delete()
            .eq('post_id', id)
            .eq('user_id', uid);
        _reacts[id]?.remove(uid);
      } else {
        await _db.from('post_reactions').upsert(
          {'post_id': id, 'user_id': uid, 'emoji': emoji},
          onConflict: 'post_id,user_id',
        );
        (_reacts[id] ??= {})[uid] = emoji;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _pickReaction(Map<String, dynamic> p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    _react(p, e);
                  },
                  child: Text(e, style: const TextStyle(fontSize: 32)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reactionBar(Map<String, dynamic> p) {
    final pid = (p['id'] as num).toInt();
    final r = _reacts[pid] ?? {};
    final counts = <String, int>{};
    for (final e in r.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final emojis = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final mine = r[uid];
    final nComments = _commentCounts[pid] ?? 0;
    return Column(
      children: [
        if (r.isNotEmpty || nComments > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                if (r.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showReactors(p),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emojis.take(3).map((e) => e.key).join(),
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text('${r.length}', style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                const Spacer(),
                if (nComments > 0)
                  GestureDetector(
                    onTap: () => _openComments(p),
                    child: Text('$nComments commentaire${nComments == 1 ? '' : 's'}',
                        style: TextStyle(color: AppColors.muted)),
                  ),
              ],
            ),
          ),
        Divider(height: 1, color: AppColors.surface2),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _pickReaction(p),
                icon: mine == null
                    ? Icon(Icons.thumb_up_alt_outlined, color: AppColors.muted)
                    : Text(mine, style: const TextStyle(fontSize: 18)),
                label: Text(mine == null ? 'Réagir' : 'Modifier',
                    style: TextStyle(color: AppColors.muted)),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _openComments(p),
                icon: Icon(Icons.chat_bubble_outline, color: AppColors.muted),
                label: Text('Commenter', style: TextStyle(color: AppColors.muted)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _name(String id) => id == uid
      ? 'Moi'
      : (_people[id]?['pseudo']?.toString() ?? 'Utilisateur');

  Future<void> _compose(bool status) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComposePostScreen(status: status)),
    );
    if (ok == true) {
      _load();
      _cardsKey.currentState?.reload();
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Cette publication sera supprimée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _db.from('posts').delete().eq('id', p['id']);
      _load();
    } catch (_) {}
  }

  Widget _media(String url) {
    if (isVideoUrl(url)) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VideoScreen(url: url)),
        ),
        child: Container(
          height: 200,
          color: Colors.black87,
          child: const Center(
            child: Icon(Icons.play_circle_fill, size: 56, color: Colors.white),
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
          child: InteractiveViewer(child: SignedImage(url)),
        ),
      ),
      child: SignedImage(url, width: double.infinity, fit: BoxFit.cover),
    );
  }

  Widget _post(Map<String, dynamic> p) {
    final id = p['author'].toString();
    final url = p['media_url']?.toString() ?? '';
    final text = p['content']?.toString() ?? '';
    final time = DateTime.tryParse(p['created_at']?.toString() ?? '')?.toLocal();
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Avatar(name: _name(id), size: 42, userId: id,
                photoUrl: _people[id]?['avatar_url']?.toString()),
            title: Text(_name(id), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(formatListTime(time), style: TextStyle(color: AppColors.muted)),
            trailing: id == uid
                ? IconButton(onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline))
                : IconButton(
                    tooltip: 'Signaler',
                    onPressed: () => showReportDialog(context,
                        kind: 'post',
                        targetUser: id,
                        targetId: (p['id'] as num).toInt()),
                    icon: Icon(Icons.flag_outlined, color: AppColors.muted),
                  ),
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LinkText(text,
                  style: TextStyle(fontSize: 16, height: 1.35, color: AppColors.text),
                  linkColor: AppColors.primary),
            ),
          if (url.isNotEmpty) _media(url),
          _reactionBar(p),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts.where((p) => p['kind'] == 'post').toList();
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _compose(false),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.edit, color: Colors.white),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            _cardsKey.currentState?.reload();
            await _load();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Fil',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              StoryCards(key: _cardsKey),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_error!))),
              if (!_loading && _error == null && posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Aucune publication pour le moment.\nAjoute des amis ou publie quelque chose avec le bouton crayon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              for (final p in posts) _post(p),
            ],
          ),
        ),
      ),
    );
  }
}
