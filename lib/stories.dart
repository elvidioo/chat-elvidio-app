import 'package:supabase_flutter/supabase_flutter.dart';

/// Une story (statut de 24 h).
class Story {
  Story(this.row);
  final Map<String, dynamic> row;

  int get id => (row['id'] as num).toInt();
  String get author => row['author'].toString();
  String get text => row['content']?.toString() ?? '';
  String get mediaUrl => row['media_url']?.toString() ?? '';
  DateTime? get createdAt =>
      DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
}

/// Toutes les stories d'une même personne, de la plus ancienne à la plus récente.
class StoryGroup {
  StoryGroup(this.author, this.stories, this.seenIds);
  final String author;
  final List<Story> stories;
  final Set<int> seenIds;

  int get unseen => stories.where((s) => !seenIds.contains(s.id)).length;
  bool get allSeen => unseen == 0;

  /// Première story non vue (sinon la première).
  int get firstUnseenIndex {
    final i = stories.indexWhere((s) => !seenIds.contains(s.id));
    return i < 0 ? 0 : i;
  }
}

/// Charge les stories visibles, groupées par auteur : les miennes d'abord,
/// puis les non vues, puis les déjà vues.
class StoryService {
  static final _db = Supabase.instance.client;

  static Future<List<StoryGroup>> load() async {
    final me = _db.auth.currentUser!.id;
    final rows = await _db
        .from('posts')
        .select('id, author, content, media_url, media_name, kind, created_at, expires_at')
        .eq('kind', 'status')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: true)
        .limit(200)
        .timeout(const Duration(seconds: 8));
    final byAuthor = <String, List<Story>>{};
    for (final r in rows) {
      final s = Story(Map<String, dynamic>.from(r));
      (byAuthor[s.author] ??= []).add(s);
    }
    final seen = <int>{};
    try {
      final v = await _db
          .from('story_views')
          .select('post_id')
          .eq('viewer', me)
          .timeout(const Duration(seconds: 8));
      for (final e in v) {
        seen.add((e['post_id'] as num).toInt());
      }
    } catch (_) {}
    final groups = [
      for (final e in byAuthor.entries) StoryGroup(e.key, e.value, seen)
    ];
    int rank(StoryGroup g) => g.author == me ? 0 : (g.allSeen ? 2 : 1);
    groups.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return b.stories.last.createdAt?.compareTo(a.stories.last.createdAt ?? DateTime(0)) ?? 0;
    });
    return groups;
  }

  /// Note que j'ai vu cette story (sans effet pour mes propres stories).
  static Future<void> markSeen(Story s) async {
    final me = _db.auth.currentUser?.id;
    if (me == null || s.author == me) return;
    try {
      await _db.from('story_views').upsert(
        {'post_id': s.id, 'viewer': me},
        onConflict: 'post_id,viewer',
        ignoreDuplicates: true,
      );
    } catch (_) {}
  }
}

/// "il y a 5 min", "il y a 3 h"...
String agoText(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'à l\'instant';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return '${d.inDays} j';
}
