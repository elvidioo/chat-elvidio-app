import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';

/// Communautés = les groupes dont l'utilisateur est membre (seules données
/// réellement disponibles pour l'instant). Nombre de membres lu en base.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final db = Supabase.instance.client;
  final search = TextEditingController();
  Map<dynamic, int> counts = {};
  bool loadingCounts = true;
  bool countError = false;
  String query = '';

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() {
      loadingCounts = true;
      countError = false;
    });
    try {
      final rows = await db
          .from('group_members')
          .select('group_id')
          .timeout(const Duration(seconds: 8));
      final c = <dynamic, int>{};
      for (final r in rows) {
        c[r['group_id']] = (c[r['group_id']] ?? 0) + 1;
      }
      if (mounted) setState(() => counts = c);
    } catch (_) {
      if (mounted) setState(() => countError = true);
    }
    if (mounted) setState(() => loadingCounts = false);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communautés'),
        actions: [
          IconButton(
            tooltip: 'Créer un groupe',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              );
              _loadCounts();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Repo.I.groups,
        builder: (context, _) {
          final all = Repo.I.groups.value;
          final list = all
              .where((g) => (g['name']?.toString() ?? '')
                  .toLowerCase()
                  .contains(query))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: search,
                  onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une communauté',
                    prefixIcon: Icon(Icons.search, color: AppColors.muted),
                  ),
                ),
              ),
              if (countError)
                TextButton(
                    onPressed: _loadCounts,
                    child: const Text('Nombre de membres indisponible · réessayer')),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.groups_outlined,
                                  size: 64, color: AppColors.muted),
                              const SizedBox(height: 12),
                              Text(
                                all.isEmpty
                                    ? 'Tu n\'es dans aucune communauté'
                                    : 'Aucun résultat',
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                              if (all.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Crée un groupe avec tes amis : classe, quartier, équipe…',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.muted),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const CreateGroupScreen()),
                                  ),
                                  icon: const Icon(Icons.group_add),
                                  label: const Text('Créer un groupe'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(indent: 76),
                        itemBuilder: (context, i) {
                          final g = list[i];
                          final n = counts[g['id']];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: AppColors.primary,
                              child: const Icon(Icons.groups,
                                  color: Colors.white),
                            ),
                            title: Text(g['name'].toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              n != null
                                  ? '$n membre${n > 1 ? 's' : ''}'
                                  : (loadingCounts ? '…' : ''),
                              style: TextStyle(color: AppColors.muted),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => GroupChatScreen(group: g)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
