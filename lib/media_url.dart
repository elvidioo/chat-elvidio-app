import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Image du stockage avec lien signé, indicateur de chargement et erreur.
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
  late Future<String> _future = MediaUrl.resolve(widget.url);

  @override
  void didUpdateWidget(SignedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _future = MediaUrl.resolve(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final box = (Widget child) => SizedBox(
          width: widget.width,
          height: widget.height ?? widget.placeholderHeight,
          child: Center(child: child),
        );
    Widget image(String u) => Image.network(
          u,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : box(const CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, __, ___) =>
              box(const Icon(Icons.broken_image_outlined)),
        );
    final now = MediaUrl.cached(widget.url);
    if (now != null) return image(now);
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) => snap.hasData
          ? image(snap.data!)
          : box(const CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
