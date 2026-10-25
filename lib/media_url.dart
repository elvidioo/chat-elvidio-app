import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'settings.dart';
import 'transfer.dart';

/// Fichiers du stockage Supabase : on demande un lien signé (temporaire)
/// au lieu d'utiliser un lien public permanent.
class MediaUrl {
  static const _marker = '/object/public/media/';
  static final Map<String, _Signed> _cache = {};

  static bool isManaged(String url) => url.contains(_marker);

  /// Lien signé déjà en mémoire (ou le lien tel quel s'il n'est pas géré).
  static String? cached(String url) {
    if (!isManaged(url)) return url;
    final c = _cache[url];
    if (c != null && c.expires.isAfter(DateTime.now())) return c.url;
    return null;
  }

  static Future<String> resolve(String url) async {
    final hit = cached(url);
    if (hit != null) return hit;
    final path = Uri.decodeComponent(url.split(_marker).last.split('?').first);
    try {
      final signed = await Supabase.instance.client.storage
          .from('media')
          .createSignedUrl(path, 3600);
      _cache[url] = _Signed(
        signed,
        DateTime.now().add(const Duration(minutes: 50)),
      );
      return signed;
    } catch (_) {
      return url; // secours : ancien lien public
    }
  }

  static void clear() => _cache.clear();
}

class _Signed {
  _Signed(this.url, this.expires);
  final String url;
  final DateTime expires;
}

/// Image du stockage : cache sur le téléphone (jamais retéléchargée), lien
/// signé, et chargement à la demande si l'économie de données est active.
class SignedImage extends StatefulWidget {
  const SignedImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.placeholderHeight = 140,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final double placeholderHeight;

  @override
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  File? _file;
  bool _loading = false;
  bool _failed = false;
  bool _checked = false;

  static Future<File> _cacheFile(String url) async {
    final dir = await getApplicationSupportDirectory();
    final cache = Directory('${dir.path}/img_cache');
    await cache.create(recursive: true);
    final key = url
        .split('/media/')
        .last
        .split('?')
        .first
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${cache.path}/$key');
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(SignedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _failed = false;
      _checked = false;
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final f = await _cacheFile(widget.url);
      if (await f.exists() && await f.length() > 0) {
        if (mounted) setState(() { _file = f; _checked = true; });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _checked = true);
    if (AppSettings.I.autoPhotos.value) _download();
  }

  Future<void> _download() async {
    if (_loading) return;
    setState(() { _loading = true; _failed = false; });
    try {
      final bytes = await downloadBytes(widget.url);
      final f = await _cacheFile(widget.url);
      await f.writeAsBytes(bytes);
      if (mounted) setState(() => _file = f);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height ?? widget.placeholderHeight;
    Widget box(Widget child) => SizedBox(
          width: widget.width,
          height: h,
          child: Center(child: child),
        );
    final f = _file;
    if (f != null) {
      return Image.file(
        f,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) =>
            box(const Icon(Icons.broken_image_outlined)),
      );
    }
    if (!_checked || _loading) {
      return box(const CircularProgressIndicator(strokeWidth: 2));
    }
    return InkWell(
      onTap: _download,
      child: box(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_failed ? Icons.refresh : Icons.download_for_offline_outlined,
              size: 32),
          const SizedBox(height: 4),
          Text(_failed ? 'Échec · réessayer' : 'Photo · toucher pour charger',
              style: const TextStyle(fontSize: 12)),
        ],
      )),
    );
  }
}
