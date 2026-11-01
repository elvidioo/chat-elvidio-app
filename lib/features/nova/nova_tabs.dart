import 'package:flutter/material.dart';

import '../../repo.dart';
import '../../screens/group_chat_screen.dart';
import '../../screens/public_groups_strip.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'nova_data.dart';
import 'nova_notebook.dart';
import 'nova_widgets.dart';

/// Choix du niveau et des matières (première ouverture ou modification).
class NovaOnboarding extends StatefulWidget {
  const NovaOnboarding({super.key, required this.initial, required this.onDone, this.canSkip = false});
  final Map<String, dynamic>? initial;
  final void Function(Map<String, dynamic>) onDone;
  final bool canSkip;
  @override
  State<NovaOnboarding> createState() => _NovaOnboardingState();
}

class _NovaOnboardingState extends State<NovaOnboarding> {
  late String? _level = widget.initial?['level']?.toString();
  late final Set<String> _subjects = {
    ...((widget.initial?['subjects'] as List?) ?? const []).map((e) => e.toString())
  };
  bool _saving = false;

  Future<void> _save() async {
    if (_level == null || _subjects.isEmpty) return;
    setState(() => _saving = true);
    final row = {
      'user_id': novaDb.auth.currentUser!.id,
      'level': _level,
      'subjects': _subjects.toList(),
    };
    try {
      await novaDb.from('ai_student').upsert(row);
    } catch (_) {}
    if (mounted) widget.onDone(row);
  }

  @override
  Widget build(BuildContext context) {
    final subs = _level == null ? <String>[] : novaSubjectsFor(_level!);
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(22), children: [
          const SizedBox(height: 10),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(gradient: novaGradient, borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.school_rounded, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 18),
          const Text('Bienvenue sur Lumi', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('Cours, fiches, quiz et un tuteur qui t\'explique, adaptés à ton niveau.',
              style: TextStyle(color: AppColors.muted, height: 1.4)),
          const SizedBox(height: 26),
          const Text('Ton niveau', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in novaLevels)
              ChoiceChip(
                label: Text(l),
                selected: _level == l,
                onSelected: (_) => setState(() {
                  _level = l;
                  _subjects.removeWhere((s) => !novaSubjectsFor(l).contains(s));
                }),
              ),
          ]),
          if (_level != null) ...[
            const SizedBox(height: 24),
            const Text('Tes matières', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in subs)
                FilterChip(
                  label: Text(s),
                  avatar: Icon(novaIcon(s), size: 18),
                  selected: _subjects.contains(s),
                  onSelected: (v) => setState(() => v ? _subjects.add(s) : _subjects.remove(s)),
                ),
            ]),
          ],
          const SizedBox(height: 30),
          FilledButton(
            onPressed: (_level == null || _subjects.isEmpty || _saving) ? null : _save,
            child: Text(_saving ? 'Enregistrement…' : 'Commencer'),
          ),
          if (widget.canSkip)
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ]),
      ),
    );
  }
}

/// Accueil : objectif du jour, matières, reprise, statistiques.
class NovaHome extends StatefulWidget {
  const NovaHome({super.key, required this.student, required this.onOpenSubject, required this.onGoCourses});
  final Map<String, dynamic> student;
  final void Function(String subject) onOpenSubject;
  final VoidCallback onGoCourses;
  @override
  State<NovaHome> createState() => _NovaHomeState();
}

