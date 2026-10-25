import 'package:flutter/material.dart';

import 'group_invite_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';

/// Infos du groupe : membres, ajout, retrait, quitter.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _db = Supabase.instance.client;
  late final String uid = _db.auth.currentUser!.id;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  dynamic get gid => widget.group['id'];
  bool get _iAmAdmin =>
      _members.any((m) => m['user_id'] == uid && m['role'] == 'admin');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('group_members')
          .select('user_id, role, profiles(pseudo, avatar_url)')
          .eq('group_id', gid);
      _members = List<Map<String, dynamic>>.from(r);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _add() async {
    final inGroup = _members.map((m) => m['user_id'].toString()).toSet();
    final candidates =
        Repo.I.profiles.where((p) => !inGroup.contains(p['id'].toString())).toList();
    if (candidates.isEmpty) {
      _toast('Tous tes amis sont déjà dans le groupe.');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final p in candidates)
            ListTile(
              leading: Avatar(
                  name: p['pseudo']?.toString() ?? '?',
                  size: 40,
                  userId: p['id'].toString()),
              title: Text(p['pseudo']?.toString() ?? 'Utilisateur'),
              onTap: () => Navigator.pop(c, p['id'].toString()),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    try {
      await _db.rpc('add_group_member', params: {'gid': gid, 'member': picked});
      await _load();
    } catch (_) {
      _toast('Ajout impossible.');
    }
  }

  Future<void> _remove(String userId) async {
    try {
      await _db
          .from('group_members')
          .delete()
          .eq('group_id', gid)
          .eq('user_id', userId);
      if (userId == uid) {
        await Repo.I.loadGroups();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        await _load();
      }
    } catch (_) {
      _toast('Action impossible.');
    }
  }

  Future<void> _leave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Quitter le groupe ?'),
        content: const Text('Tu ne verras plus les messages de ce groupe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Quitter')),
        ],
      ),
    );
    if (yes == true) _remove(uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.group['name']?.toString() ?? 'Groupe')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Membres (${_members.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.muted)),
                ),
                if (_iAmAdmin)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.person_add, color: Colors.white),
                    ),
                    title: const Text('Ajouter un membre'),
                    onTap: _add,
                  ),
                if (_iAmAdmin)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.gold,
                      child: const Icon(Icons.qr_code_2, color: AppColors.deepGreen),
                    ),
                    title: const Text('Inviter par code ou QR'),
                    subtitle: const Text('Pour ceux qui ne sont pas encore tes amis'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GroupInviteScreen(group: widget.group)),
                    ),
                  ),
                for (final m in _members)
                  ListTile(
                    leading: Avatar(
                      name: (m['profiles'] as Map?)?['pseudo']?.toString() ?? '?',
                      size: 42,
                      userId: m['user_id'].toString(),
                      photoUrl:
                          (m['profiles'] as Map?)?['avatar_url']?.toString(),
                    ),
                    title: Text(m['user_id'] == uid
                        ? 'Toi'
                        : ((m['profiles'] as Map?)?['pseudo']?.toString() ??
                            'Utilisateur')),
                    subtitle: m['role'] == 'admin'
                        ? Text('Admin',
                            style: TextStyle(color: AppColors.primary))
                        : null,
                    trailing: (_iAmAdmin && m['user_id'] != uid)
                        ? IconButton(
                            tooltip: 'Retirer',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _remove(m['user_id'].toString()),
                          )
                        : null,
                  ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _leave,
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text('Quitter le groupe',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
    );
  }
}
