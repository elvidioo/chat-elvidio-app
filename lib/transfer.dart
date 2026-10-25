import 'dart:io';

import 'media_url.dart';
import 'settings.dart';

/// Télécharge un fichier avec reprise : si la connexion coupe, on redemande
/// seulement la suite (en-tête Range) jusqu'à 4 essais.
Future<List<int>> downloadBytes(String url) async {
  final real = await MediaUrl.resolve(url);
  final out = <int>[];
  Object? lastError;
  int? total;
  for (var attempt = 0; attempt < 4; attempt++) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(real));
      if (out.isNotEmpty) req.headers.set('Range', 'bytes=${out.length}-');
      final res = await req.close();
      if (res.statusCode == 200) {
        out.clear(); // le serveur renvoie tout depuis le début
      } else if (res.statusCode != 206) {
        throw HttpException('http ${res.statusCode}');
      }
      total ??= res.contentLength > 0 ? res.contentLength : null;
      await for (final chunk in res) {
        out.addAll(chunk);
      }
      if (total == null || out.length >= total) {
        AppSettings.I.addMediaBytes(out.length);
        return out;
      }
    } catch (e) {
      lastError = e;
    } finally {
      client.close();
    }
    await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
  }
  throw lastError ?? Exception('téléchargement incomplet');
}
