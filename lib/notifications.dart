import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Notifications locales : affichées quand l'app reçoit un message
/// (app ouverte ou encore active en arrière-plan).
class Notifier {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'messages',
            'Messages',
            description: 'Nouveaux messages',
            importance: Importance.high,
          ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'calls',
            'Appels',
            description: 'Appels entrants',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ));
      _ready = true;
    } catch (_) {}
  }

  static Future<void> requestPermission() async {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'Nouveaux messages',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Notification d'appel entrant plein écran avec sonnerie (même app fermée).
  static Future<void> showCall({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'calls',
            'Appels',
            channelDescription: 'Appels entrants',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: true,
            timeoutAfter: 40000,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
            additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT : la sonnerie se répète
            vibrationPattern: Int64List.fromList(<int>[0, 800, 600, 800, 600, 800]),
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  static Future<bool> testNotification() async {
    if (!_ready) await init();
    if (!_ready) return false;
    await show(
      id: 424242,
      title: 'Chat Elvidio',
      body: 'Test : les notifications fonctionnent sur ce téléphone.',
    );
    return true;
  }
}

/// Reçoit les messages Firebase quand l'app est fermée ou en arrière-plan.
/// Seuls les appels (message de données) passent ici : les messages normaux
/// sont affichés directement par Android.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final d = message.data;
  if (d['type'] != 'call') return;
  await Notifier.init();
  await Notifier.showCall(
    id: 777001,
    title: d['title']?.toString() ?? 'Appel entrant',
    body: d['body']?.toString() ?? 'Appel entrant',
  );
}
