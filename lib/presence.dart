import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Statut "en ligne", "est en train d'écrire" et photos de profil.
class LivePresence {
  LivePresence._();
  static final LivePresence I = LivePresence._();

  /// Identifiants des personnes actuellement en ligne.
  final ValueNotifier<Set<String>> online = ValueNotifier<Set<String>>({});

  /// Personnes qui sont en train de m'écrire.
  final ValueNotifier<Set<String>> typingToMe = ValueNotifier<Set<String>>({});

  /// id -> url de la photo de profil.
  final ValueNotifier<Map<String, String>> avatars =
      ValueNotifier<Map<String, String>>({});

  /// Etat de la connexion temps réel (affiché dans Paramètres).
  final ValueNotifier<String> status = ValueNotifier<String>('non connecté');

  RealtimeChannel? _ch;
  String? _uid;
  String? _typingTo;
  Timer? _typingReset;

  void setAvatars(Iterable<Map<String, dynamic>> profiles) {
    final m = <String, String>{...avatars.value};
    for (final p in profiles) {
      final u = p['avatar_url']?.toString() ?? '';
      if (u.isNotEmpty) {
        m[p['id'].toString()] = u;
      } else {
        m.remove(p['id'].toString());
      }
    }
    avatars.value = m;
  }

  void setMyAvatar(String id, String url) {
    avatars.value = {...avatars.value, id: url};
  }

  void start() {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;
    if (_ch != null && _uid == uid) return;
    stop();
    _uid = uid;
    final ch = db.channel('lobby', opts: RealtimeChannelConfig(key: uid));
    _ch = ch;
    ch.onPresenceSync((_) {
      final on = <String>{};
      final typing = <String>{};
      for (final s in ch.presenceState()) {
        for (final p in s.presences) {
          on.add(s.key);
          if (p.payload['typing_to'] == uid) typing.add(s.key);
        }
      }
      on.remove(uid);
      online.value = on;
      typingToMe.value = typing;
    }).subscribe((st, [error]) async {
      this.status.value = error == null ? st.name : '${st.name}: $error';
      if (st == RealtimeSubscribeStatus.subscribed) {
        await ch.track({'typing_to': _typingTo});
      }
    });
  }

  /// Dit aux autres que j'écris (ou plus) à [peer].
  void setTyping(String? peer) {
    _typingReset?.cancel();
    if (peer != null) {
      _typingReset = Timer(const Duration(seconds: 4), () => setTyping(null));
    }
    if (_typingTo == peer) return;
    _typingTo = peer;
    try {
      _ch?.track({'typing_to': peer});
    } catch (_) {}
  }

  void stop() {
    _typingReset?.cancel();
    final ch = _ch;
    _ch = null;
    _uid = null;
    _typingTo = null;
    online.value = {};
    typingToMe.value = {};
    if (ch != null) {
      try {
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
  }
}
