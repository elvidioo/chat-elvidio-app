import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_post_screen.dart';
import 'story_cards.dart';

/// Rangée compacte de stories (écran Discussions). Anneau doré = story non vue.
/// Toucher ouvre directement la story ; le fil complet est dans l'onglet Stories.
class StoriesStrip extends StatefulWidget {
  const StoriesStrip({super.key, required this.onOpenStories});

  final VoidCallback onOpenStories;

  @override
  State<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<StoriesStrip> {
  final db = Supabase.instance.client;
  List<StoryGroup> groups = [];
  final Map<String, Map<String, dynamic>> people = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await StoryService.load();
      final ids = g.map((e) => e.author).toList();
      if (ids.isNotEmpty) {
        final ps = await db.from('profiles').select('id, pseudo, avatar_url').inFilter('id', ids);
        for (final p in ps) {
          people[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }
      if (mounted) setState(() => groups = g);
    } catch (_) {
      // Hors ligne : on garde la rangée telle quelle.
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = db.auth.currentUser!.id;
    final mineIdx = groups.indexWhere((g) => g.author == me);
    final others = [
      for (var i = 0; i < groups.length; i++)
        if (groups[i].author != me) i
    ];
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _item(
            label: mineIdx >= 0 ? 'Ma story' : 'Ajouter',
            ring: mineIdx >= 0 ? AppColors.surface2 : null,
            child: mineIdx >= 0
                ? Avatar(name: 'Moi', size: 52, userId: me)
                : CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.surface2,
                    child: Icon(Icons.add, color: AppColors.primary),
                  ),
            onTap: () async {
              if (mineIdx >= 0) {
                await openStories(context, groups, mineIdx, people);
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ComposePostScreen(status: true)),
                );
              }
              _load();
            },
          ),
          for (final i in others)
            _item(
              label: people[groups[i].author]?['pseudo']?.toString() ??
                  Repo.I.names[groups[i].author] ??
                  'Ami',
              ring: groups[i].allSeen ? AppColors.surface2 : AppColors.gold,
              child: Avatar(
                name: Repo.I.names[groups[i].author] ?? '?',
                size: 52,
                userId: groups[i].author,
                photoUrl: people[groups[i].author]?['avatar_url']?.toString(),
              ),
              onTap: () async {
                await openStories(context, groups, i, people);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _item({
    required String label,
    required Color? ring,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: 'Story de $label',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring ?? AppColors.surface2, width: 2.5),
                ),
                child: child,
              ),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
