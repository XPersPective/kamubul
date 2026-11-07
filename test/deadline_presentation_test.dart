import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ui/premium.dart';

void main() {
  DateTime turkey(int day, int hour, [int minute = 0, int second = 0]) =>
      DateTime.utc(2026, 10, day, hour - 3, minute, second);
  test('deadline labels count calendar dates and preserve exact expiry', () {
    final now = turkey(2, 23, 30);
    expect(countdownLabel(null, now), isNull);
    expect(countdownLabel(turkey(3, 0, 30), now), 'Son 1 gün');
    expect(
      countdownLabel(turkey(3, 23, 59), turkey(2, 23, 59, 30)),
      'Son 1 gün',
    );
    expect(countdownLabel(turkey(5, 8), now), 'Son 3 gün');
    expect(countdownLabel(turkey(2, 23, 59), now), 'Bugün son gün');
    expect(countdownLabel(turkey(2, 13), now), 'Süre doldu');
    expect(countdownLabel(now, now), 'Süre doldu');
    expect(countdownLabel(turkey(1, 23, 59), now), 'Süre doldu');
    expect(
      countdownLabel(turkey(3, 0, 30).toLocal(), now.toLocal()),
      'Son 1 gün',
    );
  });
  test(
    'canonical Turkish midnight is ten calendar days away on every host',
    () {
      expect(
        countdownLabel(
          DateTime.parse('2026-10-12T00:00:00+03:00'),
          DateTime.parse('2026-10-02T12:00:00+03:00'),
        ),
        'Son 10 gün',
      );
    },
  );
}
