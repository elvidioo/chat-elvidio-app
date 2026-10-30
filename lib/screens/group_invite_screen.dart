import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

const inviteScheme = 'chatelvidio://join/';

/// Pour les admins : crée un code d'invitation (QR + texte), valable 7 jours.
class GroupInviteScreen extends StatefulWidget {
  const GroupInviteScreen({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends State<GroupInviteScreen> {
  final db = Supabase.instance.client;
  String? code;
  String? error;
  bool loading = false;

  Future<void> _create() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = await db.rpc('create_group_invite',
          params: {'gid': widget.group['id'], 'days': 7});
      if (mounted) setState(() => code = c.toString());
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de créer l\'invitation (admin ? connexion ?).');
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _revoke() async {
    try {
      await db.rpc('revoke_group_invites', params: {'gid': widget.group['id']});
      if (mounted) {
        setState(() => code = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Toutes les invitations de ce groupe sont désactivées.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Action impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.group['name']?.toString() ?? 'Groupe';
    return Scaffold(
      appBar: AppBar(title: const Text('Inviter dans le groupe')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Toute personne ayant ce code peut rejoindre le groupe pendant 7 jours (100 personnes maximum). Ne le partage qu\'avec ceux que tu veux inviter.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          if (code == null) ...[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton.icon(
              onPressed: loading ? null : _create,
              icon: const Icon(Icons.qr_code_2),
              label: Text(loading ? 'Création…' : 'Créer une invitation'),
            ),
          ] else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: QrImageView(
                  data: '$inviteScheme$code',
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code!,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copié')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copier'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Share.share(
                      'Rejoins « $name » sur Veyra !\n'
                      'Code d\'invitation : $code\n'
                      'Dans l\'app : Discussions → icône Communautés → « Rejoindre ».\n'
                      'Télécharger l\'app : https://github.com/elvidioo/chat-elvidio-app/releases/latest/download/chat-elvidio.apk',
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Partager'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _revoke,
            icon: const Icon(Icons.link_off, color: Colors.redAccent),
            label: const Text('Désactiver toutes les invitations',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
