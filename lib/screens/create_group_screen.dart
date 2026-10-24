import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';

/// Créer un groupe avec des amis.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final Set<String> _selected = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Donne un nom au groupe.');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Choisis au moins un ami.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('create_group', params: {
        'group_name': name,
        'members': _selected.toList(),
      });
      await Repo.I.loadGroups();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Création impossible. Réessaie.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = Repo.I.profiles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau groupe'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _create,
            child: const Text('Créer'),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (_saving) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(
                hintText: 'Nom du groupe',
                prefixIcon: Icon(Icons.groups),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.orangeAccent)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Ajouter des amis (${_selected.length})',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.muted)),
          ),
          if (friends.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Ajoute d\'abord des amis pour créer un groupe.',
                  style: TextStyle(color: AppColors.muted)),
            ),
          for (final p in friends)
            CheckboxListTile(
              value: _selected.contains(p['id'].toString()),
              onChanged: (v) => setState(() {
                final id = p['id'].toString();
                v == true ? _selected.add(id) : _selected.remove(id);
              }),
              secondary: Avatar(
                name: p['pseudo']?.toString() ?? '?',
                size: 42,
                userId: p['id'].toString(),
              ),
              title: Text(p['pseudo']?.toString() ?? 'Utilisateur'),
            ),
        ],
      ),
    );
  }
}
