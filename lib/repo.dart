import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'media.dart';
import 'notifications.dart';
import 'presence.dart';
import 'settings.dart';

/// Source unique des messages : écoute le temps réel, garde une copie sur le
/// téléphone (visible sans internet) et déclenche les notifications.
class Repo {
  Repo._();
  static final Repo I = Repo._();

  /// Tous mes messages, du plus récent au plus ancien.
  final ValueNotifier<List<Map<String, dynamic>>> messages =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  List<Map<String, dynamic>> profiles = [];

  /// message -> (utilisateur -> emoji)
  final ValueNotifier<Map<int, Map<String, String>>> reactions =
      ValueNotifier<Map<int, Map<String, String>>>({});
  StreamSubscription<List<Map<String, dynamic>>>? _reactSub;

  /// Groupes dont je suis membre, et leurs messages (du plus récent au plus ancien).
  final ValueNotifier<List<Map<String, dynamic>>> groups =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);
  final ValueNotifier<List<Map<String, dynamic>>> groupMessages =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);
  /// Groupe actuellement ouvert (pas de notification pour lui).
  dynamic activeGroup;
  final Set<dynamic> _knownG = {};
  bool _silentG = true;
  final ValueNotifier<Map<int, Map<String, String>>> groupReactions =
      ValueNotifier<Map<int, Map<String, String>>>({});
  StreamSubscription<List<Map<String, dynamic>>>? _grSub;

  void _onGroupData(List<Map<String, dynamic>> l) {
    final uid = _uid;
    for (final m in l) {
      if (_knownG.add(m['id']) && !_silentG && m['sender'] != uid) {
        _notifyGroup(m);
      }
    }
    _silentG = false;
    groupMessages.value = List<Map<String, dynamic>>.from(l);
  }

  void _notifyGroup(Map<String, dynamic> m) {
    if (!AppSettings.I.notifications.value) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    if (activeGroup == m['group_id']) return;
    var gname = 'Groupe';
    for (final g in groups.value) {
      if (g['id'] == m['group_id']) gname = g['name']?.toString() ?? gname;
    }
    final who = names[m['sender'].toString()] ?? 'Quelqu\'un';
    final text = m['content']?.toString() ?? '';
    final media = m['media_url']?.toString() ?? '';
    Notifier.show(
      id: 1000000000 + ((m['id'] as num).toInt() % 1000000000),
      title: gname,
      body: '$who : ${text.isNotEmpty ? text : (media.isEmpty ? 'Nouveau message' : mediaLabel(media))}',
    );
  }

  StreamSubscription<List<Map<String, dynamic>>>? _gmSub;
  StreamSubscription<List<Map<String, dynamic>>>? _gmemSub;

  Future<void> loadGroups() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await _db
          .from('group_members')
          .select('group_id, groups(id, name, avatar_url, created_by)')
          .eq('user_id', uid);
      groups.value = [
        for (final e in r)
          if (e['groups'] != null) Map<String, dynamic>.from(e['groups'] as Map)
      ];
    } catch (_) {}
  }

  void _subscribeGroups() {
    loadGroups();
    _silentG = true;
    _grSub?.cancel();
    try {
      _grSub = _db
          .from('group_message_reactions')
          .stream(primaryKey: ['message_id', 'user_id']).listen((rows) {
        final m = <int, Map<String, String>>{};
        for (final r in rows) {
          final id = (r['message_id'] as num).toInt();
          (m[id] ??= {})[r['user_id'].toString()] = r['emoji'].toString();
        }
        groupReactions.value = m;
      }, onError: (_) {});
    } catch (_) {}
    _gmemSub?.cancel();
    _gmSub?.cancel();
    try {
      _gmemSub = _db
          .from('group_members')
          .stream(primaryKey: ['group_id', 'user_id']).listen((_) => loadGroups(),
              onError: (_) {});
      _gmSub = _db
          .from('group_messages')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .listen(_onGroupData, onError: (_) {});
    } catch (_) {}
  }


  Future<void> touchLastSeen() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db
          .from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid);
    } catch (_) {}
  }

  void _subscribeReactions() {
    _reactSub?.cancel();
    try {
      _reactSub = _db
          .from('message_reactions')
          .stream(primaryKey: ['message_id', 'user_id']).listen((rows) {
        final m = <int, Map<String, String>>{};
        for (final r in rows) {
          final id = (r['message_id'] as num).toInt();
          (m[id] ??= {})[r['user_id'].toString()] = r['emoji'].toString();
        }
        reactions.value = m;
      }, onError: (_) {});
    } catch (_) {}
  }

  // ---- File d'attente d'envoi (survit à la fermeture de l'app) ----
  final ValueNotifier<List<Map<String, dynamic>>> outbox =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);
  Timer? _flushTimer;
  bool _flushing = false;
  static const _maxQueue = 200;
  static const _maxAge = Duration(days: 7);

  Future<File> _outboxFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/outbox.json');
  }

  String _newId() {
    final r = Random.secure();
    String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }

  Future<void> _loadOutbox(String uid) async {
    try {
      final f = await _outboxFile();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (data['uid'] != uid) return;
      final cutoff = DateTime.now().toUtc().subtract(_maxAge);
      final list = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) =>
              (DateTime.tryParse(m['created_at']?.toString() ?? '') ?? cutoff)
                  .isAfter(cutoff))
          .toList();
      outbox.value = list;
    } catch (_) {}
  }

  Future<void> _saveOutbox() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final f = await _outboxFile();
      await f.writeAsString(jsonEncode({'uid': uid, 'items': outbox.value}));
    } catch (_) {}
  }

  /// Ajoute un message à la file : il s'affiche tout de suite, puis part dès que possible.
  Future<void> enqueue({
    required String receiver,
    required String content,
    dynamic replyTo,
  }) async {
    final uid = _uid ?? _db.auth.currentUser?.id;
    if (uid == null) return;
    final item = <String, dynamic>{
      'id': -DateTime.now().microsecondsSinceEpoch,
      'client_id': _newId(),
      'sender': uid,
      'receiver': receiver,
      'content': content,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'reply_to': replyTo,
      '_pending': true,
      '_failed': false,
    };
    var list = [item, ...outbox.value];
    if (list.length > _maxQueue) list = list.sublist(0, _maxQueue);
    outbox.value = list;
    await _saveOutbox();
    flush();
  }

  /// Envoie les messages en attente, du plus ancien au plus récent.
  Future<void> flush() async {
    if (_flushing || outbox.value.isEmpty) return;
    _flushing = true;
    try {
      final ordered = outbox.value.reversed.toList();
      for (final item in ordered) {
        try {
          await _db.from('messages').upsert({
            'client_id': item['client_id'],
            'sender': item['sender'],
            'receiver': item['receiver'],
            'content': item['content'],
            if (item['reply_to'] != null) 'reply_to': item['reply_to'],
          }, onConflict: 'sender,client_id', ignoreDuplicates: true)
              .timeout(const Duration(seconds: 10));
          outbox.value =
              outbox.value.where((m) => m['client_id'] != item['client_id']).toList();
          await _saveOutbox();
        } on PostgrestException catch (e) {
          // refus définitif (ex. plus amis, bloqué) : on abandonne ce message
          if (e.code == '42501' || e.code == '23503' || e.code == '23514') {
            outbox.value = outbox.value
                .where((m) => m['client_id'] != item['client_id'])
                .toList();
            await _saveOutbox();
          } else {
            item['_failed'] = true;
            outbox.value = List<Map<String, dynamic>>.from(outbox.value);
            break;
          }
        } catch (_) {
          item['_failed'] = true;
          outbox.value = List<Map<String, dynamic>>.from(outbox.value);
          break; // pas de réseau : on réessaiera
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => flush());
  }

  /// Demandes d'amis reçues, en attente.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
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
      LivePresence.I.setAvatars(prof);
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
      await _loadOutbox(uid);
    }
    _startFlushTimer();
    flush();
    _subscribe();
    _subscribeReactions();
    _subscribeGroups();
    _refreshProfiles();
    _profTimer?.cancel();
    _profTimer = Timer.periodic(
        const Duration(seconds: 40), (_) => _refreshProfiles());
  }

  Timer? _profTimer;

  /// Recharge les contacts (photos de profil, nouveaux inscrits) en silence.
  Future<void> _refreshProfiles() async {
    try {
      await loadProfiles();
    } catch (_) {}
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
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    final sender = m['sender'].toString();
    if (activePeer == sender) return;
    final text = m['content']?.toString() ?? '';
    final media = m['media_url']?.toString() ?? '';
    final body = text.isNotEmpty
        ? text
        : (media.isEmpty
            ? 'Nouveau message'
            : mediaLabel(media));
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
      final fr = await _db
          .from('friendships')
          .select('requester, addressee, status')
          .timeout(const Duration(seconds: 6));
      final peers = <String>{};
      var pending = 0;
      for (final f in fr) {
        final other =
            (f['requester'] == uid ? f['addressee'] : f['requester']).toString();
        if (f['status'] == 'accepted') {
          peers.add(other);
        } else if (f['addressee'] == uid) {
          pending++;
        }
      }
      pendingCount.value = pending;
      final data = peers.isEmpty
          ? <dynamic>[]
          : await _db
              .from('profiles')
              .select('id, pseudo, avatar_url, last_seen')
              .inFilter('id', peers.toList())
              .order('pseudo')
              .timeout(const Duration(seconds: 6));
      profiles = List<Map<String, dynamic>>.from(data);
      LivePresence.I.setAvatars(profiles);
      if (uid != null) {
        try {
          final me = await _db
              .from('profiles')
              .select('id, avatar_url')
              .eq('id', uid)
              .maybeSingle();
          if (me != null) LivePresence.I.setAvatars([me]);
        } catch (_) {}
      }
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

  /// Bloque quelqu'un et le retire de mes amis.
  Future<void> blockUser(String id) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('blocks').insert({'blocked': id});
    try {
      final fr = await _db.from('friendships').select('id, requester, addressee');
      for (final f in fr) {
        final a = f['requester'].toString();
        final b = f['addressee'].toString();
        if ((a == uid && b == id) || (a == id && b == uid)) {
          await _db.from('friendships').delete().eq('id', f['id']);
        }
      }
    } catch (_) {}
    profiles = profiles.where((p) => p['id'].toString() != id).toList();
    _scheduleSave();
  }

  /// À la déconnexion : on arrête tout et on efface la copie locale.
  Future<void> stop() async {
    _retry?.cancel();
    _flushTimer?.cancel();
    outbox.value = [];
    try {
      final of = await _outboxFile();
      if (await of.exists()) await of.delete();
    } catch (_) {}
    _profTimer?.cancel();
    _saveTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _reactSub?.cancel();
    _reactSub = null;
    await _gmSub?.cancel();
    await _gmemSub?.cancel();
    await _grSub?.cancel();
    groupReactions.value = {};
    _knownG.clear();
    groups.value = [];
    groupMessages.value = [];
    reactions.value = {};
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
