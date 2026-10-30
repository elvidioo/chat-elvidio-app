import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repo.dart';
import '../theme.dart';
import 'group_chat_screen.dart';
import 'group_invite_screen.dart';

/// Extrait le code d'un lien/QR « chatelvidio://join/CODE » ou d'un code brut.
String? parseInviteCode(String raw) {
  var s = raw.trim();
  if (s.startsWith(inviteScheme)) s = s.substring(inviteScheme.length);
  s = s.toUpperCase();
  return RegExp(r'^[A-Z0-9]{10}$').hasMatch(s) ? s : null;
}

/// Rejoindre un groupe avec un code ou en scannant un QR.
class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final db = Supabase.instance.client;
  final input = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    Clipboard.getData('text/plain').then((d) {
      final c = parseInviteCode(d?.text ?? '');
      if (c != null && mounted && input.text.isEmpty) {
        setState(() => input.text = c);
      }
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScannerScreen()),
    );
    if (raw == null) return;
    final c = parseInviteCode(raw);
    if (c == null) {
      setState(() => error = 'Ce QR code n\'est pas une invitation Veyra.');
      return;
    }
    setState(() => input.text = c);
    _check();
  }

  Future<void> _check() async {
    final code = parseInviteCode(input.text);
    if (code == null) {
      setState(() => error = 'Code invalide (10 lettres ou chiffres).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rows = await db.rpc('preview_group_invite', params: {'invite_code': code});
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) {
        setState(() => error = 'Invitation invalide, expirée ou désactivée.');
        return;
      }
      final g = list.first;
      if (g['already_member'] == true) {
        setState(() => error = 'Tu es déjà dans « ${g['name']} ».');
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(g['name'].toString()),
          content: Text('${g['members']} membre(s). Rejoindre ce groupe ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Rejoindre')),
          ],
        ),
      );
      if (ok != true) return;
      final gid = await db.rpc('join_group_by_code', params: {'invite_code': code});
      await Repo.I.loadGroups();
      final group = Repo.I.groups.value
          .where((x) => x['id'].toString() == gid.toString())
          .toList();
      if (!mounted) return;
      if (group.isNotEmpty) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => GroupChatScreen(group: group.first)));
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Impossible de rejoindre (connexion ?). Réessaie.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre un groupe')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Entre le code reçu, ou scanne le QR code d\'un administrateur.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: input,
            textCapitalization: TextCapitalization.characters,
            maxLength: 40,
            decoration: const InputDecoration(
              hintText: 'Code d\'invitation',
              counterText: '',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onSubmitted: (_) => busy ? null : _check(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _check,
            child: Text(busy ? 'Vérification…' : 'Continuer'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scanner un QR code'),
          ),
        ],
      ),
    );
  }
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner l\'invitation')),
      body: MobileScanner(
        onDetect: (capture) {
          if (done) return;
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && parseInviteCode(v) != null) {
              done = true;
              Navigator.pop(context, v);
              return;
            }
          }
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Caméra indisponible. Autorise la caméra pour l\'app, ou entre le code à la main.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
