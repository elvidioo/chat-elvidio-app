import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Réglages de l'app, enregistrés dans un fichier sur le téléphone.
class AppSettings {
  AppSettings._();
  static final AppSettings I = AppSettings._();

  /// 'system', 'light' ou 'dark'
  final ValueNotifier<String> themeMode = ValueNotifier<String>('system');
  final ValueNotifier<bool> notifications = ValueNotifier<bool>(true);
  final ValueNotifier<bool> readReceipts = ValueNotifier<bool>(true);

  /// Économie de données : 'low' | 'normal' | 'high' (qualité des photos envoyées)
  final ValueNotifier<String> photoQuality = ValueNotifier<String>('normal');
  /// Chargement des photos reçues : true = automatique, false = à la demande
  final ValueNotifier<bool> autoPhotos = ValueNotifier<bool>(true);
  /// Messages cachés « pour moi » : clés 'm:<id>' (privé) ou 'g:<id>' (groupe).
  final ValueNotifier<Set<String>> hidden = ValueNotifier<Set<String>>({});
  /// Conversations épinglées : 'u:<id>' (contact) ou 'g:<id>' (groupe).
  final ValueNotifier<Set<String>> pinned = ValueNotifier<Set<String>>({});

  void hideMessage(String key) {
    hidden.value = {...hidden.value, key};
    _save();
  }

  void togglePin(String key) {
    final s = {...pinned.value};
    if (!s.remove(key)) s.add(key);
    pinned.value = s;
    _save();
  }

  /// Octets de médias réellement transférés (envoyés + téléchargés), mesurés.
  final ValueNotifier<int> mediaBytes = ValueNotifier<int>(0);

  /// (largeur max, qualité JPEG) selon le réglage.
  (double, int) get photoParams {
    switch (photoQuality.value) {
      case 'low':
        return (960, 45);
      case 'high':
        return (1920, 90);
      default:
        return (1280, 70);
    }
  }

  void addMediaBytes(int n) {
    mediaBytes.value += n;
    _save();
  }

  void resetMediaBytes() {
    mediaBytes.value = 0;
    _save();
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/settings.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final mode = data['theme']?.toString();
      if (mode == 'light' || mode == 'dark' || mode == 'system') {
        themeMode.value = mode!;
      }
      notifications.value = data['notifications'] != false;
      readReceipts.value = data['readReceipts'] != false;
      final q = data['photoQuality']?.toString();
      if (q == 'low' || q == 'normal' || q == 'high') photoQuality.value = q!;
      autoPhotos.value = data['autoPhotos'] != false;
      mediaBytes.value = (data['mediaBytes'] as num?)?.toInt() ?? 0;
      hidden.value = {for (final e in (data['hidden'] as List? ?? [])) e.toString()};
      pinned.value = {for (final e in (data['pinned'] as List? ?? [])) e.toString()};
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'theme': themeMode.value,
        'notifications': notifications.value,
        'readReceipts': readReceipts.value,
        'photoQuality': photoQuality.value,
        'autoPhotos': autoPhotos.value,
        'mediaBytes': mediaBytes.value,
        'hidden': hidden.value.toList(),
        'pinned': pinned.value.toList(),
      }));
    } catch (_) {}
  }

  void setTheme(String mode) {
    themeMode.value = mode;
    _save();
  }

  void setNotifications(bool on) {
    notifications.value = on;
    _save();
  }

  void setReadReceipts(bool on) {
    readReceipts.value = on;
    _save();
  }

  void setPhotoQuality(String q) {
    photoQuality.value = q;
    _save();
  }

  void setAutoPhotos(bool on) {
    autoPhotos.value = on;
    _save();
  }
}
