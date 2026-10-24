import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'contact_profile_screen.dart';

/// Amis : demandes reçues, recherche par pseudo, liste des amis.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _db = Supabase.instance.client;
  final _search = TextEditingController();
  late final String uid = _db.auth.currentUser!.id;

  List<Map<String, dynamic>> _friendships = [];
  final Map<String, Map<String, dynamic>> _people = {};
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fr = await _db
          .from('friendships')
          .select('id, requester, addressee, status')
          .timeout(const Duration(seconds: 8));
      _friendships = List<Map<String, dynamic>>.from(fr);
      final ids = <String>{
        for (final f in _friendships)
          (f['requester'] == uid ? f['addressee'] : f['requester']).toString()
      };
      if (ids.isNotEmpty) {
        final ps = await _db
            .from('profiles')
            .select('id, pseudo, avatar_url')
            .inFilter('id', ids.toList());
        for (final p in ps) {
          _people[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }
      _error = null;
      try {
        final sg = await _db.rpc('suggest_friends');
        _suggestions = List<Map<String, dynamic>>.from(sg as List);
      } catch (_) {}
    } catch (_) {
      _error = 'Pas de connexion. Réessaie.';
    }
    if (mounted) setState(() => _loading = false);
    Repo.I.loadProfiles().then((_) {}, onError: (_) {});
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final safe = query.replaceAll(RegExp(r'[%_,()]'), '');
      final r = await _db
          .from('profiles')
          .select('id, pseudo, avatar_url')
          .ilike('pseudo', '%$safe%')
          .neq('id', uid)
          .limit(20);
      _results = List<Map<String, dynamic>>.from(r);
    } catch (_) {
      _results = [];
    }
    if (mounted) setState(() => _searching = false);
  }

  Map<String, dynamic>? _relation(String other) {
    for (final f in _friendships) {
      if ((f['requester'] == other && f['addressee'] == uid) ||
          (f['requester'] == uid && f['addressee'] == other)) {
        return f;
      }
    }
    return null;
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _request(String other) async {
    try {
      await _db.from('friendships').insert({'addressee': other});
      _toast('Demande envoyée');
      await _load();
    } catch (_) {
      _toast('Envoi impossible.');
    }
  }

  Future<void> _accept(Map<String, dynamic> f) async {
    try {
      await _db.from('friendships').update({'status': 'accepted'}).eq('id', f['id']);
      await _load();
    } catch (_) {
      _toast('Action impossible.');
    }
  }

  Future<void> _remove(Map<String, dynamic> f) async {
    try {
      await _db.from('friendships').delete().eq('id', f['id']);
      await _load();
    } catch (_) {
      _toast('Action impossible.');
    }
  }

  String _name(String id) => _people[id]?['pseudo']?.toString() ?? 'Utilisateur';

  Widget _row(String id, String name,
      {required List<Widget> actions, String? subtitle}) {
    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContactProfileScreen(userId: id, name: name),
        ),
      ),
      leading: Avatar(name: name, size: 46, userId: id, photoUrl: _people[id]?['avatar_url']?.toString()),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(color: AppColors.muted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.muted)),
      );

  @override
  Widget build(BuildContext context) {
    final incoming = _friendships
        .where((f) => f['status'] == 'pending' && f['addressee'] == uid)
        .toList();
    final outgoing = _friendships
        .where((f) => f['status'] == 'pending' && f['requester'] == uid)
        .toList();
    final friends = _friendships.where((f) => f['status'] == 'accepted').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Amis')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: _runSearch,
                decoration: const InputDecoration(
                  hintText: 'Rechercher une personne par pseudo',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            if (_results.isNotEmpty) _title('Résultats'),
            for (final p in _results)
              Builder(builder: (context) {
                final id = p['id'].toString();
                final name = p['pseudo']?.toString() ?? 'Utilisateur';
                _people[id] = Map<String, dynamic>.from(p);
                final rel = _relation(id);
                Widget action;
                if (rel == null) {
                  action = FilledButton(
                    onPressed: () => _request(id),
                    child: const Text('Ajouter'),
                  );
                } else if (rel['status'] == 'accepted') {
                  action = Text('Ami', style: TextStyle(color: AppColors.muted));
                } else if (rel['requester'] == uid) {
                  action = Text('Demande envoyée',
                      style: TextStyle(color: AppColors.muted));
                } else {
                  action = FilledButton(
                    onPressed: () => _accept(rel),
                    child: const Text('Accepter'),
                  );
                }
                return _row(id, name, actions: [action]);
              }),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(_error!)),
              ),
            if (incoming.isNotEmpty) _title('Demandes reçues'),
            for (final f in incoming)
              _row(f['requester'].toString(), _name(f['requester'].toString()),
                  actions: [
                    FilledButton(
                        onPressed: () => _accept(f),
                        child: const Text('Accepter')),
                    IconButton(
                      onPressed: () => _remove(f),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
            if (outgoing.isNotEmpty) _title('Demandes envoyées'),
            for (final f in outgoing)
              _row(f['addressee'].toString(), _name(f['addressee'].toString()),
                  actions: [
                    TextButton(
                        onPressed: () => _remove(f),
                        child: const Text('Annuler')),
                  ]),
            if (_results.isEmpty && _suggestions.isNotEmpty)
              _title('Personnes que tu connais peut-être'),
            if (_results.isEmpty)
              for (final p in _suggestions)
                Builder(builder: (context) {
                  final id = p['id'].toString();
                  _people[id] = {
                    'id': id,
                    'pseudo': p['pseudo'],
                    'avatar_url': p['avatar_url'],
                  };
                  final n = (p['mutual'] as num?)?.toInt() ?? 0;
                  return _row(
                    id,
                    p['pseudo']?.toString() ?? 'Utilisateur',
                    subtitle: n > 0
                        ? '$n ami${n > 1 ? 's' : ''} en commun'
                        : null,
                    actions: [
                      FilledButton(
                        onPressed: () => _request(id),
                        child: const Text('Ajouter'),
                      ),
                    ],
                  );
                }),
            _title('Mes amis (${friends.length})'),
            if (friends.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Tu n\'as pas encore d\'ami. Cherche un pseudo ci-dessus pour envoyer une demande.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            for (final f in friends)
              Builder(builder: (context) {
                final other =
                    (f['requester'] == uid ? f['addressee'] : f['requester'])
                        .toString();
                return _row(other, _name(other), actions: [
                  IconButton(
                    tooltip: 'Retirer',
                    onPressed: () => _remove(f),
                    icon: Icon(Icons.person_remove_outlined,
                        color: AppColors.muted),
                  ),
                ]);
              }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
