import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ui/premium.dart';

void main() {
  test('deadline labels count calendar dates and preserve exact expiry', () {
    final now = DateTime(2026, 10, 2, 23, 30);
    expect(countdownLabel(null, now), isNull);
    expect(countdownLabel(DateTime(2026, 10, 3, 0, 30), now), 'Son 1 gün');
    expect(
      countdownLabel(
        DateTime(2026, 10, 3, 23, 59),
        DateTime(2026, 10, 2, 23, 59, 30),
      ),
      'Son 1 gün',
    );
    expect(countdownLabel(DateTime(2026, 10, 5, 8), now), 'Son 3 gün');
    expect(countdownLabel(DateTime(2026, 10, 2, 23, 59), now), 'Bugün son gün');
    expect(countdownLabel(DateTime(2026, 10, 2, 13), now), 'Süre doldu');
    expect(countdownLabel(now, now), 'Süre doldu');
    expect(countdownLabel(DateTime(2026, 10, 1, 23, 59), now), 'Süre doldu');
    expect(
      countdownLabel(DateTime(2026, 10, 3, 0, 30).toUtc(), now.toUtc()),
      'Son 1 gün',
    );
  });
}
