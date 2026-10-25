import 'package:chat_elvidio_app/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = AppSettings.I;

  test('qualité photo : paramètres selon le réglage', () {
    s.photoQuality.value = 'low';
    expect(s.photoParams, (960.0, 45));
    s.photoQuality.value = 'normal';
    expect(s.photoParams, (1280.0, 70));
    s.photoQuality.value = 'high';
    expect(s.photoParams, (1920.0, 90));
  });

  test('hideMessages cache plusieurs messages', () {
    s.hidden.value = {};
    s.hideMessages(['m:1', 'm:2']);
    expect(s.hidden.value, {'m:1', 'm:2'});
    s.hideMessages(['m:2', 'm:3']);
    expect(s.hidden.value.length, 3);
  });

  test('masquer le statut est mémorisé en mémoire', () {
    s.setHideStatus(true);
    expect(s.hideStatus.value, isTrue);
    s.setHideStatus(false);
    expect(s.hideStatus.value, isFalse);
  });

  test('épingler puis désépingler', () {
    s.pinned.value = {};
    s.togglePin('u:a');
    expect(s.pinned.value.contains('u:a'), isTrue);
    s.togglePin('u:a');
    expect(s.pinned.value.contains('u:a'), isFalse);
  });
}
