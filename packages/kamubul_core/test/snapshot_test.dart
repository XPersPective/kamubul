import 'dart:convert';

import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

ListingRecord _record(String url, {String title = 'KURUM - İlan'}) =>
    ListingRecord(
      url: url,
      sourceId: 'kariyerkapisi',
      title: title,
      category: 'Personel',
      publishedAt: DateTime(2026, 9, 28),
      fetchedAt: DateTime(2026, 9, 29, 8),
      deadline: DateTime(2026, 10, 5, 23, 59),
      quota: 12,
      places: const ['ANKARA'],
      maxAge: 35,
      maxAgeQuote: '35 yaşını doldurmamış olmak',
      summary: const ['Yaş sınırı 35'],
    );

void main() {
  test('snapshot gidiş-dönüş: alanlar ve duvar saati korunur', () {
    final snapshot = CatalogueSnapshot(
      generatedAt: DateTime(2026, 9, 29, 8),
      sources: [
        SourceStatus(
          id: 'kariyerkapisi',
          name: 'Kariyer Kapısı',
          state: SourceState.ok,
          lastSuccessAt: DateTime(2026, 9, 29, 8),
          listingCount: 1,
        ),
        const SourceStatus(
          id: 'iskur',
          name: 'İŞKUR',
          state: SourceState.blocked,
          note: 'WAF',
        ),
      ],
      listings: [_record('https://kariyerkapisi.gov.tr/ilan/1')],
    );
    final decoded = CatalogueSnapshot.decode(snapshot.encode());
    expect(decoded.generatedAt, DateTime(2026, 9, 29, 8));
    expect(decoded.sources.map((s) => s.state), [
      SourceState.ok,
      SourceState.blocked,
    ]);
    final record = decoded.listings.single;
    expect(record.deadline, DateTime(2026, 10, 5, 23, 59));
    expect(record.maxAge, 35);
    expect(record.maxAgeQuote, '35 yaşını doldurmamış olmak');
    expect(record.summary, ['Yaş sınırı 35']);
    expect(record.places, ['ANKARA']);
  });

  test('bilinmeyen şema, bozuk JSON ve eksik alanlar reddedilir', () {
    expect(
      () => CatalogueSnapshot.decode('{bozuk'),
      throwsA(isA<SnapshotFormatException>()),
    );
    expect(
      () => CatalogueSnapshot.decode(
        jsonEncode({
          'schema': 2,
          'generatedAt': '2026-09-29T08:00:00',
          'listings': [],
        }),
      ),
      throwsA(isA<SnapshotFormatException>()),
    );
    expect(
      () => CatalogueSnapshot.decode(jsonEncode({'schema': 1, 'listings': []})),
      throwsA(isA<SnapshotFormatException>()),
    );
    expect(
      () => CatalogueSnapshot.decode(
        jsonEncode({'schema': 1, 'generatedAt': '2026-09-29T08:00:00'}),
      ),
      throwsA(isA<SnapshotFormatException>()),
    );
  });

  test('geçersiz kayıtlar atlanır, geçerliler kalır', () {
    final good = listingToJson(_record('https://x.gov.tr/1'));
    final body = jsonEncode({
      'schema': 1,
      'generatedAt': '2026-09-29T08:00:00',
      'listings': [
        good,
        {...good, 'url': 'http://x.gov.tr/http'}, // https değil
        {...good, 'url': 'https://x.gov.tr/2', 'title': ''}, // boş başlık
        {
          ...good,
          'url': 'https://x.gov.tr/3',
          'maxAge': 5,
        }, // yaş sınırı dışı: alan düşer
        good, // yinelenen url
        'metin',
      ],
    });
    final decoded = CatalogueSnapshot.decode(body);
    expect(decoded.listings.map((r) => r.url), [
      'https://x.gov.tr/1',
      'https://x.gov.tr/3',
    ]);
    expect(decoded.listings.last.maxAge, isNull);
    expect(decoded.skipped, 4);
  });

  test('ofsetli/UTC tarih değeri okunmaz (yalnızca duvar saati)', () {
    expect(parseWallIso('2026-09-29T08:00:00Z'), isNull);
    expect(parseWallIso('2026-09-29T08:00:00'), DateTime(2026, 9, 29, 8));
    expect(wallIso(DateTime.utc(2026, 9, 29, 8)), '2026-09-29T08:00:00.000');
  });

  test('wallClock Türkiye saatini üretir', () {
    final wall = wallClock(DateTime.utc(2026, 9, 29, 21, 30));
    expect(wall, DateTime(2026, 9, 30, 0, 30));
    expect(dayKey(wall), '2026-09-30');
  });
}
