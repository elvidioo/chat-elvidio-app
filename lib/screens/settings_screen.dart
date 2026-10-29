import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../call_service.dart';
import '../push.dart';
import '../repo.dart';
import 'admin_screen.dart';
import 'ai_assistant_screen.dart';
import 'auth_screen.dart';
import 'invite_screen.dart';
import 'premium_screen.dart';

import '../notifications.dart';
import '../policy_text.dart';
import 'blocked_screen.dart';
import 'data_saver_screen.dart';
import '../settings.dart';
import '../theme.dart';
import '../premium.dart';
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
          section('Intelligence artificielle'),
          ListTile(
            leading: Icon(Icons.smart_toy_outlined, color: AppColors.primary),
            title: const Text('Réponse automatique à ma place'),
            subtitle: Text('L\'IA répond à tes amis quand tu es indisponible.',
                style: TextStyle(color: AppColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AiAssistantScreen())),
          ),
          section('Soutien'),
          ListTile(
            leading: Icon(Icons.group_add_rounded, color: AppColors.primary),
            title: const Text('Inviter des amis'),
            subtitle: Text('Partage ton code : 3 jours de Premium chacun.',
                style: TextStyle(color: AppColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const InviteScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: AppColors.gold),
            title: const Text('Premium'),
            subtitle: Text('Badge doré, stories de 72 h, soutiens l\'app.',
                style: TextStyle(color: AppColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: Premium.I.isAdmin,
            builder: (context, admin, _) => admin
                ? ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
                    title: const Text('Administration'),
                    subtitle: Text('Demandes Premium, prix, paiement.',
                        style: TextStyle(color: AppColors.muted)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                  )
                : const SizedBox.shrink(),
          ),
          section('Arrière-plan et notifications'),
          ListTile(
            leading: Icon(Icons.notifications_active_outlined, color: AppColors.primary),
            title: const Text('Recevoir les messages et appels app fermée'),
            subtitle: Text(
              'Teste les notifications et autorise l\'app à rester active en arrière-plan.',
              style: TextStyle(color: AppColors.muted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _backgroundHelp(context),
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
          ValueListenableBuilder<bool>(
            valueListenable: s.hideStatus,
            builder: (context, on, _) => SwitchListTile(
              title: const Text('Masquer mon statut'),
              subtitle: Text(
                'Les autres ne voient plus quand tu es en ligne, ni « Vu à… », ni quand tu écris.',
                style: TextStyle(color: AppColors.muted),
              ),
              value: on,
              onChanged: (v) {
                s.setHideStatus(v);
                LivePresence.I.applyVisibility();
                Repo.I.touchLastSeen();
              },
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
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined,
                color: Colors.redAccent),
            title: const Text('Supprimer mon compte',
                style: TextStyle(color: Colors.redAccent)),
            subtitle: Text(
              'Efface définitivement ton profil, tes messages, tes fichiers et tes publications.',
              style: TextStyle(color: AppColors.muted),
            ),
            onTap: () => _deleteAccount(context),
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

Future<void> _deleteAccount(BuildContext context) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Supprimer ton compte ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'C\'est définitif : profil, messages, fichiers et publications seront effacés. Les groupes que tu as créés restent, gérés par un autre membre.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'Écris SUPPRIMER pour confirmer'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler')),
        TextButton(
            onPressed: () =>
                Navigator.pop(c, ctrl.text.trim().toUpperCase() == 'SUPPRIMER'),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent))),
      ],
    ),
  );
  ctrl.dispose();
  if (ok != true) return;
  try {
    final db = Supabase.instance.client;
    final res = await db.functions.invoke('delete-account');
    if (res.status != 200) throw Exception('http ${res.status}');
    CallService.I.stop();
    await Push.logout();
    LivePresence.I.stop();
    Premium.I.stop();
    await Repo.I.stop();
    try {
      await db.auth.signOut();
    } catch (_) {}
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Suppression impossible. Vérifie ta connexion et réessaie.')));
  }
}

Future<void> _backgroundHelp(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (c) => const _BackgroundDialog(),
  );
}

class _BackgroundDialog extends StatefulWidget {
  const _BackgroundDialog();

  @override
  State<_BackgroundDialog> createState() => _BackgroundDialogState();
}

class _BackgroundDialogState extends State<_BackgroundDialog> {
  String _push = 'Vérification…';
  bool _notif = false;
  bool _battery = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await Permission.notification.isGranted;
    final b = await Permission.ignoreBatteryOptimizations.isGranted;
    final p = await Push.diagnose();
    if (mounted) {
      setState(() {
        _notif = n;
        _battery = b;
        _push = p;
      });
    }
  }

  Widget _row(bool ok, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                size: 20, color: ok ? Colors.green : Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Arrière-plan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(_notif, _notif ? 'Notifications autorisées' : 'Notifications non autorisées'),
            _row(_push.startsWith('OK'), _push),
            _row(_battery,
                _battery ? 'App non limitée par la batterie' : 'La batterie peut mettre l\'app en veille'),
            const SizedBox(height: 10),
            Text(
              'Sur certains téléphones (Tecno, Infinix, Xiaomi, Samsung…), il faut aussi autoriser « Démarrage automatique » et « Aucune restriction » pour Chat Elvidio dans les réglages du téléphone.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Permission.notification.request();
            _refresh();
          },
          child: const Text('Autoriser notifs'),
        ),
        TextButton(
          onPressed: () async {
            await Permission.ignoreBatteryOptimizations.request();
            _refresh();
          },
          child: const Text('Batterie : autoriser'),
        ),
        TextButton(
          onPressed: () async {
            final ok = await Notifier.testNotification();
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications indisponibles.')));
            }
          },
          child: const Text('Tester'),
        ),
        TextButton(onPressed: openAppSettings, child: const Text('Réglages du téléphone')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    );
  }
}
