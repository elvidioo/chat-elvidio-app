import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';

/// « Groupes à rejoindre » : groupes publics, un clic pour entrer.
class PublicGroupsStrip extends StatefulWidget {
  const PublicGroupsStrip({super.key});

  @override
  State<PublicGroupsStrip> createState() => _PublicGroupsStripState();
}

class _PublicGroupsStripState extends State<PublicGroupsStrip> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _groups = [];
  final Set<dynamic> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.rpc('public_groups').timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _groups = List<Map<String, dynamic>>.from(r as List));
    } catch (_) {}
  }

  Future<void> _join(Map<String, dynamic> g) async {
    final id = g['id'];
    setState(() => _busy.add(id));
    try {
      await _db.rpc('join_public_group', params: {'gid': id});
      await Repo.I.loadGroups();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tu as rejoint « ${g['name']} ».')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de rejoindre pour le moment.')));
      }
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final list = _groups.where((g) => g['joined'] != true).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('Groupes à rejoindre',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
        ),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final g = list[i];
              final n = (g['members'] as num?)?.toInt() ?? 0;
              final busy = _busy.contains(g['id']);
              return Container(
                width: 170,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.groups_rounded, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(g['name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('$n membre${n > 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: FilledButton(
                        onPressed: busy ? null : () => _join(g),
                        style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        child: Text(busy ? '…' : 'Rejoindre'),
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
