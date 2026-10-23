import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notifications.dart';
import 'presence.dart';
import 'settings.dart';
import 'widgets.dart';

/// Source unique des messages : écoute le temps réel, garde une copie sur le
/// téléphone (visible sans internet) et déclenche les notifications.
class Repo {
  Repo._();
  static final Repo I = Repo._();

  /// Tous mes messages, du plus récent au plus ancien.
  final ValueNotifier<List<Map<String, dynamic>>> messages =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  List<Map<String, dynamic>> profiles = [];
  final Map<String, String> names = {};

  /// Conversation actuellement ouverte (pas de notification pour elle).
  String? activePeer;

  String? _uid;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _retry;
  Timer? _saveTimer;
  final Set<dynamic> _known = {};
  bool _silent = true;

  SupabaseClient get _db => Supabase.instance.client;

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/cache.json');
  }

  Future<void> _loadCache(String uid) async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (data['uid'] != uid) return;
      final list = (data['messages'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final prof = (data['profiles'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      profiles = prof;
      Presence.I.setAvatars(prof);
      for (final p in prof) {
        names[p['id'].toString()] = p['pseudo']?.toString() ?? '';
      }
      _known.addAll(list.map((m) => m['id']));
      messages.value = list;
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  Future<void> _saveNow() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final f = await _cacheFile();
      final list = messages.value;
      await f.writeAsString(jsonEncode({
        'uid': uid,
        'messages': list.length > 1500 ? list.sublist(0, 1500) : list,
        'profiles': profiles,
      }));
    } catch (_) {}
  }

  /// À appeler après la connexion et à chaque retour dans l'app.
  Future<void>? _ready;

  Future<void> start() => _ready = _start();

  Future<void> _start() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    if (_uid != uid) {
      _uid = uid;
      _known.clear();
      messages.value = [];
      profiles = [];
      names.clear();
      await _loadCache(uid);
    }
    _subscribe();
  }

  void _subscribe() {
    _retry?.cancel();
    _sub?.cancel();
    _silent = true;
    try {
      _sub = _db
          .from('messages')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .listen(_onData, onError: (_) => _scheduleRetry());
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 8), () {
      if (_uid != null) _subscribe();
    });
  }

  void _onData(List<Map<String, dynamic>> list) {
    final uid = _uid;
    if (uid == null) return;
    for (final m in list) {
      if (_known.add(m['id'])) {
        if (!_silent && m['receiver'] == uid && m['sender'] != uid) {
          _notify(m);
        }
      }
    }
    _silent = false;
    messages.value = List<Map<String, dynamic>>.from(list);
    _scheduleSave();
  }

  void _notify(Map<String, dynamic> m) {
    if (!AppSettings.I.notifications.value) return;
    final sender = m['sender'].toString();
    if (activePeer == sender) return;
    final text = m['content']?.toString() ?? '';
    final media = m['media_url']?.toString() ?? '';
    final body = text.isNotEmpty
        ? text
        : (media.isEmpty
            ? 'Nouveau message'
            : (isVideoUrl(media) ? '\u{1F3A5} Vidéo' : '\u{1F4F7} Photo'));
    Notifier.show(
      id: (m['id'] as num).toInt() & 0x7fffffff,
      title: names[sender] ?? 'Nouveau message',
      body: body,
    );
  }

  /// Contacts : depuis le serveur, sinon la copie enregistrée.
  Future<List<Map<String, dynamic>>> loadProfiles() async {
    try {
      await _ready;
    } catch (_) {}
    final uid = _db.auth.currentUser?.id;
    try {
      final data = await _db
          .from('profiles')
          .select('id, pseudo, avatar_url')
          .neq('id', uid ?? '')
          .order('pseudo')
          .timeout(const Duration(seconds: 6));
      profiles = List<Map<String, dynamic>>.from(data);
      Presence.I.setAvatars(profiles);
      for (final p in profiles) {
        names[p['id'].toString()] = p['pseudo']?.toString() ?? '';
      }
      _scheduleSave();
      return profiles;
    } catch (_) {
      if (profiles.isNotEmpty) return profiles;
      rethrow;
    }
  }

  /// À la déconnexion : on arrête tout et on efface la copie locale.
  Future<void> stop() async {
    _retry?.cancel();
    _saveTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    _known.clear();
    profiles = [];
    names.clear();
    messages.value = [];
    try {
      final f = await _cacheFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
