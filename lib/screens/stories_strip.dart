import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_post_screen.dart';

/// Rangée de stories : statuts non expirés visibles (amis + moi, selon RLS).
/// « Vu / non vu » n'est pas suivi par le backend : pas de distinction affichée.
class StoriesStrip extends StatefulWidget {
  const StoriesStrip({super.key, required this.onOpenStories});

  final VoidCallback onOpenStories;

  @override
  State<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<StoriesStrip> {
  final db = Supabase.instance.client;
  List<String> authors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await db
          .from('posts')
          .select('author, created_at')
          .eq('kind', 'status')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(60)
          .timeout(const Duration(seconds: 8));
      final seen = <String>[];
      for (final r in rows) {
        final a = r['author'].toString();
        if (!seen.contains(a)) seen.add(a);
      }
      if (mounted) setState(() => authors = seen);
    } catch (_) {
      // Hors ligne : on garde la rangée telle quelle (bouton « Ma story » seul).
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = db.auth.currentUser!.id;
    final others = authors.where((a) => a != me).toList();
    final mine = authors.contains(me);
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _item(
            label: mine ? 'Ma story' : 'Ajouter',
            ring: mine,
            child: mine
                ? Avatar(name: 'Moi', size: 52, userId: me)
                : CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.surface2,
                    child: Icon(Icons.add, color: AppColors.primary),
                  ),
            onTap: () async {
              if (mine) {
                widget.onOpenStories();
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ComposePostScreen(status: true)),
                );
                _load();
              }
            },
          ),
          for (final a in others)
            _item(
              label: Repo.I.names[a] ?? 'Ami',
              ring: true,
              child: Avatar(name: Repo.I.names[a] ?? '?', size: 52, userId: a),
              onTap: widget.onOpenStories,
            ),
        ],
      ),
    );
  }

  Widget _item({
    required String label,
    required bool ring,
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
                  border: Border.all(
                      color: ring ? AppColors.gold : AppColors.surface2,
                      width: 2.5),
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
