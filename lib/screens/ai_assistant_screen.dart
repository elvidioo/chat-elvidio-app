import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

/// Assistant IA : répond à ta place, aux messages texte privés, quand tu es indisponible.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _db = Supabase.instance.client;
  final _instr = TextEditingController();
  bool _enabled = false;
  bool _always = true;
  int _from = 22 * 60;
  int _to = 7 * 60;
  bool _ready = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _instr.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = _db.auth.currentUser!.id;
      final s = await _db.from('ai_settings').select().eq('user_id', me).maybeSingle();
      if (s != null) {
        _enabled = s['enabled'] == true;
        _always = s['always'] != false;
        _from = (s['from_min'] as num).toInt();
        _to = (s['to_min'] as num).toInt();
        _instr.text = s['instructions']?.toString() ?? '';
      }
      final c = await _db.from('app_config').select('value').eq('key', 'ai_ready').maybeSingle();
      _ready = c?['value'] == '1';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _db.from('ai_settings').upsert({
        'user_id': _db.auth.currentUser!.id,
        'enabled': _enabled,
        'always': _always,
        'from_min': _from,
        'to_min': _to,
        // Fuseau de ce téléphone (ex. Bénin = +60 min)
        'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
        'instructions': _instr.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      _toast('Enregistré.');
    } catch (_) {
      _toast('Enregistrement impossible.');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Activer l\'assistant IA ?'),
          content: const Text(
              'Quand tu es indisponible, les messages texte que tes amis t\'envoient en discussion privée sont transmis à un service d\'IA (Google Gemini ou Anthropic) pour écrire une réponse à ta place.\n\n'
              'Tes amis voient clairement « Réponse automatique (IA) ». Les photos, vocaux, appels et groupes ne sont jamais traités. Tu peux désactiver à tout moment.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activer')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _enabled = v);
    await _save();
  }

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pick(bool from) async {
    final cur = from ? _from : _to;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t == null) return;
    setState(() {
      if (from) {
        _from = t.hour * 60 + t.minute;
      } else {
        _to = t.hour * 60 + t.minute;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réponse automatique')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_ready)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                        'Le service d\'IA n\'est pas encore branché sur le serveur : les réglages sont enregistrés mais aucune réponse ne partira pour l\'instant.'),
                  ),
                SwitchListTile(
                  title: const Text('Répondre à ma place'),
                  subtitle: Text('Messages texte privés uniquement.',
                      style: TextStyle(color: AppColors.muted)),
                  value: _enabled,
                  onChanged: _toggle,
                ),
                const Divider(),
                RadioListTile<bool>(
                  title: const Text('Tout le temps (tant que c\'est activé)'),
                  value: true,
                  groupValue: _always,
                  onChanged: (v) => setState(() => _always = true),
                ),
                RadioListTile<bool>(
                  title: const Text('Seulement sur une plage horaire'),
                  value: false,
                  groupValue: _always,
                  onChanged: (v) => setState(() => _always = false),
                ),
                if (!_always)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                              onPressed: () => _pick(true), child: Text('De ${_fmt(_from)}')),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                              onPressed: () => _pick(false), child: Text('à ${_fmt(_to)}')),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('Consignes pour l\'assistant (facultatif)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: _instr,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Ex : Je suis en cours jusqu\'à 17 h. Reste poli et bref. Pour une urgence, dis d\'appeler.',
                  ),
                ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Enregistrer'),
                ),
                const SizedBox(height: 16),
                Text(
                  'L\'assistant n\'invente aucun engagement et ne s\'arrête pas de lui-même : il se tait dès que tu réponds toi-même, et envoie au plus 5 réponses par heure et par contact.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
    );
  }
}
