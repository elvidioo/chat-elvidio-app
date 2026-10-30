import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

const _fullApk =
    'https://github.com/elvidioo/chat-elvidio-app/releases/latest/download/chat-elvidio.apk';
const _liteApk =
    'https://github.com/elvidioo/chat-elvidio-app/releases/latest/download/chat-elvidio-lite.apk';

/// Inviter des amis (code + lien à partager) et utiliser le code d'un ami.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _db = Supabase.instance.client;
  final _codeCtrl = TextEditingController();
  String? _code;
  int _invited = 0;
  bool _used = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = _db.auth.currentUser!.id;
      final code = await _db.rpc('my_invite_code');
      final rows = await _db.from('referrals').select('invitee, inviter');
      var invited = 0;
      var used = false;
      for (final r in rows) {
        if (r['inviter'] == me) invited++;
        if (r['invitee'] == me) used = true;
      }
      if (mounted) {
        setState(() {
          _code = code?.toString();
          _invited = invited;
          _used = used;
        });
      }
    } catch (_) {}
  }

  String get _message =>
      'Rejoins-moi sur Veyra : messages, appels, stories et une IA qui t\'aide à réviser !\n\n'
      'Télécharge l\'app : $_fullApk\n'
      'Version Lite (légère, peu de données) : $_liteApk\n\n'
      'Après l\'inscription, entre mon code d\'invitation : ${_code ?? ''}\n'
      'Nous gagnons chacun 3 jours de Premium.';

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _redeem() async {
    final c = _codeCtrl.text.trim();
    if (c.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final name = await _db.rpc('redeem_invite', params: {'code': c});
      _codeCtrl.clear();
      _toast('Code accepté : tu es maintenant ami avec $name. +3 jours de Premium !');
      await _load();
    } on PostgrestException catch (e) {
      _toast(e.message.isEmpty ? 'Code refusé.' : e.message);
    } catch (_) {
      _toast('Impossible pour le moment (connexion ?).');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inviter des amis')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite, gagne du Premium',
                    style: TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                    'Chaque ami qui entre ton code devient ton ami dans l\'app. '
                    'Vous gagnez tous les deux 3 jours de Premium (jusqu\'à 10 invitations).',
                    style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Ton code d\'invitation',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _code == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _code!));
                    _toast('Code copié.');
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(_code ?? '…',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _code == null ? null : () => Share.share(_message),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Partager (WhatsApp, SMS…)'),
          ),
          const SizedBox(height: 8),
          Center(
              child: Text('Amis invités : $_invited',
                  style: TextStyle(color: AppColors.muted))),
          const SizedBox(height: 22),
          Text('Tu as reçu un code ?',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 8),
          if (_used)
            Text('Tu as déjà utilisé un code d\'invitation.',
                style: TextStyle(color: AppColors.muted))
          else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  decoration: const InputDecoration(
                      hintText: 'Code à 8 caractères', counterText: ''),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _redeem,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Valider'),
              ),
            ]),
        ],
      ),
    );
  }
}
