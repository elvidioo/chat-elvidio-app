import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ai_text.dart';
import '../theme.dart';

/// Lumi : le tuteur IA de Veyra pour les élèves et étudiants.
const aiName = 'Lumi';

const _levels = ['6ème', '5ème', '4ème', '3ème', '2nde', '1ère', 'Terminale', 'Université'];
const _series = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'Autre'];
const _subjectList = [
  'Maths',
  'Physique-Chimie',
  'SVT',
  'Français',
  'Anglais',
  'Philosophie',
  'Histoire-Géo',
  'Économie',
  'Informatique',
  'Autre',
];

class _Mode {
  const _Mode(this.id, this.label, this.icon, this.hint);
  final String id;
  final String label;
  final IconData icon;
  final String hint;
}

const _modes = <_Mode>[
  _Mode('explain', 'Expliquer une notion', Icons.lightbulb_outline,
      'Quelle notion ? (ex : les limites de suites)'),
  _Mode('exercise', 'Générer un exercice', Icons.edit_note, 'Sur quel chapitre ? (ex : la dérivation)'),
  _Mode('debug', 'Aide sur une erreur', Icons.bug_report_outlined,
      'Colle ta résolution ou décris ton erreur'),
  _Mode('summary', 'Résumé du chapitre', Icons.menu_book_outlined, 'Quel chapitre ?'),
  _Mode('quiz', 'Quiz de révision', Icons.quiz_outlined, 'Quiz sur quel sujet ?'),
  _Mode('sheet', 'Fiche de révision', Icons.description_outlined, 'Fiche sur quel sujet ?'),
];

const _followUps = <(String, String)>[
  ('Plus simple', 'Explique-moi plus simplement, avec un exemple.'),
  ('Un exemple', 'Donne-moi un autre exemple résolu pas à pas.'),
  ('Correction', 'Correction'),
  ('M\'entraîner', 'Donne-moi un exercice sur ça pour m\'entraîner.'),
];

