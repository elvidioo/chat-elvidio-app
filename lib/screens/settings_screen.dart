import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../repo.dart';

import '../notifications.dart';
import '../policy_text.dart';
import 'blocked_screen.dart';
import 'data_saver_screen.dart';
import '../settings.dart';
import '../theme.dart';
import '../presence.dart';
import '../updater.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title,
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          section('Apparence'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ValueListenableBuilder<String>(
              valueListenable: s.themeMode,
              builder: (context, mode, _) => SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('Système')),
                    ButtonSegment(value: 'light', label: Text('Clair')),
                    ButtonSegment(value: 'dark', label: Text('Sombre')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => s.setTheme(v.first),
                ),
              ),
            ),
          ),
          section('Messages'),
          ValueListenableBuilder<bool>(
            valueListenable: s.notifications,
            builder: (context, on, _) => SwitchListTile(
              title: const Text('Notifications'),
              subtitle: Text(
                'Une alerte quand tu reçois un message, tant que l\'app est active.',
                style: TextStyle(color: AppColors.muted),
              ),
              value: on,
              onChanged: (v) {
                s.setNotifications(v);
                if (v) Notifier.requestPermission();
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.readReceipts,
            builder: (context, on, _) => SwitchListTile(
              title: const Text('Confirmations de lecture'),
              subtitle: Text(
                'Les autres voient « Vu » quand tu lis leurs messages, et tu vois le leur.',
                style: TextStyle(color: AppColors.muted),
              ),
              value: on,
              onChanged: s.setReadReceipts,
            ),
          ),
          section('Économie de données'),
          ListTile(
            leading: Icon(Icons.eco_rounded, color: AppColors.primary),
            title: const Text('Elvidio Data Mini'),
            subtitle: Text('Qualité des photos, chargement à la demande, cache',
                style: TextStyle(color: AppColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataSaverScreen()),
            ),
          ),
          section('Mes données'),
          ListTile(
            leading: Icon(Icons.download_for_offline_outlined,
                color: AppColors.primary),
            title: const Text('Exporter mes discussions'),
            subtitle: Text(
              'Crée un fichier avec les messages chargés sur ce téléphone. Tes messages restent aussi sur ton compte : ils reviennent quand tu te reconnectes.',
              style: TextStyle(color: AppColors.muted),
            ),
            onTap: () => _exportChats(context),
          ),
          section('Confidentialité'),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Utilisateurs bloqués'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BlockedScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Politique de confidentialité'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Confidentialité')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      privacyText.replaceAll('**', ''),
                      style: const TextStyle(height: 1.45),
                    ),
                  ),
                ),
              ),
            ),
          ),
          section('À propos'),
          ListTile(
            title: const Text('Version'),
            trailing: Text(
              currentBuild == 0 ? 'développement' : '$currentBuild',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: LivePresence.I.status,
            builder: (context, v, _) => ListTile(
              title: const Text('Connexion temps réel'),
              subtitle: Text(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Rechercher une mise à jour'),
            onTap: () => checkAndPrompt(context),
          ),
        ],
      ),
    );
  }
}

Future<void> _exportChats(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final names = Repo.I.names;
    final rows = [
      for (final m in Repo.I.messages.value)
        {
          'date': m['created_at'],
          'de': names[m['sender'].toString()] ?? m['sender'],
          'a': names[m['receiver'].toString()] ?? m['receiver'],
          'texte': m['content'],
          'fichier': m['media_name'] ?? (m['media_url'] != null ? 'média' : null),
        }
    ];
    if (rows.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Aucun message à exporter.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/chat-elvidio-discussions.json');
    await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(rows));
    await Share.shareXFiles([XFile(f.path)],
        text: 'Mes discussions Chat Elvidio');
  } catch (e) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Export impossible.')));
  }
}
