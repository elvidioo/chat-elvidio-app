import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';

/// Écrire une publication ou un statut (visible 24 h).
class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key, this.status = false});

  final bool status;

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final _db = Supabase.instance.client;
  final _text = TextEditingController();
  XFile? _file;
  bool _video = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(bool video) async {
    final picker = ImagePicker();
    final f = video
        ? await picker.pickVideo(
            source: ImageSource.gallery, maxDuration: const Duration(minutes: 2))
        : await picker.pickImage(
            source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
    if (f != null) {
      setState(() {
        _file = f;
        _video = video;
      });
    }
  }

  Future<void> _publish() async {
    final text = _text.text.trim();
    if (text.isEmpty && _file == null) {
      setState(() => _error = 'Écris quelque chose ou ajoute une photo.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final uid = _db.auth.currentUser!.id;
      String? url;
      String? name;
      final f = _file;
      if (f != null) {
        final bytes = await f.readAsBytes();
        if (bytes.length > 50 * 1024 * 1024) {
          setState(() {
            _sending = false;
            _error = 'Fichier trop lourd (50 Mo maximum).';
          });
          return;
        }
        final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
        await _db.storage.from('media').uploadBinary(
              path,
              Uint8List.fromList(bytes),
              fileOptions: FileOptions(contentType: f.mimeType),
            );
        url = _db.storage.from('media').getPublicUrl(path);
        name = f.name;
      }
      await _db.from('posts').insert({
        'content': text.isEmpty ? null : text,
        'media_url': url,
        'media_name': name,
        'kind': widget.status ? 'status' : 'post',
        if (widget.status)
          'expires_at':
              DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Publication impossible : $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.status ? 'Nouveau statut' : 'Nouvelle publication'),
        actions: [
          TextButton(
            onPressed: _sending ? null : _publish,
            child: const Text('Publier'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_sending) const LinearProgressIndicator(),
          if (widget.status)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Ton statut sera visible par tes amis pendant 24 heures.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: widget.status ? 'Ton statut…' : 'Quoi de neuf ?',
            ),
          ),
          const SizedBox(height: 12),
          if (_file != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(_video ? Icons.videocam : Icons.photo,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_file!.name, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _file = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _sending ? null : () => _pick(false),
                icon: const Icon(Icons.photo_library),
                label: const Text('Photo'),
              ),
              TextButton.icon(
                onPressed: _sending ? null : () => _pick(true),
                icon: const Icon(Icons.videocam),
                label: const Text('Vidéo'),
              ),
            ],
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
        ],
      ),
    );
  }
}
