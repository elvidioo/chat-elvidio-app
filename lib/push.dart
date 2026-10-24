import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'settings.dart';

/// Notifications push (Firebase) : reçues même quand l'app est fermée.
class Push {
  static bool _ready = false;
  static String? _token;

  static SupabaseClient get _db => Supabase.instance.client;

  /// À appeler une fois connecté.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      if (!_ready) {
        try {
          await Firebase.initializeApp();
        } catch (_) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: 'AIzaSyD0qiS6DeBhubUjUdLJRH4SlpI4nHJliLE',
              appId: '1:279434771228:android:a4adb24ac47d9fc03cd8d9',
              messagingSenderId: '279434771228',
              projectId: 'chat-elvidio',
            ),
          );
        }
        _ready = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((t) {
          _token = t;
          sync();
        });
        AppSettings.I.notifications.addListener(sync);
      }
      await sync();
    } catch (_) {}
  }

  /// Enregistre (ou retire) ce téléphone selon le réglage "Notifications".
  static Future<void> sync() async {
    if (!_ready) return;
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      _token ??= await FirebaseMessaging.instance.getToken();
      final t = _token;
      if (t == null) return;
      if (AppSettings.I.notifications.value) {
        await _db.from('device_tokens').upsert({
          'token': t,
          'user_id': uid,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await _db.from('device_tokens').delete().eq('token', t);
      }
    } catch (_) {}
  }

  /// À la déconnexion : ce téléphone ne reçoit plus les messages de ce compte.
  static Future<void> logout() async {
    try {
      final t = _token;
      if (t != null) await _db.from('device_tokens').delete().eq('token', t);
    } catch (_) {}
  }
}
