// Version Lite : pas d'appels audio/vidéo (la bibliothèque WebRTC est retirée
// pour alléger l'APK). Ce fichier remplace lib/call_service.dart au moment du build Lite.
import 'package:flutter/material.dart';

class CallService {
  CallService._();
  static final CallService I = CallService._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void start() {}
  void stop() {}
  void onInviteMessage(Map<String, dynamic> m) {}

  Future<void> startCall(String peer, String name, {required bool withVideo}) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Les appels ne sont pas dans la version Lite. Installe la version complète pour appeler.')));
  }
}
