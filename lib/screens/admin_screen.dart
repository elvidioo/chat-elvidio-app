import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

/// Réservé à l'administrateur : moyens de paiement, prix et demandes Premium.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _db = Supabase.instance.client;
  final _info = TextEditingController();
  final _price = TextEditingController();
  List<Map<String, dynamic>> _pending = [];
  final Map<String, String> _names = {};
  int _users = 0, _premium = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _info.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await _db.from('app_config').select('key, value');
      for (final r in c) {
        if (r['key'] == 'payment_info') _info.text = r['value'].toString();
        if (r['key'] == 'premium_price') _price.text = r['value'].toString();
      }
      final p = await _db
          .from('premium_requests')
          .select('id, user_id, reference, created_at')
          .eq('status', 'pending')
          .order('created_at');
      _pending = List<Map<String, dynamic>>.from(p);
      final ids = _pending.map((e) => e['user_id'].toString()).toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await _db.from('profiles').select('id, pseudo').inFilter('id', ids);
        for (final e in ps) {
          _names[e['id'].toString()] = e['pseudo']?.toString() ?? '?';
        }
      }
      _users = (await _db.from('profiles').select('id')).length;
      _premium = (await _db.from('premium').select('user_id').gt('until', DateTime.now().toUtc().toIso8601String())).length;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveConfig() async {
    try {
      await _db.from('app_config').upsert([
        {'key': 'payment_info', 'value': _info.text.trim()},
        {'key': 'premium_price', 'value': _price.text.trim()},
      ]);
      _toast('Enregistré.');
    } catch (_) {
      _toast('Enregistrement impossible.');
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool ok) async {
    try {
      if (ok) {
        await _db.rpc('approve_premium', params: {'rid': r['id'], 'days': 30});
      } else {
        await _db.rpc('reject_premium', params: {'rid': r['id']});
      }
      _pending.removeWhere((e) => e['id'] == r['id']);
      if (mounted) setState(() {});
    } catch (_) {
      _toast('Action impossible.');
    }
  }

  void _toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('$_users comptes · $_premium Premium actifs',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                const Text('Prix affiché', style: TextStyle(fontWeight: FontWeight.w700)),
                TextField(controller: _price),
                const SizedBox(height: 12),
                const Text('Comment payer (numéro Mobile Money, nom, étapes)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextField(controller: _info, minLines: 3, maxLines: 8),
                const SizedBox(height: 8),
                FilledButton(onPressed: _saveConfig, child: const Text('Enregistrer')),
                const SizedBox(height: 24),
                Text('Demandes en attente (${_pending.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if (_pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Aucune demande.', style: TextStyle(color: AppColors.muted)),
                  ),
                for (final r in _pending)
                  Card(
                    color: AppColors.surface,
                    child: ListTile(
                      title: Text(_names[r['user_id'].toString()] ?? 'Utilisateur'),
                      subtitle: Text('Référence : ${r['reference']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Refuser',
                            icon: const Icon(Icons.close, color: Colors.redAccent),
                            onPressed: () => _decide(r, false),
                          ),
                          IconButton(
                            tooltip: 'Valider 30 jours',
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => _decide(r, true),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
