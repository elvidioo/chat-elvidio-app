import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../presence.dart';
import '../call_service.dart';
import '../push.dart';
import '../repo.dart';
import '../theme.dart';
import '../settings.dart';
import 'data_saver_screen.dart';
import 'settings_screen.dart';
import '../updater.dart';
import '../widgets.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.firstTime = false,
    this.showLogout = false,
    this.onSaved,
  });

  final bool firstTime;
  final bool showLogout;
  final VoidCallback? onSaved;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _pseudo = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _pseudo.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return;

      final profile = await _db
          .from('profiles')
          .select('pseudo, bio')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        _pseudo.text = profile?['pseudo']?.toString() ?? '';
        _bio.text = profile?['bio']?.toString() ?? '';
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de charger le profil.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );
      if (file == null) return;
      setState(() => _saving = true);
      final bytes = await file.readAsBytes();
      final path = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from('media').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      final url = _db.storage.from('media').getPublicUrl(path);
      await _db.from('profiles').update({'avatar_url': url}).eq('id', user.id);
      LivePresence.I.setMyAvatar(user.id, url);
      widget.onSaved?.call();
    } catch (_) {
      if (mounted) setState(() => _error = 'Photo impossible à envoyer.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveProfile() async {
    final pseudo = _pseudo.text.trim();
    final user = _db.auth.currentUser;

    if (user == null) return;
    if (pseudo.length < 3 || pseudo.length > 30) {
      setState(
          () => _error = 'Le pseudo doit contenir entre 3 et 30 caractères.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _db.from('profiles').upsert({
        'id': user.id,
        'pseudo': pseudo,
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
      }, onConflict: 'id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré !')),
      );
      if (widget.firstTime) Navigator.pop(context);
      widget.onSaved?.call();
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == '23505'
            ? 'Ce pseudo est déjà pris.'
            : 'Enregistrement impossible : ${e.message}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erreur réseau. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
            'Les messages en attente d\'envoi sur ce téléphone seront perdus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok == true) await _logout();
  }

  Future<void> _logout() async {
    CallService.I.stop();
    await Push.logout();
    LivePresence.I.stop();
    await Repo.I.stop();
    await _db.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstTime ? 'Bienvenue !' : 'Mon profil'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: widget.firstTime ? null : _pickPhoto,
                      child: Stack(
                        children: [
                          Avatar(
                            name: _pseudo.text,
                            size: 96,
                            userId: _db.auth.currentUser?.id,
                          ),
                          if (!widget.firstTime)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 15,
                                backgroundColor: AppColors.primary,
                                child: const Icon(Icons.camera_alt,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.firstTime
                        ? 'Choisis ton pseudo : c\'est le nom que verront tes amis.'
                        : 'Ton pseudo visible par les autres.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _pseudo,
                    maxLength: 30,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Pseudo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    maxLength: 200,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Biographie (facultatif)',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  const SizedBox(height: 6),
                  GradientButton(
                    label: 'Enregistrer',
                    loading: _saving,
                    onPressed: _saveProfile,
                  ),
                  if (widget.showLogout) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    ValueListenableBuilder<String>(
                      valueListenable: AppSettings.I.themeMode,
                      builder: (context, mode, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'system',
                                icon: Icon(Icons.brightness_auto),
                                label: Text('Auto')),
                            ButtonSegment(
                                value: 'light',
                                icon: Icon(Icons.light_mode),
                                label: Text('Clair')),
                            ButtonSegment(
                                value: 'dark',
                                icon: Icon(Icons.dark_mode),
                                label: Text('Sombre')),
                          ],
                          selected: {mode},
                          onSelectionChanged: (v) =>
                              AppSettings.I.setTheme(v.first),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.eco_rounded, color: AppColors.primary),
                      title: const Text('Économie de données'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DataSaverScreen()),
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.settings, color: AppColors.primary),
                      title: const Text('Paramètres, confidentialité et sécurité'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.person_add_alt_1, color: AppColors.primary),
                      title: const Text('Inviter des amis'),
                      onTap: () => Share.share(
                        'Rejoins-moi sur Chat Elvidio ! Télécharge l\'app ici : '
                        'https://github.com/elvidioo/chat-elvidio-app/releases/latest/download/chat-elvidio.apk',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      label: const Text(
                        'Se déconnecter',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'Version ${currentBuild == 0 ? 'développement' : currentBuild}',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => checkAndPrompt(context),
                      icon: const Icon(Icons.system_update),
                      label: const Text('Rechercher une mise à jour'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
