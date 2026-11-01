import 'package:flutter/material.dart';

import '../../ai_text.dart';
import '../../theme.dart';
import 'nova_data.dart';
import 'nova_widgets.dart';

/// Chapitres d'une matière.
class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key, required this.level, required this.subject});
  final String level, subject;
  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  List<Map<String, dynamic>>? _topics;
  Map<String, Map<String, dynamic>> _prog = {};
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final r = await novaCall({'kind': 'topics', 'level': widget.level, 'subject': widget.subject});
      final topics = List<Map<String, dynamic>>.from(
          (r['topics'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      final p = await novaDb.from('edu_progress').select('topic_id,lesson_done,best_score');
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _prog = {for (final x in p as List) x['topic_id'].toString(): Map<String, dynamic>.from(x as Map)};
      });
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Future<void> _refreshProg() async {
    try {
      final p = await novaDb.from('edu_progress').select('topic_id,lesson_done,best_score');
      if (mounted) {
        setState(() => _prog = {
              for (final x in p as List) x['topic_id'].toString(): Map<String, dynamic>.from(x as Map)
            });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = _topics;
    final done = t == null ? 0 : t.where((x) => _prog[x['id'].toString()]?['lesson_done'] == true).length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject)),
      body: _err != null
          ? NovaError(_err!, _load)
          : t == null
              ? NovaLoading('Lumi prépare le programme de ${widget.subject} (${widget.level})…\nLa première fois, ça peut prendre quelques secondes.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    NovaCard(
                      gradient: novaGradient,
                      child: Row(children: [
                        SubjectChip(widget.subject, size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.level, style: const TextStyle(color: Colors.white70)),
                            Text('$done / ${t.length} chapitres terminés',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: t.isEmpty ? 0 : done / t.length,
                                minHeight: 7,
                                backgroundColor: Colors.white24,
                                color: Colors.white,
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    for (final x in t) _row(x),
                    const SizedBox(height: 8),
                    Center(child: NovaBadge('Programme généré par IA · à vérifier avec ton cours')),
                  ],
                ),
    );
  }

  Widget _row(Map<String, dynamic> x) {
    final p = _prog[x['id'].toString()];
    final done = p?['lesson_done'] == true;
    final best = (p?['best_score'] as int?) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NovaCard(
        onTap: () async {
          await Navigator.push(
              context,
              novaRoute(TopicScreen(
                  topic: x, subject: widget.subject, level: widget.level)));
          _refreshProg();
        },
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: done ? const Color(0xFF14B8A6) : AppColors.surface2,
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : Text('${(x['position'] as int? ?? 0) + 1}',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (best > 0)
                Text('Meilleur quiz : $best %', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
      ),
    );
  }
}

/// Un chapitre : leçon + quiz.
class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, required this.topic, required this.subject, required this.level});
  final Map<String, dynamic> topic;
  final String subject, level;
  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  String? _lesson;
  String? _err;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final r = await novaCall({'kind': 'lesson', 'topic_id': widget.topic['id']});
      if (mounted) setState(() => _lesson = cleanAiText(r['content'].toString()));
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Future<void> _markDone() async {
    try {
      await novaDb.from('edu_progress').upsert({
        'user_id': novaDb.auth.currentUser!.id,
        'topic_id': widget.topic['id'],
        'lesson_done': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,topic_id');
      if (mounted) setState(() => _done = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistrement impossible, réessaie.')));
      }
    }
  }

  static final _head = RegExp(r'^\s*([A-ZÀÂÉÈÊËÎÏÔÛÙÇ][A-ZÀÂÉÈÊËÎÏÔÛÙÇ \x27’()]{3,})\s*:\s*(.*)$');

  List<Widget> _body() {
    final base = TextStyle(fontSize: 15.5, height: 1.5, color: AppColors.text);
    final out = <Widget>[];
    for (final raw in _lesson!.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 6));
        continue;
      }
      final m = _head.firstMatch(line);
      if (m != null) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(m.group(1)!,
              style: const TextStyle(
                  color: Color(0xFF22D3EE), fontWeight: FontWeight.w900, letterSpacing: 0.6, fontSize: 13.5)),
        ));
        if ((m.group(2) ?? '').trim().isNotEmpty) {
          out.add(Text.rich(TextSpan(children: novaSpans(m.group(2)!, base))));
        }
      } else {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text.rich(TextSpan(children: novaSpans(line, base))),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.topic['title'].toString(), style: const TextStyle(fontSize: 17)),
          bottom: const TabBar(tabs: [Tab(text: 'Leçon'), Tab(text: 'Quiz')]),
        ),
        body: TabBarView(children: [
          _err != null
              ? NovaError(_err!, _load)
              : _lesson == null
                  ? const NovaLoading('Lumi prépare ta leçon…')
                  : ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
                      Align(alignment: Alignment.centerLeft, child: NovaBadge('Généré par IA · à vérifier')),
                      ..._body(),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _done ? null : _markDone,
                        icon: Icon(_done ? Icons.check_circle_rounded : Icons.done_rounded),
                        label: Text(_done ? 'Leçon terminée' : "J'ai compris cette leçon"),
                      ),
                    ]),
          ListView(padding: const EdgeInsets.all(18), children: [
            NovaCard(
              gradient: novaGradient,
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.quiz_rounded, color: Colors.white, size: 34),
                const SizedBox(height: 10),
                const Text('Teste-toi', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('8 questions à choix multiples avec correction expliquée.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1B3BD6)),
                  onPressed: () => Navigator.push(context, novaRoute(QuizScreen(topic: widget.topic))),
                  child: const Text('Commencer le quiz'),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Quiz avec correction et résultat.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, this.topic = const {}, this.preset});
  final Map<String, dynamic> topic;
  final List<Map<String, dynamic>>? preset; // quiz du carnet (non enregistré)
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Map<String, dynamic>>? _qs;
  String? _err;
  int _i = 0, _score = 0;
  int? _pick;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _err = null;
      _qs = null;
      _i = 0;
      _score = 0;
      _pick = null;
      _finished = false;
    });
    try {
      if (widget.preset != null) {
        if (mounted) setState(() => _qs = widget.preset);
        return;
      }
      final r = await novaCall({'kind': 'quiz', 'topic_id': widget.topic['id']});
      final qs = (r['questions'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _qs = qs);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Future<void> _finish() async {
    final total = _qs!.length;
    final pct = (_score * 100 / total).round();
    setState(() => _finished = true);
    if (widget.preset != null) return;
    try {
      final uid = novaDb.auth.currentUser!.id;
      await novaDb.from('edu_attempts').insert({'topic_id': widget.topic['id'], 'score': _score, 'total': total});
      final cur = await novaDb
          .from('edu_progress')
          .select('best_score')
          .eq('user_id', uid)
          .eq('topic_id', widget.topic['id'])
          .maybeSingle();
      final best = (cur?['best_score'] as int?) ?? 0;
      await novaDb.from('edu_progress').upsert({
        'user_id': uid,
        'topic_id': widget.topic['id'],
        'best_score': pct > best ? pct : best,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,topic_id');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: _err != null
          ? NovaError(_err!, _load)
          : _qs == null
              ? const NovaLoading('Lumi prépare ton quiz…')
              : _finished
                  ? _result()
                  : _question(),
    );
  }

  Widget _question() {
    final q = _qs![_i];
    final opts = List<String>.from((q['options'] as List).map((e) => cleanAiText(e.toString())));
    final answer = q['answer'] as int;
    final shown = _pick != null;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        Text('Question ${_i + 1} / ${_qs!.length}', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('$_score pts', style: const TextStyle(color: Color(0xFF22D3EE), fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: (_i + 1) / _qs!.length, minHeight: 6),
      ),
      const SizedBox(height: 22),
      Text(cleanAiText(q['q'].toString()), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
      const SizedBox(height: 18),
      for (var k = 0; k < opts.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: shown
                  ? null
                  : () => setState(() {
                        _pick = k;
                        if (k == answer) _score++;
                      }),
              child: Ink(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: !shown
                      ? AppColors.surface
                      : k == answer
                          ? const Color(0xFF14B8A6).withValues(alpha: 0.22)
                          : k == _pick
                              ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                              : AppColors.surface,
                  border: Border.all(
                      color: !shown
                          ? AppColors.surface2
                          : k == answer
                              ? const Color(0xFF14B8A6)
                              : k == _pick
                                  ? const Color(0xFFEF4444)
                                  : AppColors.surface2),
                ),
                child: Row(children: [
                  CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.surface2,
                      child: Text(String.fromCharCode(65 + k), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(opts[k], style: const TextStyle(fontSize: 15.5))),
                ]),
              ),
            ),
          ),
        ),
      if (shown) ...[
        const SizedBox(height: 6),
        NovaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_pick == answer ? 'Bravo, bonne réponse !' : 'Pas tout à fait.',
                style: TextStyle(fontWeight: FontWeight.w800, color: _pick == answer ? const Color(0xFF14B8A6) : const Color(0xFFF87171))),
            const SizedBox(height: 6),
            Text(cleanAiText((q['explain'] ?? '').toString()), style: TextStyle(color: AppColors.muted, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => _i + 1 >= _qs!.length ? _finish() : setState(() { _i++; _pick = null; }),
          child: Text(_i + 1 >= _qs!.length ? 'Voir mon résultat' : 'Question suivante'),
        ),
      ],
    ]);
  }

  Widget _result() {
    final total = _qs!.length;
    final v = _score / total;
    final msg = v >= 0.8 ? 'Excellent travail !' : v >= 0.5 ? 'Bien joué, continue !' : 'Relis la leçon et réessaie, tu vas y arriver.';
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 10),
      Center(
        child: NovaRing(
          value: v,
          size: 170,
          color: const Color(0xFF22D3EE),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$_score/$total', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            Text('${(v * 100).round()} %', style: TextStyle(color: AppColors.muted)),
          ]),
        ),
      ),
      const SizedBox(height: 22),
      Center(child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
      const SizedBox(height: 26),
      FilledButton(onPressed: _load, child: const Text('Refaire le quiz')),
      const SizedBox(height: 10),
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), shape: const StadiumBorder()),
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour au chapitre'),
      ),
    ]);
  }
}
