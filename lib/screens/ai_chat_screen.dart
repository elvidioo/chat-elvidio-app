import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ai_text.dart';
import '../theme.dart';

/// Discussion directe avec « Elvidio IA ».
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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _waiting) return;
    _text.clear();
    setState(() {
      _lines.add(_Line(true, t));
      _waiting = true;
    });
    _toBottom();
    try {
      final res = await _db.functions
          .invoke('ai-chat', body: {'text': t})
          .timeout(const Duration(seconds: 40));
      final data = res.data;
      if (res.status == 200 && data is Map && data['reply'] != null) {
        _lines.add(_Line(false, data['reply'].toString()));
      } else {
        final msg = (data is Map ? data['error'] : null)?.toString() ??
            'L\'assistant n\'est pas disponible pour le moment.';
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

  void _prefill(String s) {
    _text.text = s;
    _text.selection = TextSelection.collapsed(offset: s.length);
  }

  static const _shortcuts = <(String, String)>[
    ('📘 Expliquer un cours', 'Explique-moi simplement le cours sur '),
    ('✍️ Exercice corrigé', 'Donne-moi un exercice corrigé, étape par étape, sur '),
    ('🧠 Quiz de révision', 'Fais-moi un quiz de 5 questions (niveau Terminale) sur '),
    ('📝 Résumé de chapitre', 'Fais-moi un résumé clair du chapitre '),
    ('✉️ Écrire un message', 'Aide-moi à écrire un message pour '),
  ];

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
        content: const Text('L\'historique avec l\'assistant sera supprimé.'),
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

  @override
  Widget build(BuildContext context) {
    final items = _lines.reversed.toList();
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
                const Text('Elvidio IA', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                Text('Assistant intelligent',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'clear' ? _clear() : null,
            itemBuilder: (_) => const [
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
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AiAvatar(size: 72),
                              const SizedBox(height: 14),
                              const Text('Salut ! Je suis Elvidio IA.',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(
                                'Pose-moi une question, demande-moi de t\'aider à écrire un message, de réviser un cours ou juste discuter.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.muted),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final s in _shortcuts)
                                    ActionChip(
                                      label: Text(s.$1),
                                      onPressed: () => _prefill(s.$2),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: items.length + (_waiting ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_waiting && i == 0) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Text('Elvidio IA écrit…',
                                    style: TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic)),
                              ),
                            );
                          }
                          final l = items[_waiting ? i - 1 : i];
                          return Align(
                            alignment: l.mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.82),
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
                                    height: 1.35,
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
                      decoration: const InputDecoration(hintText: 'Écris à Elvidio IA…', counterText: ''),
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

/// Avatar de l'assistant : pastille verte et or.
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
      child: Icon(Icons.auto_awesome, color: AppColors.gold, size: size * 0.52),
    );
  }
}
