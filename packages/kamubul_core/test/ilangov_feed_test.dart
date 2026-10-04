import 'dart:io';

import 'package:test/test.dart';
import 'package:kamubul_core/kamubul_core.dart';

void main() {
  // Fikstür 2026-10-04'te ilan.gov.tr AdsByFilter (ats=5) yanıtından alındı.
  final fixture = File('test/fixtures/ilangov_ads.json').readAsStringSync();

  test('kurum, il, yayın tarihi, kategori ve resmî bağlantıyı okur', () {
    final (items, total) = parseIlanGovAds(fixture);
    expect(total, 167);
    expect(items, hasLength(3));
    final first = items.first;
    expect(first.id, '2244449');
    expect(first.institution, 'ADALET BAKANLIĞI');
    expect(first.city, 'Ankara');
    expect(first.category, 'A Grubu Kadro Alımları');
    expect(first.publishedAt, DateTime.utc(2026, 10, 2, 21, 0, 1));
    expect(first.url.host, 'www.ilan.gov.tr');
    expect(first.url.path, startsWith('/ilan/2244449/'));
    expect(items[1].city, 'Osmaniye');
  });

  test('kayıt eşlemesi kurumu başlığa koyar, son tarihi tahmin etmez', () {
    final (items, _) = parseIlanGovAds(fixture);
    final record = ilanGovRecord(items.first, DateTime(2026, 10, 4));
    expect(record.sourceId, kIlanGovSourceId);
    expect(record.title, startsWith('ADALET BAKANLIĞI — '));
    expect(record.deadline, isNull);
    expect(record.places, ['Ankara']);
  });

  test('bozuk yanıt sessiz boş liste değil hata verir', () {
    expect(() => parseIlanGovAds('{"result":null}'), throwsFormatException);
  });

  test('HTML düz metne iner', () {
    expect(
      htmlToPlainText(
        '<p>Ba&#351;vuru&nbsp;&#351;artlar&#305; g&uuml;ncel &ccedil;:</p><ul><li>35 yaş</li><li>KPSS &amp; P3</li></ul><br>&#304;stanbul',
      ),
      'Başvuru şartları güncel ç:\n35 yaş\nKPSS & P3\nİstanbul',
    );
  });
}
