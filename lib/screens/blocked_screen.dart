import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';

/// Utilisateurs bloqués : on peut les débloquer.
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _db.from('blocks').select('blocked');
      final ids = rows.map((r) => r['blocked'].toString()).toList();
      if (ids.isEmpty) {
        _people = [];
      } else {
        final ps = await _db
            .from('profiles')
            .select('id, pseudo, avatar_url')
            .inFilter('id', ids);
        _people = List<Map<String, dynamic>>.from(ps);
      }
      _error = null;
    } catch (_) {
      _error = 'Pas de connexion. Réessaie.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unblock(String id) async {
    try {
      await _db.from('blocks').delete().eq('blocked', id);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Action impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs bloqués')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _people.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Tu n\'as bloqué personne.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final p in _people)
                          ListTile(
                            leading: Avatar(
                              name: p['pseudo']?.toString() ?? '?',
                              size: 44,
                              photoUrl: p['avatar_url']?.toString(),
                            ),
                            title: Text(p['pseudo']?.toString() ?? 'Utilisateur'),
                            trailing: OutlinedButton(
                              onPressed: () => _unblock(p['id'].toString()),
                              child: const Text('Débloquer'),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