/// Discussion avec le tuteur.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _Line {
  _Line(this.mine, this.text, {this.error = false});
  final bool mine;
  final String text;
  final bool error;
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _db = Supabase.instance.client;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<_Line> _lines = []; // du plus ancien au plus récent
  bool _loading = true;
  bool _waiting = false;
  _Mode? _mode;
  Map<String, dynamic>? _student;
  String _pseudo = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = _db.auth.currentUser!.id;
    try {
      final r = await _db
          .from('ai_chats')
          .select('role, content')
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 8));
      _lines
        ..clear()
        ..addAll([for (final e in (r as List).reversed) _Line(e['role'] == 'user', e['content'].toString())]);
    } catch (_) {}
    try {
      final s = await _db.from('ai_student').select().eq('user_id', me).maybeSingle();
      _student = s == null ? null : Map<String, dynamic>.from(s);
      final p = await _db.from('profiles').select('pseudo').eq('id', me).maybeSingle();
      _pseudo = p?['pseudo']?.toString() ?? '';
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    if (_student == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editProfile(first: true);
      });
    }
  }

  String get _profileLine {
    final s = _student;
    if (s == null) return 'Dis-moi ton niveau pour que je m\'adapte à toi.';
    final parts = <String>[
      if ((s['level'] ?? '').toString().isNotEmpty) s['level'].toString(),
      if ((s['serie'] ?? '').toString().isNotEmpty) 'série ${s['serie']}',
      if ((s['field'] ?? '').toString().isNotEmpty) s['field'].toString(),
    ];
    return parts.isEmpty ? '' : 'Niveau : ${parts.join(' · ')}';
  }

  Future<void> _editProfile({bool first = false}) async {
    var level = (_student?['level'] ?? '').toString();
    var serie = (_student?['serie'] ?? '').toString();
    final field = TextEditingController(text: (_student?['field'] ?? '').toString());
    final subjects = <String>{...?(_student?['subjects'] as List?)?.map((e) => e.toString())};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(first ? 'Faisons connaissance' : 'Mon profil d\'étudiant',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('$aiName adapte ses explications à ton niveau.',
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 16),
                const Text('Ton niveau', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final l in _levels)
                    ChoiceChip(
                      label: Text(l),
                      selected: level == l,
                      onSelected: (_) => setS(() => level = l),
                    ),
                ]),
                if (level == '1ère' || level == 'Terminale') ...[
                  const SizedBox(height: 16),
                  const Text('Ta série', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in _series)
                      ChoiceChip(
                        label: Text(s),
                        selected: serie == s,
                        onSelected: (_) => setS(() => serie = s),
                      ),
                  ]),
                ],
                if (level == 'Université') ...[
                  const SizedBox(height: 16),
                  const Text('Ta filière', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: field,
                    maxLength: 80,
                    decoration: const InputDecoration(
                        hintText: 'Ex : Informatique, Droit, Médecine…', counterText: ''),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Tes matières', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in _subjectList)
                    FilterChip(
                      label: Text(s),
                      selected: subjects.contains(s),
                      onSelected: (v) => setS(() => v ? subjects.add(s) : subjects.remove(s)),
                    ),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: level.isEmpty ? null : () => Navigator.pop(ctx, true),
                    child: const Text('Enregistrer'),
                  ),
                ),
                if (first)
                  Center(
                    child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final fieldText = field.text.trim();
    field.dispose();
    if (saved != true) return;
    final row = {
      'user_id': _db.auth.currentUser!.id,
      'level': level,
      'serie': (level == '1ère' || level == 'Terminale') && serie.isNotEmpty ? serie : null,
      'field': level == 'Université' && fieldText.isNotEmpty ? fieldText : null,
      'subjects': subjects.toList(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _db.from('ai_student').upsert(row);
      if (mounted) setState(() => _student = row);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profil non enregistré (connexion ?).')));
      }
    }
  }

  Future<void> _send({String? override}) async {
    final t = (override ?? _text.text).trim();
    if (t.isEmpty || _waiting) return;
    final mode = override == null ? _mode : null;
    if (override == null) _text.clear();
    setState(() {
      _lines.add(_Line(true, t));
      _waiting = true;
      _mode = null;
    });
    _toBottom();
    try {
      final res = await _db.functions
          .invoke('ai-chat', body: {'text': t, if (mode != null) 'mode': mode.id})
          .timeout(const Duration(seconds: 40));
      final data = res.data;
      if (res.status == 200 && data is Map && data['reply'] != null) {
        _lines.add(_Line(false, data['reply'].toString()));
      } else {
        final msg = (data is Map ? data['error'] : null)?.toString() ??
            '$aiName n\'est pas disponible pour le moment.';
        _lines.add(_Line(false, msg, error: true));
      }
    } catch (e) {
      final msg = e is FunctionException && e.details is Map && (e.details as Map)['error'] != null
          ? (e.details as Map)['error'].toString()
          : 'Pas de réponse. Vérifie ta connexion et réessaie.';
      _lines.add(_Line(false, msg, error: true));
    }
    if (mounted) setState(() => _waiting = false);
    _toBottom();
  }

  void _pickMode(_Mode m) {
    setState(() => _mode = _mode?.id == m.id ? null : m);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Effacer la discussion ?'),
        content: Text('L\'historique avec $aiName sera supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('ai_chats').delete().eq('user_id', _db.auth.currentUser!.id);
      setState(_lines.clear);
    } catch (_) {}
  }

  Widget _modeChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _modes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = _modes[i];
          final on = _mode?.id == m.id;
          return ChoiceChip(
            avatar: Icon(m.icon, size: 18, color: on ? Colors.white : AppColors.primary),
            label: Text(m.label),
            labelStyle: TextStyle(color: on ? Colors.white : AppColors.text),
            selectedColor: AppColors.primary,
            selected: on,
            showCheckmark: false,
            onSelected: (_) => _pickMode(m),
          );
        },
      ),
    );
  }

  Widget _welcome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      children: [
        Center(child: const AiAvatar(size: 72)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pseudo.isEmpty ? 'Bonjour ! Je suis $aiName.' : 'Bonjour $_pseudo ! Je suis $aiName.',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                  'Ton tuteur personnel. Pose-moi une question sur ton cours, demande une explication, un exercice ou un quiz pour t\'entraîner.'),
              if (_profileLine.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_profileLine, style: TextStyle(color: AppColors.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Que veux-tu faire ?',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
        const SizedBox(height: 8),
        for (final m in _modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(m.icon, color: AppColors.primary),
                title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickMode(m),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () => _editProfile(),
          icon: const Icon(Icons.school_outlined),
          label: Text(_student == null ? 'Choisir mon niveau' : 'Modifier mon profil'),
        ),
      ],
    );
  }

  Widget _followUpRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final f in _followUps)
            ActionChip(
              label: Text(f.$1),
              onPressed: _waiting ? null : () => _send(override: f.$2),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _lines.reversed.toList();
    final showFollow = !_waiting && items.isNotEmpty && !items.first.mine && !items.first.error;
    final extra = (_waiting ? 1 : 0) + (showFollow ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const AiAvatar(size: 36),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(aiName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                Text('Ton tuteur Veyra', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'clear' ? _clear() : _editProfile(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('Mon profil d\'étudiant')),
              PopupMenuItem(value: 'clear', child: Text('Effacer la discussion')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _welcome()
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: items.length + extra,
                        itemBuilder: (_, i) {
                          if (_waiting && i == 0) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Text('$aiName réfléchit…',
                                    style: TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic)),
                              ),
                            );
                          }
                          if (showFollow && i == 0) return _followUpRow();
                          final l = items[i - extra];
                          return Align(
                            alignment: l.mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.84),
                              decoration: BoxDecoration(
                                color: l.error
                                    ? Colors.orange.withValues(alpha: 0.18)
                                    : l.mine
                                        ? AppColors.primary
                                        : AppColors.surface,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: SelectableText.rich(
                                _spans(
                                  l.mine ? l.text : cleanAiText(l.text),
                                  TextStyle(
                                    fontSize: 16,
                                    height: 1.4,
                                    color: l.mine && !l.error ? Colors.white : AppColors.text,
                                  ),
                                  bold: !l.mine,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (!_loading) _modeChips(),
          if (_mode != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(children: [
                Icon(_mode!.icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Mode : ${_mode!.label}',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
                InkWell(
                  onTap: () => setState(() => _mode = null),
                  child: Icon(Icons.close, size: 16, color: AppColors.muted),
                ),
              ]),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                          hintText: _mode?.hint ?? 'Pose ta question à $aiName…', counterText: ''),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _waiting ? null : _send,
                    icon: Icon(Icons.send_rounded, color: AppColors.primary),
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

/// Texte avec le **gras** du Markdown rendu en vrai gras.
TextSpan _spans(String text, TextStyle style, {bool bold = true}) {
  if (!bold || !text.contains('**')) return TextSpan(text: text, style: style);
  final parts = text.split('**');
  return TextSpan(style: style, children: [
    for (var i = 0; i < parts.length; i++)
      TextSpan(
        text: parts[i],
        style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null,
      ),
  ]);
}

/// Avatar du tuteur : pastille verte et or.
class AiAvatar extends StatelessWidget {
  const AiAvatar({super.key, this.size = 46});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.gradient,
        border: Border.all(color: AppColors.gold, width: 2),
      ),
      child: Icon(Icons.school_rounded, color: AppColors.gold, size: size * 0.52),
    );
  }
}
