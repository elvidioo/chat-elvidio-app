import 'dart:async';

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

  static const _ice = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

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
  final Map<String, Future<RealtimeChannel>> _out = {};
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

  String get _uid => _db.auth.currentUser!.id;

  /// À appeler une fois connecté : écoute les appels entrants.
  void start() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    if (_mine != null && _mineUid == uid) return;
    stop();
    _mineUid = uid;
    final ch = _db.channel('calls:$uid');
    ch.onBroadcast(event: 'signal', callback: (p) {
      final data = p['payload'] is Map ? p['payload'] as Map : p;
      _onSignal(Map<String, dynamic>.from(data));
    }).subscribe();
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
    for (final f in _out.values) {
      f.then((c) {
        try {
          _db.removeChannel(c);
        } catch (_) {}
      }, onError: (_) {});
    }
    _out.clear();
  }

  Future<RealtimeChannel> _channelTo(String peer) {
    return _out[peer] ??= () async {
      final c = Completer<void>();
      final ch = _db.channel('calls:$peer');
      ch.subscribe((s, [e]) {
        if (s == RealtimeSubscribeStatus.subscribed && !c.isCompleted) {
          c.complete();
        }
      });
      await c.future.timeout(const Duration(seconds: 10));
      return ch;
    }();
  }

  Future<void> _send(String peer, Map<String, dynamic> data) async {
    try {
      final ch = await _channelTo(peer);
      await ch.sendBroadcastMessage(
        event: 'signal',
        payload: {...data, 'from': _uid},
      );
    } catch (_) {
      _out.remove(peer);
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
    final pc = await createPeerConnection(_ice);
    _pc = pc;
    for (final t in _local!.getTracks()) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (c) {
      final to = peerId;
      if (to == null || c.candidate == null) return;
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
        _endCall(notify: true, reason: 'Connexion impossible (réseau).');
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
    await _send(peer, {
      'type': 'invite',
      'callId': _callId,
      'video': withVideo,
      'name': Repo.I.names[_uid] ?? '',
    });
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (state.value == CallState.calling) {
        _missed();
      }
    });
  }

  Future<void> _missed() async {
    final peer = peerId;
    if (peer != null) {
      _send(peer, {'type': 'end', 'callId': _callId});
      try {
        await _db.from('messages').insert({
          'sender': _uid,
          'receiver': peer,
          'content': video ? '\u{1F4F9} Appel vidéo manqué' : '\u{1F4DE} Appel vocal manqué',
        });
      } catch (_) {}
    }
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
      if (state.value != CallState.idle) {
        _send(from, {'type': 'reject', 'callId': d['callId']});
        return;
      }
      peerId = from;
      peerName = Repo.I.names[from] ?? (d['name']?.toString() ?? 'Ami');
      video = d['video'] == true;
      incoming = true;
      _callId = d['callId']?.toString();
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
      return;
    }

    if (from != peerId || d['callId']?.toString() != _callId) return;

    switch (type) {
      case 'accept':
        final pc = _pc;
        if (pc == null) return;
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
