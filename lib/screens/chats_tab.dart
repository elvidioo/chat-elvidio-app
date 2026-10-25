import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presence.dart';
import '../media.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import '../settings.dart';
import 'communities_screen.dart';
import 'create_group_screen.dart';
import 'search_screen.dart';
import 'stories_strip.dart';
import 'friends_screen.dart';
import 'group_chat_screen.dart';

/// Onglet "Discussions" façon Messenger : contacts en haut, puis les
/// conversations avec l'aperçu du dernier message.
class ChatsTab extends StatefulWidget {
  const ChatsTab({
    super.key,
    required this.onOpenProfile,
    required this.onOpenNearby,
    required this.onOpenStories,
  });

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNearby;
  final VoidCallback onOpenStories;

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final supabase = Supabase.instance.client;
  final search = TextEditingController();
  late final String uid = supabase.auth.currentUser!.id;
  late Future<List<Map<String, dynamic>>> profiles = Repo.I.loadProfiles();
  String query = '';
  String? myPseudo;

  Future<void> loadMe() async {
    try {
      final me = await supabase
          .from('profiles')
          .select('pseudo')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) setState(() => myPseudo = me?['pseudo']?.toString());
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    loadMe();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> openFriends() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
    if (mounted) setState(() => profiles = Repo.I.loadProfiles());
  }

