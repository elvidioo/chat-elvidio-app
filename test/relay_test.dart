import 'package:flutter_test/flutter_test.dart';
import 'package:chat_elvidio_app/relay.dart';

void main() {
  final now = DateTime(2026, 10, 25).millisecondsSinceEpoch;
  String raw(String id, {String text = 'salut', int? ts, int hops = 0}) =>
      String.fromCharCodes(RelayPacket(
              id: id, from: 'A#1', text: text, createdMs: ts ?? now, hops: hops)
          .encode());

  test('un paquet valide est accepté puis vu comme doublon', () {
    final e = RelayEngine();
    expect(e.receive('x', raw('1'), now), RelayDecision.accept);
    expect(e.receive('y', raw('1'), now), RelayDecision.duplicate);
  });

  test('paquet invalide ou trop long refusé', () {
    final e = RelayEngine();
    expect(e.receive('x', 'pas du json', now), RelayDecision.invalid);
    expect(e.receive('x', raw('2', text: 'a' * 2001), now),
        RelayDecision.invalid);
  });

  test('paquet expiré refusé', () {
    final e = RelayEngine();
    final old = now - const Duration(hours: 25).inMilliseconds;
    expect(e.receive('x', raw('3', ts: old), now), RelayDecision.expired);
  });

  test('limite de débit par voisin', () {
    final e = RelayEngine(limiter: RateLimiter(maxPerWindow: 3));
    for (var i = 0; i < 3; i++) {
      expect(e.receive('x', raw('r$i'), now), RelayDecision.accept);
    }
    expect(e.receive('x', raw('r9'), now), RelayDecision.rateLimited);
    expect(e.receive('autre', raw('r10'), now), RelayDecision.accept);
  });

  test('anti-boucle : nombre de sauts limité', () {
    final e = RelayEngine();
    final p = RelayPacket(id: 'h', from: 'A', text: 't', createdMs: now);
    expect(e.shouldForward(p, now), isTrue);
    var q = p;
    for (var i = 0; i < RelayPacket.maxHops; i++) {
      q = q.nextHop();
    }
    expect(e.shouldForward(q, now), isFalse);
  });

  test('mémoire des ids bornée', () {
    final s = SeenIds(capacity: 2);
    s.add('a');
    s.add('b');
    s.add('c');
    expect(s.contains('a'), isFalse);
    expect(s.contains('c'), isTrue);
  });
}
