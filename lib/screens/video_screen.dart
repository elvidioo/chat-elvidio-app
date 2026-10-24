import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media_url.dart';

/// Lecteur vidéo dans l'app (plus d'ouverture du navigateur).
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.url});

  final String url;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _c;
  VideoPlayerController get controller => _c!;
  bool ready = false;
  String? error;

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final real = await MediaUrl.resolve(widget.url);
      final c = VideoPlayerController.networkUrl(Uri.parse(real));
      _c = c;
      c.addListener(_refresh);
      await c.initialize();
      if (!mounted) return;
      setState(() => ready = true);
      c.play();
    } catch (_) {
      if (mounted) setState(() => error = 'Impossible de lire cette vidéo.');
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_refresh);
    _c?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final value = _c?.value ?? VideoPlayerValue.uninitialized();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: error != null
            ? Text(error!, style: const TextStyle(color: Colors.white))
            : !ready
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () =>
                            value.isPlaying ? controller.pause() : controller.play(),
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      const SizedBox(height: 12),
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 40,
                            color: Colors.white,
                            icon: Icon(value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled),
                            onPressed: () => value.isPlaying
                                ? controller.pause()
                                : controller.play(),
                          ),
                          Text(
                            '${_fmt(value.position)} / ${_fmt(value.duration)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
