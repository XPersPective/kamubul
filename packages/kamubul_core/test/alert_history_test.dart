import 'package:test/test.dart';
import 'package:kamubul_core/notifications/alert_history.dart';

void main() {
  AlertRecord record(String id, {AlertDelivery delivery = AlertDelivery.held}) =>
      AlertRecord(
        id: id,
        kind: AlertKind.instant,
        searchName: 'Ankara P3',
        title: 'Ankara P3',
        body: 'TEST KURUMU ilanı',
        listingUrl: 'https://kariyerkapisi.gov.tr/IlanDetay?i=x',
        createdAt: DateTime(2026, 9, 27, 23),
        delivery: delivery,
      );

  test('JSON gidiş dönüşü alanları korur, bozuk JSON boş okunur', () {
    final encoded = encodeAlerts([record('a'), record('b')]);
    final decoded = decodeAlerts(encoded);
    expect(decoded, hasLength(2));
    expect(decoded.first.id, 'a');
    expect(decoded.first.kind, AlertKind.instant);
    expect(decoded.first.delivery, AlertDelivery.held);
    expect(decodeAlerts('{bozuk'), isEmpty);
    expect(decodeAlerts(null), isEmpty);
    // Bozuk tek kayıt listeyi düşürür, diğerleri kalır.
    final mixed = decodeAlerts('[{"id":"x","createdAt":"bozuk"},{"id":"y","createdAt":1}]');
    expect(mixed.single.id, 'y');
  });

  test('teslim ve düşürme işaretleri kaydı günceller', () {
    var history = [record('a'), record('b')];
    history = markAlertDelivered(history, 'a', DateTime(2026, 9, 28, 8));
    expect(history.firstWhere((item) => item.id == 'a').delivery, AlertDelivery.delivered);
    expect(history.firstWhere((item) => item.id == 'a').deliveredAt, DateTime(2026, 9, 28, 8));
    // Bilinmeyen kimlik geçmişi değiştirmez.
    final same = markAlertDelivered(history, 'yok', DateTime(2026, 9, 28));
    expect(same.firstWhere((item) => item.id == 'b').delivery, AlertDelivery.held);
    history = markAlertDropped(history, ['b']);
    expect(history.firstWhere((item) => item.id == 'b').delivery, AlertDelivery.dropped);
  });

  test('ekleme en yeni başta tutar ve sınırı aşmaz', () {
    var history = <AlertRecord>[];
    for (var i = 0; i < 205; i++) {
      history = appendAlert(history, record('$i'), limit: 200);
    }
    expect(history, hasLength(200));
    expect(history.first.id, '204');
    expect(history.last.id, '5');
    // Aynı kimlik tekrar eklenmez, güncellenir.
    history = appendAlert(history, record('204'), limit: 200);
    expect(history.where((item) => item.id == '204'), hasLength(1));
  });

  test('kuyruk planı: sessiz saatte boş, tavan kadarı FIFO gider', () {
    final queue = [record('a'), record('b'), record('c')];
    final night = planQueueFlush(
      queue: queue,
      now: DateTime(2026, 9, 27, 23),
      quietStartHour: 22,
      quietEndHour: 8,
      maxInstantPerDay: 6,
      instantSentToday: 0,
    );
    expect(night, isEmpty);
    final day = planQueueFlush(
      queue: queue,
      now: DateTime(2026, 9, 28, 9),
      quietStartHour: 22,
      quietEndHour: 8,
      maxInstantPerDay: 2,
      instantSentToday: 0,
    );
    expect(day.map((item) => item.id), ['a', 'b']);
    // Tavan dolduysa hiçbir şey çıkmaz, kuyruk korunur.
    final full = planQueueFlush(
      queue: queue,
      now: DateTime(2026, 9, 28, 9),
      quietStartHour: 22,
      quietEndHour: 8,
      maxInstantPerDay: 6,
      instantSentToday: 6,
    );
    expect(full, isEmpty);
  });

  test('kuyruk sınırında taşan en eskiler düşer', () {
    final queue = [for (var i = 0; i < 55; i++) record('$i')];
    final kept = trimQueue(queue);
    expect(kept, hasLength(50));
    expect(trimmedQueueIds(queue), hasLength(5));
    expect(trimmedQueueIds(queue).last, '54');
    expect(trimmedQueueIds(kept), isEmpty);
  });

  test('kimlik üreten kurucu benzersizdir', () {
    final a = AlertRecord.create(
      kind: AlertKind.digest,
      searchName: 'x',
      title: 't',
      body: 'b',
      listingUrl: 'https://ornek.gov.tr',
    );
    final b = AlertRecord.create(
      kind: AlertKind.digest,
      searchName: 'x',
      title: 't',
      body: 'b',
      listingUrl: 'https://ornek.gov.tr',
    );
    expect(a.id, isNot(b.id));
  });
}
