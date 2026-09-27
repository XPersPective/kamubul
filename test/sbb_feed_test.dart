import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/sbb_feed.dart';

void main() {
  // Fikstür 2026-09-27'de kamuilan.sbb.gov.tr 2026 listesinden alınmıştır.
  final fixture = File('test/fixtures/sbb_list.html').readAsStringSync();

  test('kurum, kontenjan, tarih aralığı ve resmî bağlantıyı okur', () {
    final items = parseSbbListings(fixture);
    expect(items, hasLength(3));
    final first = items.first;
    expect(first.institution, 'TÜRKİYE ULUSLARARASI İSLAM, BİLİM VE TEKNOLOJİ ÜNİVERSİTESİ');
    expect(first.title, contains('7 SÖZLEŞMELİ PERSONEL ALACAK'));
    expect(first.category, 'Sözleşmeli Personel');
    expect(first.quota, 7);
    expect(first.publishedAt, DateTime(2026, 9, 28));
    expect(first.start, DateTime(2026, 9, 28));
    expect(first.deadline, DateTime(2026, 10, 12));
    expect(first.url.host, 'kamuilan.sbb.gov.tr');
    expect(first.url.path, '/ilanDetay.aspx');
    expect(first.url.queryParameters['kod'], isNotEmpty);
  });

  test('yılları aşan aralıkta son tarihi doğru hesaplar', () {
    const html =
        "<a href='ilanDetay.aspx?kod=abc' class='xx'><img src='./ilan_dosyalar/logolar/1.png#15.12.2026 00:00:00'/>"
        "<h5><span class='black'>TEST KURUMU</span><span class='patrol'>2 İŞÇİ ALACAK</span>"
        "<span class='h5date'>15 Aralık - 5 Ocak</span></h5></a>";
    final items = parseSbbListings(html);
    expect(items.single.category, 'İşçi');
    expect(items.single.quota, 2);
    expect(items.single.start, DateTime(2026, 12, 15));
    expect(items.single.deadline, DateTime(2027, 1, 5));
  });

  test('düzen değişirse FormatException verir', () {
    expect(() => parseSbbListings('<html><body>boş</body></html>'), throwsFormatException);
  });
}
