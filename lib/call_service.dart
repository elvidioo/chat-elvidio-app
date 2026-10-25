import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repo.dart';
import 'screens/call_screen.dart';

enum CallState { idle, calling, ringing, connecting, connected }

/// Appels audio / vidéo (WebRTC). La signalisation passe par Supabase Realtime.
class CallService {
  CallService._();
  static final CallService I = CallService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // TURN gratuit « Open Relay » (Metered) en mode secret partagé public :
  // identifiants temporaires calculés ici (HMAC-SHA1, norme TURN REST).
  // Service tiers gratuit, sans garantie de disponibilité.
  static const _turnSecret = 'openrelayprojectsecret';

  List<dynamic>? _remoteIce;
  DateTime? _remoteIceAt;
  String turnSource = 'public';

  /// Serveurs TURN personnels (fonction « turn » + compte Metered) si configurés,
  /// sinon les serveurs publics gratuits.
  String _gather = '-';
  String _ice = '-';

  void _refreshDiag() {
    diag.value =
        'Relais: $turnSource · $_hostCands local, $_srflxCands public, $_relayCands relais · collecte $_gather · ICE $_ice';
  }

  Future<Map<String, dynamic>> _iceConfigAsync() async {
    final fresh = _remoteIceAt != null &&
        DateTime.now().difference(_remoteIceAt!).inMinutes < 10;
    if (!fresh) {
      try {
        final r = await _db.functions
            .invoke('turn')
            .timeout(const Duration(seconds: 4));
        final d = r.data;
        final list = d is Map ? d['iceServers'] : null;
        if (list is List && list.isNotEmpty) {
          _remoteIce = list;
          _remoteIceAt = DateTime.now();
        }
      } catch (_) {}
    }
    final remote = _remoteIce;
    if (remote != null && remote.isNotEmpty) {
      turnSource = 'metered';
      return {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          ...remote,
        ],
        'sdpSemantics': 'unified-plan',
      };
    }
    turnSource = 'public';
    return _iceConfig();
  }

  static Map<String, dynamic> _iceConfig() {
    final username =
        '${DateTime.now().toUtc().add(const Duration(hours: 12)).millisecondsSinceEpoch ~/ 1000}';
    final credential = base64.encode(
        Hmac(sha1, utf8.encode(_turnSecret)).convert(utf8.encode(username)).bytes);
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {
          'urls': [
            'turn:staticauth.openrelay.metered.ca:80',
            'turn:staticauth.openrelay.metered.ca:443',
            'turn:staticauth.openrelay.metered.ca:443?transport=tcp',
            'turns:staticauth.openrelay.metered.ca:443?transport=tcp',
          ],
          'username': username,
          'credential': credential,
        },
      ],
      'sdpSemantics': 'unified-plan',
    };
  }

  SupabaseClient get _db => Supabase.instance.client;

  final ValueNotifier<CallState> state = ValueNotifier(CallState.idle);
  final ValueNotifier<String> info = ValueNotifier('');
  final ValueNotifier<int> tick = ValueNotifier(0); // met à jour l'écran

  String? peerId;
  String peerName = '';
  String? _callId;
  bool video = false;
  bool incoming = false;
  bool muted = false;
  bool speaker = false;
  bool camOff = false;
  DateTime? connectedAt;

  RealtimeChannel? _mine;
  String? _mineUid;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  final List<RTCIceCandidate> _pending = [];
  bool _remoteSet = false;
  Timer? _ringTimer;
  Timer? _vibrate;
  bool _screenOpen = false;
  int _relayCands = 0, _srflxCands = 0, _hostCands = 0;
  final ValueNotifier<String> diag = ValueNotifier('');

  String get _uid => _db.auth.currentUser!.id;

  /// À appeler une fois connecté : écoute les signaux d'appel qui me sont
  /// destinés. La signalisation passe par une table (call_signals) suivie en
  /// temps réel, plus fiable que les canaux « broadcast ».
  void start() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    if (_mine != null && _mineUid == uid) return;
    stop();
    _mineUid = uid;
    final ch = _db.channel('call-signals:$uid');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'receiver',
        value: uid,
      ),
      callback: (change) {
        final r = change.newRecord;
        final payload = r['payload'];
        final data = <String, dynamic>{
          if (payload is Map) ...Map<String, dynamic>.from(payload),
          'type': r['type'],
          'from': r['sender'],
          'callId': r['call_id'],
        };
        _onSignal(data);
      },
    ).subscribe((status, [error]) {
      // Si la connexion temps réel tombe, on se réabonne (sinon plus d'appel reçu).
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        Future.delayed(const Duration(seconds: 4), () {
          if (_mine == ch && _mineUid == _db.auth.currentUser?.id) {
            _mine = null;
            _mineUid = null;
            try {
              _db.removeChannel(ch);
            } catch (_) {}
            start();
          }
        });
      }
    });
    _mine = ch;
  }

  void stop() {
    _endCall(notify: false, reason: '');
    final ch = _mine;
    _mine = null;
    _mineUid = null;
    if (ch != null) {
      try {
        _db.removeChannel(ch);
      } catch (_) {}
    }
  }

  Future<void> _send(String peer, Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    final callId = (data['callId'] ?? _callId)?.toString();
    if (type == null || callId == null) return;
    final payload = Map<String, dynamic>.from(data)
      ..remove('type')
      ..remove('callId');
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _db.from('call_signals').insert({
          'call_id': callId,
          'receiver': peer,
          'type': type,
          'payload': payload,
        });
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<bool> _permissions(bool withVideo) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (withVideo) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  Future<void> _prepare(bool withVideo) async {
    await _ensureRenderers();
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': withVideo ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = _local;
    final pc = await createPeerConnection(await _iceConfigAsync());
    _pc = pc;
    for (final t in _local!.getTracks()) {
      await pc.addTrack(t, _local!);
    }
    _relayCands = _srflxCands = _hostCands = 0;
    _gather = '-';
    _ice = '-';
    _refreshDiag();
    pc.onIceGatheringState = (s) {
      _gather = s.name.replaceFirst('RTCIceGatheringState', '');
      _refreshDiag();
    };
    pc.onIceConnectionState = (s) {
      _ice = s.name.replaceFirst('RTCIceConnectionState', '');
      _refreshDiag();
    };
    pc.onIceCandidate = (c) {
      final to = peerId;
      if (to == null || c.candidate == null) return;
      final cs = c.candidate!;
      if (cs.contains(' typ relay')) {
        _relayCands++;
      } else if (cs.contains(' typ srflx')) {
        _srflxCands++;
      } else {
        _hostCands++;
      }
      _refreshDiag();
      _send(to, {
        'type': 'candidate',
        'callId': _callId,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams[0];
        tick.value++;
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _ringTimer?.cancel();
        _stopVibrate();
        connectedAt ??= DateTime.now();
        state.value = CallState.connected;
        speaker = withVideo;
        Helper.setSpeakerphoneOn(speaker);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall(
            notify: true,
            reason: 'Connexion impossible (réseau). ${diag.value}');
      }
    };
  }

  void _openScreen() {
    if (_screenOpen) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _screenOpen = true;
    nav
        .push(MaterialPageRoute(builder: (_) => const CallScreen()))
        .then((_) => _screenOpen = false);
  }

  /// Appeler un ami.
  Future<void> startCall(String peer, String name, {required bool withVideo}) async {
    if (state.value != CallState.idle) return;
    if (!await _permissions(withVideo)) {
      info.value = 'Autorisation refusée (micro / caméra).';
      return;
    }
    peerId = peer;
    peerName = name;
    video = withVideo;
    incoming = false;
    _callId = DateTime.now().microsecondsSinceEpoch.toString();
    muted = false;
    camOff = false;
    connectedAt = null;
    info.value = 'Appel en cours…';
    state.value = CallState.calling;
    _openScreen();
    try {
      await _prepare(withVideo);
    } catch (_) {
      _endCall(notify: false, reason: 'Micro ou caméra indisponible.');
      return;
    }
    final invite = {
      'type': 'invite',
      'callId': _callId,
      'video': withVideo,
      'name': Repo.I.names[_uid] ?? '',
    };
    // 1) signal direct (rapide si l'autre a l'app ouverte)
    _send(peer, invite);
    // 2) ligne de message : arrive même si le signal direct est perdu, et
    //    déclenche la notification push quand l'app de l'autre est fermée.
    try {
      await _db.from('messages').insert({
        'sender': _uid,
        'receiver': peer,
        'content': withVideo
            ? '\u{1F4F9} Appel vidéo'
            : '\u{1F4DE} Appel vocal',
        'media_name': 'call:$_callId:${withVideo ? 'v' : 'a'}',
      });
    } catch (_) {}
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (state.value == CallState.calling) {
        _missed();
      }
    });
  }

  Future<void> _missed() async {
    final peer = peerId;
    if (peer != null) _send(peer, {'type': 'end', 'callId': _callId});
    _endCall(notify: false, reason: 'Pas de réponse.');
  }

  /// Décrocher un appel entrant.
  Future<void> accept() async {
    if (state.value != CallState.ringing) return;
    final peer = peerId;
    if (peer == null) return;
    _stopVibrate();
    _ringTimer?.cancel();
    if (!await _permissions(video)) {
      decline();
      return;
    }
    state.value = CallState.connecting;
    info.value = 'Connexion…';
    _armConnectTimeout();
    try {
      await _prepare(video);
    } catch (_) {
      _endCall(notify: true, reason: 'Micro ou caméra indisponible.');
      return;
    }
    await _send(peer, {'type': 'accept', 'callId': _callId});
  }

  void decline() {
    final peer = peerId;
    if (peer != null) _send(peer, {'type': 'reject', 'callId': _callId});
    _endCall(notify: false, reason: '');
  }

  void hangUp() {
    final peer = peerId;
    if (peer != null) _send(peer, {'type': 'end', 'callId': _callId});
    _endCall(notify: false, reason: '');
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    tick.value++;
  }

  void toggleSpeaker() {
    speaker = !speaker;
    Helper.setSpeakerphoneOn(speaker);
    tick.value++;
  }

  void toggleCamera() {
    camOff = !camOff;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !camOff;
    }
    tick.value++;
  }

  void switchCamera() {
    final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) Helper.switchCamera(tracks.first);
  }

  // ---- Signalisation reçue ----
  Future<void> _onSignal(Map<String, dynamic> d) async {
    final type = d['type']?.toString();
    final from = d['from']?.toString();
    if (from == null || type == null) return;

    if (type == 'invite') {
      final isFriend =
          Repo.I.profiles.any((p) => p['id'].toString() == from);
      if (!isFriend) return;
      _ring(from, d['callId']?.toString(), d['video'] == true,
          d['name']?.toString());
      return;
    }

    _afterInvite(type, from, d);
  }

  final Set<String> _handled = {};

  /// Invitation arrivée par une ligne de message (media_name = call:<id>:<v|a>).
  void onInviteMessage(Map<String, dynamic> m) {
    final tag = m['media_name']?.toString() ?? '';
    if (!tag.startsWith('call:')) return;
    final parts = tag.split(':');
    if (parts.length < 3) return;
    final created = DateTime.tryParse(m['created_at']?.toString() ?? '');
    if (created == null ||
        DateTime.now().difference(created.toLocal()).inSeconds > 40) {
      return;
    }
    _ring(m['sender'].toString(), parts[1], parts[2] == 'v', null);
  }

  void _ring(String from, String? callId, bool isVideo, String? name) {
    if (callId == null || !_handled.add(callId)) return; // déjà traité
    if (state.value != CallState.idle) {
      if (callId != _callId) {
        _send(from, {'type': 'reject', 'callId': callId});
      }
      return;
    }
    {
      peerId = from;
      peerName = Repo.I.names[from] ?? (name ?? 'Ami');
      video = isVideo;
      incoming = true;
      _callId = callId;
      muted = false;
      camOff = false;
      connectedAt = null;
      info.value = video ? 'Appel vidéo entrant' : 'Appel vocal entrant';
      state.value = CallState.ringing;
      _startVibrate();
      _openScreen();
      _ringTimer = Timer(const Duration(seconds: 45), () {
        if (state.value == CallState.ringing) {
          _endCall(notify: false, reason: '');
        }
      });
    }
  }

  Future<void> _afterInvite(
      String type, String from, Map<String, dynamic> d) async {
    if (from != peerId || d['callId']?.toString() != _callId) return;

    switch (type) {
      case 'accept':
        final pc = _pc;
        if (pc == null) return;
        _armConnectTimeout();
        state.value = CallState.connecting;
        info.value = 'Connexion…';
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _send(from, {
          'type': 'offer',
          'callId': _callId,
          'sdp': offer.sdp,
          'sdpType': offer.type,
        });
        break;
      case 'offer':
        final pc = _pc;
        if (pc == null) return;
        await pc.setRemoteDescription(
            RTCSessionDescription(d['sdp']?.toString(), d['sdpType']?.toString()));
        _remoteSet = true;
        await _flushCandidates();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _send(from, {
          'type': 'answer',
          'callId': _callId,
          'sdp': answer.sdp,
          'sdpType': answer.type,
        });
        break;
      case 'answer':
        final pc = _pc;
        if (pc == null) return;
        await pc.setRemoteDescription(
            RTCSessionDescription(d['sdp']?.toString(), d['sdpType']?.toString()));
        _remoteSet = true;
        await _flushCandidates();
        break;
      case 'candidate':
        final c = RTCIceCandidate(
          d['candidate']?.toString(),
          d['sdpMid']?.toString(),
          (d['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteSet && _pc != null) {
          await _pc!.addCandidate(c);
        } else {
          _pending.add(c);
        }
        break;
      case 'reject':
        _endCall(notify: true, reason: 'Appel refusé.');
        break;
      case 'end':
        _endCall(notify: true, reason: 'Appel terminé.');
        break;
    }
  }

  Future<void> _flushCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _pending.clear();
  }

  void _armConnectTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 30), () {
      if (state.value == CallState.connecting) {
        final peer = peerId;
        if (peer != null) _send(peer, {'type': 'end', 'callId': _callId});
        final why = _relayCands == 0
            ? 'aucun serveur relais joignable'
            : 'relais disponible mais aucun chemin trouvé';
        _endCall(
            notify: false,
            reason: 'Connexion impossible ($why). ${diag.value}');
      }
    });
  }

  void _startVibrate() {
    _vibrate?.cancel();
    _vibrate = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.vibrate();
    });
  }

  void _stopVibrate() {
    _vibrate?.cancel();
    _vibrate = null;
  }

  void _endCall({required bool notify, required String reason}) {
    _ringTimer?.cancel();
    _stopVibrate();
    try {
      for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
        t.stop();
      }
      _local?.dispose();
    } catch (_) {}
    _local = null;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    _pending.clear();
    _remoteSet = false;
    peerId = null;
    _callId = null;
    connectedAt = null;
    info.value = reason;
    state.value = CallState.idle;
    tick.value++;
    if (_screenOpen) {
      navigatorKey.currentState?.maybePop();
    }
  }
}
