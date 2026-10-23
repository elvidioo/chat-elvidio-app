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
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'theme': themeMode.value,
        'notifications': notifications.value,
        'readReceipts': readReceipts.value,
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
}
