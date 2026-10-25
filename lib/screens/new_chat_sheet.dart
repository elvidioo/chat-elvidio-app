import 'package:flutter/material.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'friends_screen.dart';

/// Feuille « Nouvelle discussion » : amis réels, nouveau groupe, ajout d'ami.
Future<void> showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NewChatSheet(),
  );
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet();

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  late final Future<List<Map<String, dynamic>>> friends = Repo.I.loadProfiles();

  void _go(Widget screen) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Nouvelle discussion',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.group_add, color: AppColors.deepGreen),
            ),
            title: const Text('Nouveau groupe'),
            onTap: () => _go(const CreateGroupScreen()),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.person_add_alt_1, color: Colors.white),
            ),
            title: const Text('Ajouter un ami'),
            onTap: () => _go(const FriendsScreen()),
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: friends,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                      child: Text('Impossible de charger tes amis.'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Tu n\'as pas encore d\'ami. Ajoute quelqu\'un avec son pseudo pour discuter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final name = p['pseudo']?.toString() ?? 'Utilisateur';
                    return ListTile(
                      leading: Avatar(
                          name: name,
                          size: 44,
                          userId: p['id'].toString(),
                          showOnline: true),
                      title: Text(name),
                      onTap: () => _go(ChatScreen(
                          receiverId: p['id'].toString(), receiverName: name)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
