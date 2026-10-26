import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../media_url.dart';
import '../repo.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_post_screen.dart';
import 'story_viewer.dart';

/// Ouvre la visionneuse sur le groupe [index] puis recharge les stories.
Future<void> openStories(BuildContext context, List<StoryGroup> groups, int index,
    Map<String, Map<String, dynamic>> people) async {
  if (index < 0 || index >= groups.length) return;
  await Navigator.push(
    context,
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          StoryViewer(groups: groups, startGroup: index, people: people),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

/// Rangée de cartes de stories façon Facebook : « Créer une story » puis
/// une carte par personne (aperçu, pastille = stories non vues).
class StoryCards extends StatefulWidget {
  const StoryCards({super.key});

  @override
  State<StoryCards> createState() => StoryCardsState();
}

class StoryCardsState extends State<StoryCards> {
  final _db = Supabase.instance.client;
  List<StoryGroup> groups = [];
  final Map<String, Map<String, dynamic>> people = {};

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final g = await StoryService.load();
      final ids = g.map((e) => e.author).toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await _db
            .from('profiles')
            .select('id, pseudo, avatar_url')
            .inFilter('id', ids)
            .timeout(const Duration(seconds: 8));
        for (final p in ps) {
          people[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }
      if (mounted) setState(() => groups = g);
    } catch (_) {}
  }

  String _name(String id, String me) => id == me
      ? 'Votre story'
      : (people[id]?['pseudo']?.toString() ?? Repo.I.names[id] ?? 'Ami');

  @override
  Widget build(BuildContext context) {
    final me = _db.auth.currentUser!.id;
    return SizedBox(
      height: 196,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _createCard(me),
          for (var i = 0; i < groups.length; i++) _card(i, me),
        ],
      ),
    );
  }

  Widget _createCard(String me) {
    return Semantics(
      button: true,
      label: 'Créer une story',
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ComposePostScreen(status: true)),
          );
          reload();
        },
        child: Container(
          width: 112,
          margin: const EdgeInsets.fromLTRB(2, 6, 6, 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surface2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: AppColors.surface2,
                      child: Avatar(
                        name: 'Moi', size: 80, userId: me,
                        photoUrl: people[me]?['avatar_url']?.toString(),
                      ),
                    ),
                    Positioned(
                      bottom: -16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              color: AppColors.surface, shape: BoxShape.circle),
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: AppColors.primary,
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 22, 6, 10),
                child: Text('Créer une story',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(int i, String me) {
    final g = groups[i];
    final cover = g.stories.lastWhere((s) => s.mediaUrl.isNotEmpty && !isVideoUrl(s.mediaUrl),
        orElse: () => g.stories.last);
    final unseen = g.unseen;
    final name = _name(g.author, me);
    return Semantics(
      button: true,
      label: 'Story de $name',
      child: GestureDetector(
        onTap: () async {
          await openStories(context, groups, i, people);
          reload();
        },
        child: Container(
          width: 112,
          margin: const EdgeInsets.fromLTRB(2, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: unseen > 0 ? AppColors.gold : AppColors.surface2,
              width: unseen > 0 ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _coverOf(cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: unseen > 0 ? AppColors.gold : Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${unseen > 0 ? unseen : g.stories.length}',
                    style: TextStyle(
                      color: unseen > 0 ? const Color(0xFF07130F) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverOf(Story s) {
    if (s.mediaUrl.isNotEmpty && !isVideoUrl(s.mediaUrl)) {
      return SignedImage(s.mediaUrl, fit: BoxFit.cover, width: 112, height: 190, alwaysLoad: true);
    }
    if (s.mediaUrl.isNotEmpty) {
      return Container(
        color: const Color(0xFF16201C),
        child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF087A46), Color(0xFFD4AF37)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Text(
        s.text,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
