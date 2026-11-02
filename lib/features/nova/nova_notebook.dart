import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai_text.dart';
import '../../theme.dart';
import 'nova_data.dart';
import 'nova_learn.dart';
import 'nova_widgets.dart';

Future<Map<String, dynamic>> _nb(Map<String, dynamic> b) => novaCall(b, fn: 'nova-notebook');

/// Carnet : l'élève ajoute ses sources (texte, photos de cours) et Lumi
/// répond et crée résumés, quiz et fiches UNIQUEMENT à partir d'elles.
class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _Qa {
  _Qa(this.q);
  final String q;
  String? a;
  bool err = false;
}

class _NotebookScreenState extends State<NotebookScreen> {
  List<Map<String, dynamic>>? _src;
  final _qa = <_Qa>[];
  final _ask = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ask.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await novaDb.from('edu_sources').select('id,title,content,created_at').order('created_at', ascending: false);
      if (mounted) setState(() => _src = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map))));
    } catch (_) {
      if (mounted) setState(() => _src = _src ?? []);
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _addText({String title = '', String content = ''}) async {
    final t = TextEditingController(text: title);
    final c = TextEditingController(text: content);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nouveau cours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: t, maxLength: 80, decoration: const InputDecoration(hintText: 'Titre (ex. Cours de physique, chap. 3)')),
          const SizedBox(height: 8),
          TextField(controller: c, minLines: 6, maxLines: 10, maxLength: 20000, decoration: const InputDecoration(hintText: 'Colle ici ton cours, tes notes…')),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter'))),
        ]),
      ),
    );
    final text = c.text.trim();
    if (ok != true || text.length < 20) {
      if (ok == true) _snack('Le texte est trop court.');
      return;
    }
    try {
      await novaDb.from('edu_sources').insert({'title': t.text.trim().isEmpty ? 'Cours sans titre' : t.text.trim(), 'content': text});
      _load();
    } catch (_) {
      _snack('Ajout impossible, réessaie.');
    }
  }

  Future<void> _addPhoto() async {
    final from = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choisir dans la galerie'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (from == null) return;
    try {
      final f = await ImagePicker().pickImage(source: from, maxWidth: 1600, imageQuality: 70);
      if (f == null) return;
      setState(() => _busy = true);
      final bytes = await f.readAsBytes();
      final r = await _nb({'action': 'ocr', 'image': base64Encode(bytes), 'mime': 'image/jpeg'});
      if (!mounted) return;
      setState(() => _busy = false);
      final txt = (r['text'] ?? '').toString().trim();
      if (txt.isEmpty || txt.startsWith('AUCUN TEXTE')) {
        _snack('Je n\'ai pas trouvé de texte sur cette photo.');
        return;
      }
      await _addText(title: 'Photo de cours', content: cleanAiText(txt));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(e is String ? e : 'Photo impossible à lire.');
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce cours ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await novaDb.from('edu_sources').delete().eq('id', s['id']);
      _load();
    } catch (_) {
      _snack('Suppression impossible.');
    }
  }

  Future<void> _send() async {
    final q = _ask.text.trim();
    if (q.isEmpty || _busy) return;
    if ((_src ?? []).isEmpty) {
      _snack('Ajoute d\'abord un cours.');
      return;
    }
    final item = _Qa(q);
    setState(() {
      _qa.add(item);
      _busy = true;
      _ask.clear();
    });
    try {
      final r = await _nb({'action': 'ask', 'question': q});
      item.a = cleanAiText(r['answer'].toString());
    } catch (e) {
      item.a = e.toString();
      item.err = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _make(String type, String label) async {
    if ((_src ?? []).isEmpty) {
      _snack('Ajoute d\'abord un cours.');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _nb({'action': 'make', 'type': type});
      if (!mounted) return;
      setState(() => _busy = false);
      if (type == 'quiz') {
        final qs = (r['questions'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        Navigator.push(context, novaRoute(QuizScreen(preset: qs)));
      } else if (type == 'cards') {
        final cs = (r['cards'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        Navigator.push(context, novaRoute(_CardsScreen(cards: cs)));
      } else {
        Navigator.push(context, novaRoute(_TextScreen(title: label, text: cleanAiText(r['text'].toString()))));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = _src;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.embedded ? 'Mes cours' : 'Mon carnet'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: Column(children: [
        Expanded(
          child: src == null
              ? const NovaLoading('Chargement…')
              : ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                  Text('Ajoute les cours que tu as reçus (texte ou photo de ton cahier). Lumi répond et crée résumés, quiz et fiches uniquement à partir de tes cours.',
                      style: TextStyle(color: AppColors.muted, height: 1.4)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _addText(), icon: const Icon(Icons.notes_rounded), label: const Text('Texte'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton.icon(onPressed: _busy ? null : _addPhoto, icon: const Icon(Icons.photo_camera_rounded), label: const Text('Photo'))),
                  ]),
                  const SizedBox(height: 14),
                  for (final s in src)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: NovaCard(
                        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                        child: Row(children: [
                          const Icon(Icons.description_rounded, color: Color(0xFF22D3EE)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${s['content'].toString().length} caractères', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                            ]),
                          ),
                          IconButton(onPressed: () => _delete(s), icon: Icon(Icons.delete_outline_rounded, color: AppColors.muted)),
                        ]),
                      ),
                    ),
                  if (src.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Créer avec Lumi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in const [
                        ['summary', 'Résumé', Icons.short_text_rounded],
                        ['guide', 'Guide d\'étude', Icons.menu_book_rounded],
                        ['faq', 'FAQ', Icons.help_outline_rounded],
                        ['quiz', 'Quiz', Icons.quiz_rounded],
                        ['cards', 'Fiches', Icons.style_rounded],
                      ])
                        ActionChip(
                          avatar: Icon(t[2] as IconData, size: 18),
                          label: Text(t[1] as String),
                          onPressed: _busy ? null : () => _make(t[0] as String, t[1] as String),
                        ),
                    ]),
                  ],
                  if (_qa.isNotEmpty) const SizedBox(height: 18),
                  for (final x in _qa) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6, left: 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(18)),
                        child: Text(x.q, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12, right: 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.surface2)),
                        child: x.a == null
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text.rich(TextSpan(children: novaSpans(x.a!, TextStyle(height: 1.45, color: x.err ? const Color(0xFFF87171) : AppColors.text)))),
                      ),
                    ),
                  ],
                ]),
        ),
        if (_busy && _qa.isEmpty) const LinearProgressIndicator(minHeight: 3),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ask,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Pose une question sur tes cours…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _TextScreen extends StatelessWidget {
  const _TextScreen({required this.title, required this.text});
  final String title, text;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          NovaBadge('Basé sur tes sources · généré par IA'),
          const SizedBox(height: 12),
          Text.rich(TextSpan(children: novaSpans(text, TextStyle(fontSize: 15.5, height: 1.5, color: AppColors.text)))),
        ]),
      );
}

