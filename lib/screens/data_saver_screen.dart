import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../settings.dart';
import '../theme.dart';

/// Elvidio Data Mini : uniquement des réglages réellement appliqués par l'app.
class DataSaverScreen extends StatefulWidget {
  const DataSaverScreen({super.key});

  @override
  State<DataSaverScreen> createState() => _DataSaverScreenState();
}

class _DataSaverScreenState extends State<DataSaverScreen> {
  int? cacheBytes;
  bool clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<Directory> _cacheDir() async {
    final dir = await getApplicationSupportDirectory();
    return Directory('${dir.path}/img_cache');
  }

  Future<void> _measure() async {
    var total = 0;
    try {
      final d = await _cacheDir();
      if (await d.exists()) {
        await for (final f in d.list()) {
          if (f is File) total += await f.length();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => cacheBytes = total);
  }

  Future<void> _clear() async {
    setState(() => clearing = true);
    try {
      final d = await _cacheDir();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    await _measure();
    if (mounted) {
      setState(() => clearing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cache des photos vidé')));
    }
  }

  String _mb(int n) => '${(n / (1024 * 1024)).toStringAsFixed(1)} Mo';

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: AppColors.goldText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Économie de données')),
      body: ListView(
        children: [
          _title('Photos envoyées'),
          ValueListenableBuilder<String>(
            valueListenable: s.photoQuality,
            builder: (context, q, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'low', label: Text('Légère')),
                      ButtonSegment(value: 'normal', label: Text('Normale')),
                      ButtonSegment(value: 'high', label: Text('Haute')),
                    ],
                    selected: {q},
                    onSelectionChanged: (v) => s.setPhotoQuality(v.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    q == 'low'
                        ? 'Réduites à 960 px, qualité 45 % : les plus petits fichiers.'
                        : q == 'high'
                            ? 'Jusqu\'à 1920 px, qualité 90 % : plus de détails, plus de données.'
                            : 'Jusqu\'à 1280 px, qualité 70 % : bon compromis.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          _title('Photos reçues'),
          ValueListenableBuilder<bool>(
            valueListenable: s.autoPhotos,
            builder: (context, on, _) => SwitchListTile(
              title: const Text('Charger les photos automatiquement'),
              subtitle: Text(
                on
                    ? 'Les photos se chargent à l\'affichage.'
                    : 'Les photos se chargent quand tu les touches. Les photos de profil restent automatiques.',
                style: TextStyle(color: AppColors.muted),
              ),
              value: on,
              onChanged: s.setAutoPhotos,
            ),
          ),
          ListTile(
            leading: Icon(Icons.play_circle_outline, color: AppColors.primary),
            title: const Text('Vidéos'),
            subtitle: Text(
              'Jamais téléchargées ni lues automatiquement : elles ne partent qu\'au toucher.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          ListTile(
            leading: Icon(Icons.network_check, color: AppColors.primary),
            title: const Text('Type de connexion'),
            subtitle: Text(
              'L\'app ne sait pas distinguer Wi-Fi et données mobiles : les réglages valent pour les deux.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          _title('Cache et mesures'),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: AppColors.primary),
            title: const Text('Photos gardées sur ce téléphone'),
            subtitle: Text(
              cacheBytes == null
                  ? 'Calcul…'
                  : '${_mb(cacheBytes!)} · une photo déjà chargée n\'est jamais retéléchargée',
              style: TextStyle(color: AppColors.muted),
            ),
            trailing: TextButton(
              onPressed: clearing ? null : _clear,
              child: const Text('Vider'),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: s.mediaBytes,
            builder: (context, n, _) => ListTile(
              leading: Icon(Icons.data_usage, color: AppColors.primary),
              title: const Text('Médias transférés'),
              subtitle: Text(
                '${_mb(n)} envoyés et téléchargés par l\'app (mesuré, hors texte)',
                style: TextStyle(color: AppColors.muted),
              ),
              trailing: TextButton(
                onPressed: s.resetMediaBytes,
                child: const Text('Remettre à 0'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