class _NovaHomeState extends State<NovaHome> {
  String _name = '';
  int _today = 0, _done = 0, _avg = 0;
  Map<String, dynamic>? _last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = novaDb.auth.currentUser!.id;
      final me = await novaDb.from('profiles').select('pseudo').eq('id', uid).maybeSingle();
      final prog = await novaDb
          .from('edu_progress')
          .select('lesson_done,best_score,updated_at,edu_topics(title,subject,level)')
          .order('updated_at', ascending: false)
          .limit(200);
      final att = await novaDb.from('edu_attempts').select('score,total').order('created_at', ascending: false).limit(20);
      final list = List<Map<String, dynamic>>.from((prog as List).map((e) => Map<String, dynamic>.from(e as Map)));
      final start = DateTime.now();
      final midnight = DateTime(start.year, start.month, start.day);
      var today = 0;
      for (final p in list) {
        final t = DateTime.tryParse(p['updated_at'].toString())?.toLocal();
        if (t != null && t.isAfter(midnight)) today++;
      }
      var avg = 0;
      final a = att as List;
      if (a.isNotEmpty) {
        var s = 0.0;
        for (final x in a) {
          s += (x['score'] as int) / (x['total'] as int);
        }
        avg = (s * 100 / a.length).round();
      }
      if (!mounted) return;
      setState(() {
        _name = me?['pseudo']?.toString() ?? '';
        _today = today;
        _done = list.where((p) => p['lesson_done'] == true).length;
        _avg = avg;
        _last = list.isEmpty ? null : list.first;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final subjects = List<String>.from((widget.student['subjects'] as List?) ?? const []);
    final goal = (_today / 2).clamp(0.0, 1.0);
    final topic = _last?['edu_topics'];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 24), children: [
        Text(_name.isEmpty ? 'Bonjour 👋' : 'Bonjour, $_name 👋',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        Text('Prêt à apprendre aujourd\'hui ?', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 18),
        NovaCard(
          gradient: novaGradient,
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Objectif du jour', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(_today >= 2 ? 'Objectif atteint, bravo !' : 'Fais 2 activités (leçon ou quiz)',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${_today.clamp(0, 2)} / 2 aujourd\'hui', style: const TextStyle(color: Colors.white70)),
              ]),
            ),
            NovaRing(
              value: goal,
              size: 84,
              child: Text('${(goal * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _stat(Icons.check_circle_rounded, '$_done', 'Leçons terminées', const Color(0xFF14B8A6))),
          const SizedBox(width: 12),
          Expanded(child: _stat(Icons.insights_rounded, _avg == 0 ? '—' : '$_avg %', 'Moyenne aux quiz', const Color(0xFF22D3EE))),
        ]),
        if (topic is Map) ...[
          const SizedBox(height: 22),
          const Text('Reprendre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          NovaCard(
            onTap: () => widget.onOpenSubject(topic['subject'].toString()),
            child: Row(children: [
              SubjectChip(topic['subject'].toString()),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(topic['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(topic['subject'].toString(), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ]),
              ),
              Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 30),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        const NotebookCard(),
        const SizedBox(height: 22),
        Row(children: [
          const Text('Mes matières', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton(onPressed: widget.onGoCourses, child: const Text('Tout voir')),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final s in subjects)
              NovaCard(
                onTap: () => widget.onOpenSubject(s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  SubjectChip(s, size: 40),
                  Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _stat(IconData i, String v, String l, Color c) => NovaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, color: c),
          const SizedBox(height: 8),
          Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(l, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
      );
}

/// Mes cours : toutes les matières.
class NovaCourses extends StatelessWidget {
  const NovaCourses({super.key, required this.student, required this.onOpenSubject, required this.onEdit});
  final Map<String, dynamic> student;
  final void Function(String subject) onOpenSubject;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final subjects = List<String>.from((student['subjects'] as List?) ?? const []);
    return ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 24), children: [
      Row(children: [
        const Expanded(child: Text('Mes cours', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
        IconButton(onPressed: onEdit, icon: const Icon(Icons.tune_rounded), tooltip: 'Modifier mes matières'),
      ]),
      Text('Niveau : ${student['level']}', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      const NotebookCard(),
      const SizedBox(height: 12),
      for (final s in subjects)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NovaCard(
            onTap: () => onOpenSubject(s),
            child: Row(children: [
              SubjectChip(s, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('Chapitres, leçons et quiz', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),
        ),
    ]);
  }
}

/// Communauté : groupes publics et mes groupes d'étude.
class NovaCommunity extends StatelessWidget {
  const NovaCommunity({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(0, 14, 0, 24), children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Text('Communauté', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
        child: Text('Révise avec d\'autres élèves dans des groupes d\'étude.', style: TextStyle(color: AppColors.muted)),
      ),
      const PublicGroupsStrip(),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Text('Mes groupes', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
      ),
      ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: Repo.I.groups,
        builder: (_, groups, __) {
          if (groups.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Text('Tu n\'as pas encore de groupe. Rejoins-en un ci-dessus.', style: TextStyle(color: AppColors.muted)),
            );
          }
          return Column(children: [
            for (final g in groups)
              ListTile(
                leading: Avatar(name: g['name']?.toString() ?? '?', size: 44),
                title: Text(g['name']?.toString() ?? 'Groupe', style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, novaRoute(GroupChatScreen(group: g))),
              ),
          ]);
        },
      ),
    ]);
  }
}

/// Profil : niveau, matières, statistiques, retour à Veyra.
class NovaProfile extends StatelessWidget {
  const NovaProfile({super.key, required this.student, required this.onEdit});
  final Map<String, dynamic> student;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final subjects = List<String>.from((student['subjects'] as List?) ?? const []);
    return ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 24), children: [
      const Text('Profil', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      NovaCard(
        gradient: novaGradient,
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          const Icon(Icons.school_rounded, color: Colors.white, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mon niveau', style: TextStyle(color: Colors.white70)),
              Text('${student['level']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const Text('Mes matières', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in subjects) Chip(avatar: Icon(novaIcon(s), size: 18), label: Text(s)),
      ]),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_rounded), label: const Text('Modifier mon profil')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), shape: const StadiumBorder()),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Retour à Veyra'),
      ),
      const SizedBox(height: 18),
      NovaBadge('Les contenus sont générés par IA : vérifie avec ton cours'),
    ]);
  }
}

/// Entrée du carnet (sources personnelles).
class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key});
  @override
  Widget build(BuildContext context) => NovaCard(
        onTap: () => Navigator.push(context, novaRoute(const NotebookScreen())),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: const Color(0xFF22D3EE).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF22D3EE)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mon carnet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('Ajoute tes cours, Lumi t\'aide dessus', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
      );
}
