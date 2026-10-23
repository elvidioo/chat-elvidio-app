import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../media.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_post_screen.dart';
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
    } catch (_) {
      _error = 'Impossible de charger le fil. Vérifie ta connexion.';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _name(String id) => id == uid
      ? 'Moi'
      : (_people[id]?['pseudo']?.toString() ?? 'Utilisateur');

  Future<void> _compose(bool status) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComposePostScreen(status: status)),
    );
    if (ok == true) _load();
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
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
      child: Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 80,
          child: Center(child: Text('Image indisponible')),
        ),
      ),
    );
  }

  Widget _statusRow(List<Map<String, dynamic>> statuses) {
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _statusCircle('Mon statut', uid, null, onTap: () => _compose(true), add: true),
          for (final s in statuses)
            _statusCircle(_name(s['author'].toString()), s['author'].toString(), s,
                onTap: () => _showStatus(s)),
        ],
      ),
    );
  }

  Widget _statusCircle(String label, String id, Map<String, dynamic>? s,
      {required VoidCallback onTap, bool add = false}) {
    final name = add ? (_people[uid]?['pseudo']?.toString() ?? 'Moi') : label;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: add ? AppColors.muted : AppColors.primary,
                  width: 2,
                ),
              ),
              child: add
                  ? CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.surface2,
                      child: Icon(Icons.add, color: AppColors.primary),
                    )
                  : Avatar(name: name, size: 52, userId: id,
                      photoUrl: _people[id]?['avatar_url']?.toString()),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _showStatus(Map<String, dynamic> s) {
    final url = s['media_url']?.toString() ?? '';
    final text = s['content']?.toString() ?? '';
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Avatar(name: _name(s['author'].toString()), size: 36,
                    userId: s['author'].toString(),
                    photoUrl: _people[s['author'].toString()]?['avatar_url']?.toString()),
                const SizedBox(width: 10),
                Expanded(child: Text(_name(s['author'].toString()),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
              ]),
              if (url.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(12), child: _media(url)),
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LinkText(text,
                      style: TextStyle(fontSize: 16, color: AppColors.text),
                      linkColor: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
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
                : null,
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LinkText(text,
                  style: TextStyle(fontSize: 16, height: 1.35, color: AppColors.text),
                  linkColor: AppColors.primary),
            ),
          if (url.isNotEmpty) _media(url),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _posts.where((p) => p['kind'] == 'status').toList();
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
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Fil',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              _statusRow(statuses),
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
