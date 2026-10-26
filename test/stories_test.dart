import 'package:chat_elvidio_app/stories.dart';
import 'package:flutter_test/flutter_test.dart';

Story _s(int id) => Story({
      'id': id,
      'author': 'a',
      'content': 'x',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

void main() {
  test('StoryGroup compte les stories non vues', () {
    final g = StoryGroup('a', [_s(1), _s(2), _s(3)], {1});
    expect(g.unseen, 2);
    expect(g.allSeen, isFalse);
    expect(g.firstUnseenIndex, 1);
  });

  test('tout vu : on repart du début', () {
    final g = StoryGroup('a', [_s(1), _s(2)], {1, 2});
    expect(g.allSeen, isTrue);
    expect(g.firstUnseenIndex, 0);
  });

  test('agoText', () {
    expect(agoText(null), '');
    expect(agoText(DateTime.now()), 'à l\'instant');
    expect(agoText(DateTime.now().subtract(const Duration(minutes: 5))), '5 min');
    expect(agoText(DateTime.now().subtract(const Duration(hours: 3))), '3 h');
    expect(agoText(DateTime.now().subtract(const Duration(days: 2))), '2 j');
  });
}
