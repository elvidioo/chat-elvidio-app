import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/ai_chat_screen.dart';
import 'screens/invite_screen.dart';
import 'theme.dart';

/// Petit tour d'accueil, une seule fois par installation.
Future<void> showWelcomeIfNeeded(BuildContext context) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final marker = File('${dir.path}/welcome_v1');
    if (await marker.exists()) return;
    await marker.writeAsString('1');
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _Welcome(),
    );
  } catch (_) {}
}

class _Welcome extends StatefulWidget {
  const _Welcome();

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  final _page = PageController();
  int _i = 0;

  static const _steps = <(IconData, String, String)>[
    (Icons.chat_bubble_rounded, 'Discute et appelle',
        'Messages, photos, vocaux, appels audio et vidéo, stories : tout au même endroit.'),
    (Icons.auto_awesome, 'Elvidio IA t\'aide à réviser',
        'Cours expliqués, exercices corrigés, quiz du bac. Pose-lui n\'importe quelle question.'),
    (Icons.group_add_rounded, 'Invite tes amis',
        'Partage ton code : vous gagnez chacun 3 jours de Premium.'),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 210,
            child: PageView.builder(
              controller: _page,
              itemCount: _steps.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, i) {
                final s = _steps[i];
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(s.$1, size: 56, color: AppColors.primary),
                    const SizedBox(height: 14),
                    Text(s.$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(s.$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted)),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var k = 0; k < _steps.length; k++)
                Container(
                  margin: const EdgeInsets.all(3),
                  width: k == _i ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: k == _i ? AppColors.primary : AppColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('Passer')),
            const Spacer(),
            FilledButton(
              onPressed: () {
                if (!last) {
                  _page.nextPage(
                      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                  return;
                }
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const InviteScreen()));
              },
              child: Text(last ? 'Inviter mes amis' : 'Suivant'),
            ),
          ]),
          if (last)
            TextButton(
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const AiChatScreen()));
              },
              child: const Text('Essayer Elvidio IA'),
            ),
        ],
      ),
    );
  }
}
