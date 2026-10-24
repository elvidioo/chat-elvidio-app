import 'dart:convert';

/// Paquet texte du « Elvidio Relay » (mode proche).
///
/// Limites honnêtes : les paquets ne sont PAS chiffrés de bout en bout et
/// l'expéditeur n'est pas authentifié (n'importe quel téléphone proche peut
/// écrire un faux nom). Le relais est « au mieux » : aucune garantie de
/// livraison à un téléphone hors de portée.
class RelayPacket {
  static const maxTextLength = 2000;
  static const maxHops = 6;
  static const maxAge = Duration(hours: 24);

  final String id;
  final String from;
  final String text;
  final int createdMs;
  final int hops;

  const RelayPacket({
    required this.id,
    required this.from,
    required this.text,
    required this.createdMs,
    this.hops = 0,
  });

  RelayPacket nextHop() => RelayPacket(
      id: id, from: from, text: text, createdMs: createdMs, hops: hops + 1);

  bool isExpired(int nowMs) => nowMs - createdMs > maxAge.inMilliseconds;

  Map<String, dynamic> toJson() => {
        'v': 2,
        'id': id,
        'from': from,
        'text': text,
        'ts': createdMs,
        'hops': hops,
      };

  List<int> encode() => utf8.encode(jsonEncode(toJson()));

  /// Retourne null si le paquet est invalide (taille, champs manquants).
  static RelayPacket? decode(String raw) {
    if (raw.length > 8000) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final id = j['id']?.toString();
      final from = j['from']?.toString();
      final text = j['text']?.toString();
      if (id == null || id.isEmpty || id.length > 80) return null;
      if (from == null || from.isEmpty || from.length > 60) return null;
      if (text == null || text.isEmpty || text.length > maxTextLength) {
        return null;
      }
      final ts = j['ts'] is int ? j['ts'] as int : 0;
      final hops = j['hops'] is int ? j['hops'] as int : 0;
      if (hops < 0 || hops > maxHops) return null;
      return RelayPacket(
          id: id, from: from, text: text, createdMs: ts, hops: hops);
    } catch (_) {
      return null;
    }
  }
}

/// Mémoire d'identifiants déjà vus (anti-doublon / anti-boucle), bornée.
class SeenIds {
  SeenIds({this.capacity = 2000});
  final int capacity;
  final _ids = <String>{}; // ordre d'insertion conservé

  bool get isEmpty => _ids.isEmpty;
  bool contains(String id) => _ids.contains(id);

  /// true si l'id est nouveau.
  bool add(String id) {
    if (!_ids.add(id)) return false;
    if (_ids.length > capacity) _ids.remove(_ids.first);
    return true;
  }
}

/// Limite de débit par voisin (fenêtre glissante) contre le spam.
class RateLimiter {
  RateLimiter({this.maxPerWindow = 20, this.window = const Duration(seconds: 10)});
  final int maxPerWindow;
  final Duration window;
  final _hits = <String, List<int>>{};

  bool allow(String key, int nowMs) {
    final list = _hits.putIfAbsent(key, () => <int>[]);
    list.removeWhere((t) => nowMs - t > window.inMilliseconds);
    if (list.length >= maxPerWindow) return false;
    list.add(nowMs);
    return true;
  }
}

/// Décide quoi faire d'un paquet reçu.
enum RelayDecision { accept, duplicate, invalid, expired, rateLimited }

class RelayEngine {
  RelayEngine({SeenIds? seen, RateLimiter? limiter})
      : seen = seen ?? SeenIds(),
        limiter = limiter ?? RateLimiter();
  final SeenIds seen;
  final RateLimiter limiter;

  /// Texte brut reçu d'un voisin [from]. Si accepté, [out] contient le paquet.
  RelayDecision receive(String from, String raw, int nowMs,
      {void Function(RelayPacket p)? onAccept}) {
    if (!limiter.allow(from, nowMs)) return RelayDecision.rateLimited;
    final p = RelayPacket.decode(raw);
    if (p == null) return RelayDecision.invalid;
    if (p.isExpired(nowMs)) return RelayDecision.expired;
    if (!seen.add(p.id)) return RelayDecision.duplicate;
    onAccept?.call(p);
    return RelayDecision.accept;
  }

  /// Un paquet doit-il encore être relayé ?
  bool shouldForward(RelayPacket p, int nowMs) =>
      p.hops < RelayPacket.maxHops && !p.isExpired(nowMs);
}
