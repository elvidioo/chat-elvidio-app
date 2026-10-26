import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../media_url.dart';
import '../repo.dart';
import '../report.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_post_screen.dart';

const _emojis = ['\u{1F44D}', '❤️', '\u{1F602}', '\u{1F62E}', '\u{1F622}', '\u{1F64F}'];

/// Visionneuse plein écran façon Facebook : barres de progression, toucher à
/// gauche / à droite, maintenir pour mettre en pause, glisser vers le bas pour fermer.
class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.groups,
    required this.startGroup,
    this.people = const {},
  });

  final List<StoryGroup> groups;
  final int startGroup;
  final Map<String, Map<String, dynamic>> people;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final String me = _db.auth.currentUser!.id;
  late final AnimationController _anim = AnimationController(vsync: this);
  late int _g = widget.startGroup;
  late int _i = widget.groups[_g].firstUnseenIndex;
  VideoPlayerController? _video;
  bool _paused = false;
  bool _mediaReady = false;
  final Map<int, String> _myReaction = {};

  StoryGroup get group => widget.groups[_g];
  Story get story => group.stories[_i];
  bool get mine => story.author == me;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _show();
  }

  @override
  void dispose() {
    _anim.dispose();
    _video?.dispose();
    super.dispose();
  }

  String _name(String id) => id == me
      ? 'Ma story'
      : (widget.people[id]?['pseudo']?.toString() ?? Repo.I.names[id] ?? 'Ami');

  Future<void> _show() async {
    _anim.stop();
    _anim.value = 0;
    _video?.dispose();
    _video = null;
    final s = story;
    setState(() => _mediaReady = s.mediaUrl.isEmpty);
    StoryService.markSeen(s);
    group.seenIds.add(s.id);
    _loadMyReaction(s);
    if (s.mediaUrl.isNotEmpty && isVideoUrl(s.mediaUrl)) {
      try {
        final real = await MediaUrl.resolve(s.mediaUrl);
        final c = VideoPlayerController.networkUrl(Uri.parse(real));
        await c.initialize();
        if (!mounted || s.id != story.id) {
          c.dispose();
          return;
        }
        _video = c;
        c.play();
        _anim.duration = c.value.duration > const Duration(seconds: 60)
            ? const Duration(seconds: 60)
            : c.value.duration;
        setState(() => _mediaReady = true);
        if (!_paused) _anim.forward();
      } catch (_) {
        _anim.duration = const Duration(seconds: 4);
        if (mounted) setState(() => _mediaReady = true);
        _anim.forward();
      }
    } else {
      _anim.duration = const Duration(seconds: 6);
      if (s.mediaUrl.isEmpty && mounted) _anim.forward();
    }
  }

  void _imageLoaded() {
    if (!mounted || _mediaReady) return;
    setState(() => _mediaReady = true);
    if (!_paused) _anim.forward();
  }

  Future<void> _loadMyReaction(Story s) async {
    if (s.author == me || _myReaction.containsKey(s.id)) return;
    try {
      final r = await _db
          .from('post_reactions')
          .select('emoji')
          .eq('post_id', s.id)
          .eq('user_id', me)
          .maybeSingle();
      if (r != null && mounted) setState(() => _myReaction[s.id] = r['emoji'].toString());
    } catch (_) {}
  }

  void _next() {
    if (_i < group.stories.length - 1) {
      _i++;
      _show();
    } else if (_g < widget.groups.length - 1) {
      _g++;
      _i = group.firstUnseenIndex;
      _show();
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_anim.value > 0.15 || (_i == 0 && _g == 0)) {
      _show();
    } else if (_i > 0) {
      _i--;
      _show();
    } else {
      _g--;
      _i = group.stories.length - 1;
      _show();
    }
  }

  void _pause(bool p) {
    _paused = p;
    if (p) {
      _anim.stop();
      _video?.pause();
    } else if (_mediaReady) {
      _anim.forward();
      _video?.play();
    }
  }

  Future<void> _react(String emoji) async {
    final s = story;
    final had = _myReaction[s.id];
    try {
      if (had == emoji) {
        await _db.from('post_reactions').delete().eq('post_id', s.id).eq('user_id', me);
        _myReaction.remove(s.id);
      } else {
        await _db.from('post_reactions').upsert(
          {'post_id': s.id, 'user_id': me, 'emoji': emoji},
          onConflict: 'post_id,user_id',
        );
        _myReaction[s.id] = emoji;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _delete() async {
    _pause(true);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cette story ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (yes != true) {
      _pause(false);
      return;
    }
    try {
      await _db.from('posts').delete().eq('id', story.id);
      group.stories.removeAt(_i);
      if (group.stories.isEmpty) {
        widget.groups.removeAt(_g);
        if (widget.groups.isEmpty) {
          if (mounted) Navigator.pop(context, true);
          return;
        }
        if (_g >= widget.groups.length) _g = widget.groups.length - 1;
        _i = 0;
      } else if (_i >= group.stories.length) {
        _i = group.stories.length - 1;
      }
      _paused = false;
      _show();
    } catch (_) {
      _pause(false);
    }
  }

  Future<void> _showViewers() async {
    _pause(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ViewersSheet(story: story, people: widget.people),
    );
    _pause(false);
  }

  static const _gradients = [
    [Color(0xFF087A46), Color(0xFFD4AF37)],
    [Color(0xFF3A1C71), Color(0xFFD76D77)],
    [Color(0xFF0F2027), Color(0xFF2C5364)],
    [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
  ];

  Widget _content() {
    final s = story;
    final url = s.mediaUrl;
    if (url.isEmpty) {
      final g = _gradients[s.id % _gradients.length];
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          s.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.3),
        ),
      );
    }
    Widget media;
    if (isVideoUrl(url)) {
      final v = _video;
      media = v == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
              child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
            );
    } else {
      media = _ImageStory(key: ValueKey(url), url: url, onLoaded: _imageLoaded);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        media,
        if (s.text.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(s.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 17)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = story;
    final id = s.author;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) Navigator.pop(context);
        },
        onLongPressStart: (_) => _pause(true),
        onLongPressEnd: (_) => _pause(false),
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.localPosition.dx < w * 0.3) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _content(),
            // Dégradés pour lire le texte par-dessus
            const Positioned(
              top: 0, left: 0, right: 0, height: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        for (var k = 0; k < group.stories.length; k++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: k < _i
                                    ? const LinearProgressIndicator(
                                        value: 1, minHeight: 3,
                                        backgroundColor: Colors.white30,
                                        valueColor: AlwaysStoppedAnimation(Colors.white))
                                    : k == _i
                                        ? AnimatedBuilder(
                                            animation: _anim,
                                            builder: (_, __) => LinearProgressIndicator(
                                              value: _anim.value, minHeight: 3,
                                              backgroundColor: Colors.white30,
                                              valueColor: const AlwaysStoppedAnimation(Colors.white),
                                            ),
                                          )
                                        : const LinearProgressIndicator(
                                            value: 0, minHeight: 3,
                                            backgroundColor: Colors.white30,
                                            valueColor: AlwaysStoppedAnimation(Colors.white)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Avatar(
                          name: _name(id), size: 40, userId: id,
                          photoUrl: widget.people[id]?['avatar_url']?.toString(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_name(id),
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(agoText(s.createdAt),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, color: Colors.white),
                          onOpened: () => _pause(true),
                          onCanceled: () => _pause(false),
                          onSelected: (v) {
                            if (v == 'delete') {
                              _delete();
                            } else {
                              _pause(false);
                              showReportDialog(context,
                                  kind: 'post', targetUser: id, targetId: s.id);
                            }
                          },
                          itemBuilder: (_) => [
                            if (mine)
                              const PopupMenuItem(value: 'delete', child: Text('Supprimer'))
                            else
                              const PopupMenuItem(value: 'report', child: Text('Signaler')),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: SafeArea(child: _bottom()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottom() {
    if (mine) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _ViewerCount(storyId: story.id, onTap: _showViewers),
            ),
            TextButton.icon(
              onPressed: () async {
                _pause(true);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComposePostScreen(status: true)),
                );
                _pause(false);
              },
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              label: const Text('Ajouter une story', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    final mineEmoji = _myReaction[story.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final e in _emojis)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _react(e),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mineEmoji == e ? Colors.white24 : Colors.transparent,
                ),
                child: Text(e, style: const TextStyle(fontSize: 28)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageStory extends StatefulWidget {
  const _ImageStory({super.key, required this.url, required this.onLoaded});
  final String url;
  final VoidCallback onLoaded;

  @override
  State<_ImageStory> createState() => _ImageStoryState();
}

class _ImageStoryState extends State<_ImageStory> {
  @override
  void initState() {
    super.initState();
    // La barre démarre quand l'image est prête (ou après un court délai).
    MediaUrl.resolve(widget.url).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 400), widget.onLoaded);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SignedImage(widget.url, width: double.infinity, fit: BoxFit.contain, alwaysLoad: true),
    );
  }
}

/// "👁 N spectateurs" avec le nombre de vues en direct.
class _ViewerCount extends StatefulWidget {
  const _ViewerCount({required this.storyId, required this.onTap});
  final int storyId;
  final VoidCallback onTap;

  @override
  State<_ViewerCount> createState() => _ViewerCountState();
}

class _ViewerCountState extends State<_ViewerCount> {
  int? _n;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ViewerCount old) {
    super.didUpdateWidget(old);
    if (old.storyId != widget.storyId) {
      _n = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client
          .from('story_views')
          .select('viewer')
          .eq('post_id', widget.storyId);
      if (mounted) setState(() => _n = (r as List).length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              _n == null ? 'Spectateurs' : '$_n spectateur${_n == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste de ceux qui ont vu la story, avec leur réaction.
class _ViewersSheet extends StatefulWidget {
  const _ViewersSheet({required this.story, required this.people});
  final Story story;
  final Map<String, Map<String, dynamic>> people;

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _views = [];
  final Map<String, String> _reacts = {};
  final Map<String, Map<String, dynamic>> _profiles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _db
          .from('story_views')
          .select('viewer, viewed_at')
          .eq('post_id', widget.story.id)
          .order('viewed_at', ascending: false);
      _views = List<Map<String, dynamic>>.from(v);
      final r = await _db
          .from('post_reactions')
          .select('user_id, emoji')
          .eq('post_id', widget.story.id);
      for (final e in r) {
        _reacts[e['user_id'].toString()] = e['emoji'].toString();
      }
      final ids = {
        ..._views.map((e) => e['viewer'].toString()),
        ..._reacts.keys,
      }.toList();
      if (ids.isNotEmpty) {
        final ps = await _db.from('profiles').select('id, pseudo, avatar_url').inFilter('id', ids);
        for (final p in ps) {
          _profiles[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final viewerIds = _views.map((e) => e['viewer'].toString()).toList();
    // Ceux qui ont réagi sans (encore) apparaître dans les vues
    final extra = _reacts.keys.where((k) => !viewerIds.contains(k)).toList();
    final all = [...viewerIds, ...extra];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppColors.muted, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('${viewerIds.length} spectateur${viewerIds.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_reacts.isNotEmpty)
                  Text('${_reacts.length} réaction${_reacts.length == 1 ? '' : 's'}',
                      style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : all.isEmpty
                    ? Center(
                        child: Text('Personne n\'a encore vu cette story.',
                            style: TextStyle(color: AppColors.muted)))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: all.length,
                        itemBuilder: (_, i) {
                          final id = all[i];
                          final name = _profiles[id]?['pseudo']?.toString() ??
                              widget.people[id]?['pseudo']?.toString() ??
                              'Utilisateur';
                          final at = DateTime.tryParse(_views
                                  .firstWhere((e) => e['viewer'].toString() == id,
                                      orElse: () => {})['viewed_at']
                                  ?.toString() ??
                              '');
                          return ListTile(
                            leading: Avatar(
                              name: name, size: 42, userId: id,
                              photoUrl: _profiles[id]?['avatar_url']?.toString(),
                            ),
                            title: Text(name),
                            subtitle: at == null
                                ? null
                                : Text(agoText(at.toLocal()),
                                    style: TextStyle(color: AppColors.muted)),
                            trailing: _reacts[id] == null
                                ? null
                                : Text(_reacts[id]!, style: const TextStyle(fontSize: 26)),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