class _CardsScreen extends StatefulWidget {
  const _CardsScreen({required this.cards});
  final List<Map<String, dynamic>> cards;
  @override
  State<_CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<_CardsScreen> {
  int _i = 0;
  bool _back = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.cards[_i];
    return Scaffold(
      appBar: AppBar(title: Text('Fiches ${_i + 1} / ${widget.cards.length}')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _back = !_back),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: _back ? novaGradient : null,
                  color: _back ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.surface2),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_back ? 'RÉPONSE' : 'QUESTION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: _back ? Colors.white70 : const Color(0xFF22D3EE))),
                    const SizedBox(height: 14),
                    Text(cleanAiText((_back ? c['back'] : c['front']).toString()),
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4, color: _back ? Colors.white : AppColors.text)),
                    const SizedBox(height: 18),
                    Text('Touche pour retourner', style: TextStyle(fontSize: 12, color: _back ? Colors.white60 : AppColors.muted)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _i == 0 ? null : () => setState(() { _i--; _back = false; }), child: const Text('Précédente'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _i + 1 >= widget.cards.length ? () => Navigator.pop(context) : () => setState(() { _i++; _back = false; }), child: Text(_i + 1 >= widget.cards.length ? 'Terminer' : 'Suivante'))),
          ]),
        ]),
      ),
    );
  }
}
