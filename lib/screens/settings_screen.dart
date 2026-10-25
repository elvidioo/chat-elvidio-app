import 'package:flutter/material.dart';

import '../notifications.dart';
import 'blocked_screen.dart';
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
          ValueListenableBuilder<String>(
            valueListenable: s.photoQuality,
            builder: (context, q, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Qualité des photos envoyées'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'low', label: Text('Légère')),
                      ButtonSegment(value: 'normal', label: Text('Normale')),
                      ButtonSegment(value: 'high', label: Text('Haute')),
                    ],
                    selected: {q},
                    onSelectionChanged: (v) => s.setPhotoQuality(v.first),
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.autoPhotos,
            builder: (context, on, _) => SwitchListTile(
              title: const Text('Charger les photos automatiquement'),
              subtitle: Text(
                'Désactivé : les photos se chargent quand tu les touches. Les vidéos ne se téléchargent jamais toutes seules. Une photo déjà chargée n\'est jamais retéléchargée.',
                style: TextStyle(color: AppColors.muted),
              ),
              value: on,
              onChanged: s.setAutoPhotos,
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: s.mediaBytes,
            builder: (context, n, _) => ListTile(
              title: const Text('Données de médias utilisées'),
              subtitle: Text(
                '${(n / (1024 * 1024)).toStringAsFixed(1)} Mo envoyés et téléchargés par cette app (mesuré, hors messages texte)',
                style: TextStyle(color: AppColors.muted),
              ),
              trailing: TextButton(
                onPressed: s.resetMediaBytes,
                child: const Text('Remettre à 0'),
              ),
            ),
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
