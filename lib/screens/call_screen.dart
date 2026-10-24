import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../call_service.dart';
import '../media.dart';
import '../widgets.dart';

/// Écran d'appel (sortant ou entrant).
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final c = CallService.I;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _status() {
    switch (c.state.value) {
      case CallState.calling:
        return 'Appel en cours…';
      case CallState.ringing:
        return c.video ? 'Appel vidéo entrant' : 'Appel vocal entrant';
      case CallState.connecting:
        return 'Connexion…';
      case CallState.connected:
        final t = c.connectedAt;
        return t == null ? 'En cours' : formatDuration(DateTime.now().difference(t));
      case CallState.idle:
        return c.info.value;
    }
  }

  Widget _btn(IconData icon, VoidCallback onTap,
      {Color bg = Colors.white24, Color fg = Colors.white, String? label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onTap,
          child: CircleAvatar(
            radius: 30,
            backgroundColor: bg,
            child: Icon(icon, color: fg, size: 30),
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: c.state.value == CallState.idle,
      child: Scaffold(
        backgroundColor: const Color(0xFF111418),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([c.state, c.tick, c.info]),
            builder: (context, _) {
              final connected = c.state.value == CallState.connected;
              final showVideo = c.video && connected;
              return Stack(
                children: [
                  if (showVideo)
                    Positioned.fill(
                      child: RTCVideoView(
                        c.remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  if (c.video && !c.camOff)
                    Positioned(
                      right: 16,
                      top: 16,
                      width: 110,
                      height: 150,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: RTCVideoView(
                          c.localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      const SizedBox(height: 60),
                      if (!showVideo) ...[
                        const SizedBox(height: 40),
                        Center(
                          child: Avatar(
                            name: c.peerName,
                            size: 130,
                            userId: c.peerId,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          c.peerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          _status(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: c.state.value == CallState.ringing
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _btn(Icons.call_end, c.decline,
                                      bg: Colors.redAccent, label: 'Refuser'),
                                  _btn(c.video ? Icons.videocam : Icons.call,
                                      c.accept,
                                      bg: Colors.green, label: 'Répondre'),
                                ],
                              )
                            : Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 22,
                                runSpacing: 16,
                                children: [
                                  _btn(c.muted ? Icons.mic_off : Icons.mic,
                                      c.toggleMute,
                                      bg: c.muted ? Colors.white : Colors.white24,
                                      fg: c.muted ? Colors.black : Colors.white,
                                      label: 'Micro'),
                                  _btn(
                                      c.speaker
                                          ? Icons.volume_up
                                          : Icons.volume_down,
                                      c.toggleSpeaker,
                                      bg: c.speaker ? Colors.white : Colors.white24,
                                      fg: c.speaker ? Colors.black : Colors.white,
                                      label: 'Haut-parleur'),
                                  if (c.video) ...[
                                    _btn(
                                        c.camOff
                                            ? Icons.videocam_off
                                            : Icons.videocam,
                                        c.toggleCamera,
                                        bg: c.camOff
                                            ? Colors.white
                                            : Colors.white24,
                                        fg: c.camOff
                                            ? Colors.black
                                            : Colors.white,
                                        label: 'Caméra'),
                                    _btn(Icons.cameraswitch, c.switchCamera,
                                        label: 'Retourner'),
                                  ],
                                  _btn(Icons.call_end, c.hangUp,
                                      bg: Colors.redAccent, label: 'Raccrocher'),
                                ],
                              ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
