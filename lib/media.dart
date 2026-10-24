import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'theme.dart';
import 'widgets.dart' show isVideoUrl;

const _imageExt = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'];
const _audioExt = ['m4a', 'aac', 'mp3', 'ogg', 'wav'];

String _ext(String url) {
  final clean = url.split('?').first.toLowerCase();
  final i = clean.lastIndexOf('.');
  return i < 0 ? '' : clean.substring(i + 1);
}

bool isImageUrl(String url) => _imageExt.contains(_ext(url));
bool isAudioUrl(String url) => _audioExt.contains(_ext(url));

String fileNameOf(String url, String? name) {
  if (name != null && name.isNotEmpty) return name;
  final clean = Uri.decodeComponent(url.split('?').first);
  final base = clean.split('/').last;
  final m = RegExp(r'^\d{10,}_(.*)$').firstMatch(base);
  return m?.group(1) ?? base;
}

/// Étiquette courte d'un fichier (aperçus et notifications).
String mediaLabel(String url) {
  if (isVideoUrl(url)) return '\u{1F3A5} Vidéo';
  if (isAudioUrl(url)) return '\u{1F3A4} Message vocal';
  if (isImageUrl(url)) return '\u{1F4F7} Photo';
  return '\u{1F4CE} Document';
}

Future<List<int>> downloadBytes(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    return out;
  } finally {
    client.close();
  }
}

/// Télécharge et laisse choisir où l'enregistrer sur le téléphone.
Future<bool> saveToPhone(String url, String name) async {
  final bytes = await downloadBytes(url);
  final tmp = await getTemporaryDirectory();
  final f = File('${tmp.path}/$name');
  await f.writeAsBytes(bytes);
  final saved = await FlutterFileDialog.saveFile(
    params: SaveFileDialogParams(sourceFilePath: f.path, fileName: name),
  );
  return saved != null;
}

/// Télécharge dans un dossier temporaire et ouvre avec une autre app.
Future<void> openRemoteFile(String url, String name) async {
  final bytes = await downloadBytes(url);
  final tmp = await getTemporaryDirectory();
  final f = File('${tmp.path}/$name');
  await f.writeAsBytes(bytes);
  await OpenFilex.open(f.path);
}

String formatDuration(Duration d) {
  final m = d.inMinutes.toString().padLeft(1, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Lecteur de message vocal.
class AudioBubble extends StatefulWidget {
  const AudioBubble({super.key, required this.url, required this.mine});

  final String url;
  final bool mine;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  VideoPlayerController? _c;
  bool _failed = false;

  Future<void> _toggle() async {
    try {
      var c = _c;
      if (c == null) {
        c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        _c = c;
        c.addListener(() {
          if (mounted) setState(() {});
        });
        await c.initialize();
        await c.play();
        return;
      }
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
        await c.play();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final v = c?.value;
    final playing = v?.isPlaying ?? false;
    final total = v?.duration ?? Duration.zero;
    final pos = v?.position ?? Duration.zero;
    final color = widget.mine ? Colors.white : AppColors.primary;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              _failed
                  ? Icons.error_outline
                  : (playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
              color: color,
              size: 36,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  color: color,
                  backgroundColor: color.withOpacity(0.3),
                ),
                const SizedBox(height: 4),
                Text(
                  c == null
                      ? 'Message vocal'
                      : '${formatDuration(pos)} / ${formatDuration(total)}',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Document partagé : nom, toucher pour ouvrir.
class FileBubble extends StatelessWidget {
  const FileBubble({
    super.key,
    required this.name,
    required this.mine,
    required this.onTap,
  });

  final String name;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mine ? Colors.white : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 210,
        child: Row(
          children: [
            Icon(Icons.insert_drive_file, color: color, size: 34),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
