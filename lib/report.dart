import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signaler un utilisateur ou un contenu abusif.
/// [kind] : 'user', 'message', 'group_message' ou 'post'.
Future<void> showReportDialog(
  BuildContext context, {
  required String kind,
  String? targetUser,
  int? targetId,
}) async {
  const reasons = [
    'Spam ou publicité',
    'Harcèlement ou menaces',
    'Contenu choquant ou violent',
    'Arnaque ou fausse identité',
    'Autre',
  ];
  final picked = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Signaler'),
      children: [
        for (final r in reasons)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, r),
            child: Text(r),
          ),
      ],
    ),
  );
  if (picked == null) return;
  try {
    await Supabase.instance.client.from('reports').insert({
      'kind': kind,
      'target_user': targetUser,
      'target_id': targetId,
      'reason': picked,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci, ton signalement a été envoyé.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signalement impossible. Réessaie.')),
      );
    }
  }
}
