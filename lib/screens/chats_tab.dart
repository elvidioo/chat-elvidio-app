import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';

/// Onglet "Discussions" façon Messenger : contacts en haut, puis les
/// conversations avec l'aperçu du dernier message.
class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key, required this.onOpenProfile});

  final VoidCallback onOpenProfile;

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

  void openChat(String id, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(receiverId: id, receiverName: name),
      ),
    );
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
      body = isVideoUrl(media) ? '\u{1F3A5} Vidéo' : '\u{1F4F7} Photo';
    } else {
      body = '';
    }
    return mine ? 'Vous : $body' : body;
  }

  Widget header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onOpenProfile,
            child: Avatar(name: myPseudo ?? '?', size: 40),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Discussions',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: search,
        onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Rechercher',
          prefixIcon: Icon(Icons.search, color: AppColors.muted),
          isDense: true,
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
                  Avatar(name: name, size: 58),
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

  Widget tile(Map<String, dynamic> profile, Map<String, dynamic>? last) {
    final name = profile['pseudo']?.toString() ?? 'Utilisateur';
    final unread =
        last != null && last['sender'] != uid && last['read_at'] == null;
    return InkWell(
      onTap: () => openChat(profile['id'].toString(), name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Avatar(name: name, size: 56),
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
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
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
    for (final m in latestMessages) {
      final peer = (m['sender'] == uid ? m['receiver'] : m['sender']).toString();
      lastByPeer.putIfAbsent(peer, () => m);
    }

    final filtered = all.where((p) {
      final name = (p['pseudo']?.toString() ?? '').toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final la = created(lastByPeer[a['id'].toString()]);
      final lb = created(lastByPeer[b['id'].toString()]);
      if (la != null && lb != null) return lb.compareTo(la);
      if (la != null) return -1;
      if (lb != null) return 1;
      return (a['pseudo']?.toString() ?? '')
          .compareTo(b['pseudo']?.toString() ?? '');
    });

    final children = <Widget>[];
    if (query.isEmpty && all.isNotEmpty) children.add(contactsRow(all));
    if (filtered.isEmpty) {
      children.add(all.isEmpty
          ? message(
              Icons.people_outline,
              'Personne d\'autre pour le moment',
              'Invite tes amis à installer l\'app,\nils apparaîtront ici.',
            )
          : message(Icons.search_off, 'Aucun résultat', 'Essaie un autre nom.'));
    } else {
      for (final p in filtered) {
        children.add(tile(p, lastByPeer[p['id'].toString()]));
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
          searchBar(),
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
                  return ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: Repo.I.messages,
                    builder: (context, msgs, _) => body(snapshot.data!, msgs),
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
