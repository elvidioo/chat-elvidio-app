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
}
