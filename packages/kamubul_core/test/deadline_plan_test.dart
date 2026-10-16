import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

void main() {
  ListingRecord record({
    DateTime? deadline,
    bool saved = true,
    Map<String, Object?>? data,
  }) => ListingRecord(
    url: 'https://www.ilan.gov.tr/ilan/test',
    sourceId: 'ilangov',
    title: 'Test ilanı',
    category: 'personel',
    publishedAt: null,
    fetchedAt: DateTime.utc(2026, 10, 16),
    deadline: deadline,
    saved: saved,
    criteriaListing: data,
  );
  test('Türkiye takviminde üç gün önce09; yıl geçişi UTC instant', () {
    final expiry = DateTime.utc(2027, 1, 1, 20, 59);
    final plan = deadlineReminderPlan(
      record: record(deadline: expiry),
      now: DateTime.utc(2026, 12, 20),
    );
    expect(plan?.at, DateTime.utc(2026, 12, 29, 6));
    expect(plan?.at.isUtc, isTrue);
    expect(plan?.expiresAt, expiry);
    // UTC önceki gün, Türkiye takviminde1Ocak: slot29Aralık.
    expect(
      deadlineReminderPlan(
        record: record(deadline: DateTime.utc(2026, 12, 31, 21, 30)),
        now: DateTime.utc(2026, 12, 20),
      )?.at,
      DateTime.utc(2026, 12, 29, 6),
    );
  });
  test(
    'geçmiş slot yakın geleceğe taşınır; sessiz22–08 saatlerinde gönderilmez',
    () {
      final item = record(deadline: DateTime.utc(2026, 10, 20, 20, 59));
      DateTime? at(DateTime now) =>
          deadlineReminderPlan(record: item, now: now)?.at;
      expect(
        at(DateTime.utc(2026, 10, 18, 9)),
        DateTime.utc(2026, 10, 18, 9, 1),
      );
      expect(at(DateTime.utc(2026, 10, 18, 19)), DateTime.utc(2026, 10, 19, 5));
      expect(at(DateTime.utc(2026, 10, 18, 3)), DateTime.utc(2026, 10, 18, 5));
      expect(
        at(DateTime.utc(2026, 10, 18, 18, 59, 30)),
        DateTime.utc(2026, 10, 19, 5),
      );
    },
  );
  test(
    'expiry sonrasında veya sessiz saatten çıkmadan biten ilan planlanmaz',
    () {
      final expiry = DateTime.utc(2026, 10, 18, 20, 59);
      final item = record(deadline: expiry);
      expect(deadlineReminderPlan(record: item, now: expiry), isNull);
      expect(
        deadlineReminderPlan(
          record: item,
          now: expiry.add(const Duration(seconds: 1)),
        ),
        isNull,
      );
      expect(
        deadlineReminderPlan(record: item, now: DateTime.utc(2026, 10, 18, 19)),
        isNull,
      );
    },
  );
  test(
    'kaydedilmeyen, iptal, belirsiz çoklu takvim ve yalnız tahmin planlanmaz',
    () {
      final now = DateTime.utc(2026, 10, 16);
      final expiry = DateTime.utc(2026, 10, 25, 20, 59);
      for (final item in [
        record(deadline: expiry, saved: false),
        record(deadline: expiry, data: {'active': false}),
        record(
          deadline: expiry,
          data: {
            'extraction': {'kind': 'cancellation'},
          },
        ),
        record(
          deadline: expiry,
          data: {
            'applicationPeriods': [
              {'text': 'Kadrolara göre değişir'},
            ],
          },
        ),
        record(deadline: expiry, data: {'applicationPeriods': 'geçersiz'}),
        record(data: {'deadlineEstimate': '2026-10-25'}),
      ]) {
        expect(deadlineReminderPlan(record: item, now: now), isNull);
      }
      expect(
        deadlineReminderPlan(
          record: record(deadline: expiry, data: {'applicationPeriods': []}),
          now: now,
        ),
        isNotNull,
      );
    },
  );
}
