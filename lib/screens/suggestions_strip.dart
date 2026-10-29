import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';
import 'contact_profile_screen.dart';

/// « Personnes que tu peux connaître » : bande horizontale dans la liste des discussions.
class SuggestionsStrip extends StatefulWidget {
  const SuggestionsStrip({super.key});

  @override
  State<SuggestionsStrip> createState() => _SuggestionsStripState();
}

class _SuggestionsStripState extends State<SuggestionsStrip> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _people = [];
  final Set<String> _sent = {};
  final Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.rpc('suggest_people').timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _people = List<Map<String, dynamic>>.from(r as List));
    } catch (_) {}
  }

  Future<void> _add(String id) async {
    setState(() => _sent.add(id));
    try {
      await _db.from('friendships').insert({'addressee': id});
    } catch (_) {
      if (mounted) {
        setState(() => _sent.remove(id));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Envoi impossible.')));
      }
    }
  }

  String _reason(Map<String, dynamic> p) {
    final m = (p['mutual'] as num?)?.toInt() ?? 0;
    final g = (p['shared_groups'] as num?)?.toInt() ?? 0;
    if (m > 0) return '$m ami${m > 1 ? 's' : ''} en commun';
    if (g > 0) return '$g groupe${g > 1 ? 's' : ''} en commun';
    return 'Sur Chat Elvidio';
  }

  @override
  Widget build(BuildContext context) {
    final list = _people.where((p) => !_hidden.contains(p['id'].toString())).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('Personnes que tu peux connaître',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = list[i];
              final id = p['id'].toString();
              final name = p['pseudo']?.toString() ?? 'Utilisateur';
              final sent = _sent.contains(id);
              return Container(
                width: 132,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: InkWell(
                        onTap: () => setState(() => _hidden.add(id)),
                        child: Icon(Icons.close, size: 16, color: AppColors.muted),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ContactProfileScreen(userId: id, name: name)),
                      ),
                      child: Column(children: [
                        Avatar(
                            name: name,
                            size: 52,
                            userId: id,
                            photoUrl: p['avatar_url']?.toString()),
                        const SizedBox(height: 6),
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(_reason(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      ]),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: FilledButton(
                        onPressed: sent ? null : () => _add(id),
                        style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        child: Text(sent ? 'Envoyée' : 'Ajouter'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