  Future<void> openChat(String id, String name) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(receiverId: id, receiverName: name),
      ),
    );
    if (mounted) setState(() => profiles = Repo.I.loadProfiles());
  }

  DateTime? created(Map<String, dynamic>? m) =>
      DateTime.tryParse(m?['created_at']?.toString() ?? '')?.toLocal();

  String preview(Map<String, dynamic> m) {
    final mine = m['sender'] == uid;
    final text = m['content']?.toString() ?? '';
    final media = m['media_url']?.toString() ?? '';
    String body;
    if (text.isNotEmpty) {
      body = text;
    } else if (media.isNotEmpty) {
      body = mediaLabel(media);
    } else {
      body = '';
    }
    return mine ? 'Vous : $body' : body;
  }

  Widget header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onOpenProfile,
            child: Avatar(name: myPseudo ?? '?', size: 40, userId: uid),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'Chat ', style: TextStyle(color: AppColors.text)),
                TextSpan(
                    text: 'Elvidio',
                    style: TextStyle(color: AppColors.goldText)),
              ]),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Rechercher',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Communautés',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunitiesScreen()),
            ),
            icon: const Icon(Icons.groups_rounded),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Repo.I.pendingCount,
            builder: (context, n, _) => IconButton(
              tooltip: 'Amis',
              onPressed: openFriends,
              icon: Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                child: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rappel discret : économie de données active (réglages réellement appliqués).
  Widget dataSaverChip() {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [AppSettings.I.autoPhotos, AppSettings.I.photoQuality]),
      builder: (context, _) {
        final on = !AppSettings.I.autoPhotos.value ||
            AppSettings.I.photoQuality.value == 'low';
        if (!on) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: Icon(Icons.eco_rounded, size: 16, color: AppColors.primary),
              label: const Text('Économie de données active',
                  style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      },
    );
  }

  Widget nearbyBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: widget.onOpenNearby,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.surface2),
            ),
            child: Row(
              children: [
                Icon(Icons.sensors_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('À proximité · discuter sans internet',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget contactsRow(List<Map<String, dynamic>> list) {
    return SizedBox(
      height: 98,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final name = list[i]['pseudo']?.toString() ?? 'Utilisateur';
          return GestureDetector(
            onTap: () => openChat(list[i]['id'].toString(), name),
            child: Container(
              width: 74,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Avatar(
                    name: name,
                    size: 58,
                    userId: list[i]['id'].toString(),
                    showOnline: true,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget tile(Map<String, dynamic> profile, Map<String, dynamic>? last,
      [int unreadCount = 0]) {
    final name = profile['pseudo']?.toString() ?? 'Utilisateur';
    final unread =
        last != null && last['sender'] != uid && last['read_at'] == null;
    return InkWell(
      onTap: () => openChat(profile['id'].toString(), name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Avatar(
              name: name,
              size: 56,
              userId: profile['id'].toString(),
              showOnline: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (last == null)
                    Text(
                      'Dis bonjour \u{1F44B}',
                      style: TextStyle(color: AppColors.muted),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview(last),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread ? AppColors.text : AppColors.muted,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                        Text(
                          ' · ${formatListTime(created(last))}',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (unread)
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '${unreadCount < 1 ? 1 : unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget groupTile(Map<String, dynamic> g, Map<String, dynamic>? last) {
    final name = g['name']?.toString() ?? 'Groupe';
    String sub = 'Nouveau groupe';
    if (last != null) {
      final who = last['sender'] == uid
          ? 'Vous'
          : (Repo.I.names[last['sender'].toString()] ?? 'Quelqu\'un');
      final text = last['content']?.toString() ?? '';
      final media = last['media_url']?.toString() ?? '';
      final body = text.isNotEmpty
          ? text
          : (media.isEmpty
              ? ''
              : mediaLabel(media));
      sub = '$who : $body';
    }
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupChatScreen(group: g)),
        );
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.groups, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                      if (last != null)
                        Text(
                          ' · ${formatListTime(created(last))}',
                          style: TextStyle(color: AppColors.muted),
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

  Widget message(IconData icon, String title, String subtitle,
      {VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 64, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }

  Widget body(List<Map<String, dynamic>> all,
      List<Map<String, dynamic>> latestMessages) {
    // Dernier message de chaque conversation (liste déjà triée du plus récent).
    final lastByPeer = <String, Map<String, dynamic>>{};
    final unreadByPeer = <String, int>{};
    for (final m in latestMessages) {
      final peer = (m['sender'] == uid ? m['receiver'] : m['sender']).toString();
      lastByPeer.putIfAbsent(peer, () => m);
      if (m['receiver'] == uid && m['read_at'] == null) {
        unreadByPeer[peer] = (unreadByPeer[peer] ?? 0) + 1;
      }
    }

    final filtered = all.where((p) {
      final name = (p['pseudo']?.toString() ?? '').toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    // Dernier message de chaque groupe.
    final lastByGroup = <dynamic, Map<String, dynamic>>{};
    for (final m in Repo.I.groupMessages.value) {
      lastByGroup.putIfAbsent(m['group_id'], () => m);
    }
    final groupList = Repo.I.groups.value.where((g) {
      final name = (g['name']?.toString() ?? '').toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    // Conversations et groupes dans une seule liste, du plus récent au plus ancien.
    final entries = <_Entry>[
      for (final p in filtered)
        _Entry(created(lastByPeer[p['id'].toString()]),
            p['pseudo']?.toString() ?? '', false, p, null),
      for (final g in groupList)
        _Entry(created(lastByGroup[g['id']]), g['name']?.toString() ?? '', true,
            g, lastByGroup[g['id']]),
    ];
    entries.sort((a, b) {
      if (a.time != null && b.time != null) return b.time!.compareTo(a.time!);
      if (a.time != null) return -1;
      if (b.time != null) return 1;
      return a.name.compareTo(b.name);
    });

    final children = <Widget>[];
    children.add(StoriesStrip(onOpenStories: widget.onOpenStories));
    children.add(nearbyBanner());
    if (query.isEmpty && all.isNotEmpty) children.add(contactsRow(all));
    if (entries.isEmpty) {
      children.add(all.isEmpty
          ? message(
              Icons.people_outline,
              'Aucun ami pour le moment',
              'Touche l\'icône d\'ajout en haut à droite\npour chercher des amis par pseudo.',
            )
          : message(Icons.search_off, 'Aucun résultat', 'Essaie un autre nom.'));
    } else {
      for (final e in entries) {
        if (e.group) {
          children.add(groupTile(e.data, e.last));
        } else {
          children.add(tile(e.data, lastByPeer[e.data['id'].toString()],
              unreadByPeer[e.data['id'].toString()] ?? 0));
        }
      }
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          header(),
          dataSaverChip(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => profiles = Repo.I.loadProfiles());
                await profiles;
              },
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: profiles,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ListView(children: [
                      message(
                        Icons.cloud_off,
                        'Pas de connexion',
                        'Impossible de charger les contacts.\nTu peux utiliser le Mode proche.',
                        onRetry: () =>
                            setState(() => profiles = Repo.I.loadProfiles()),
                      ),
                    ]);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListenableBuilder(
                    listenable: Listenable.merge(
                        [Repo.I.messages, Repo.I.groups, Repo.I.groupMessages]),
                    builder: (context, _) =>
                        body(snapshot.data!, Repo.I.messages.value),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  _Entry(this.time, this.name, this.group, this.data, this.last);
  final DateTime? time;
  final String name;
  final bool group;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? last;
}
