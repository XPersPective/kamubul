import 'dart:io';

import 'package:test/test.dart';
import 'package:kamubul_core/listings/sbb_feed.dart';

void main() {
  // Fikstür 2026-09-27'de kamuilan.sbb.gov.tr 2026 listesinden alınmıştır.
  final fixture = File('test/fixtures/sbb_list.html').readAsStringSync();

  test('kurum, kontenjan, tarih aralığı ve resmî bağlantıyı okur', () {
    final items = parseSbbListings(fixture, referenceYear: 2026);
    expect(items, hasLength(3));
    final first = items.first;
    expect(first.institution, 'TÜRKİYE ULUSLARARASI İSLAM, BİLİM VE TEKNOLOJİ ÜNİVERSİTESİ');
    expect(first.title, contains('7 SÖZLEŞMELİ PERSONEL ALACAK'));
    expect(first.category, 'Sözleşmeli Personel');
    expect(first.quota, 7);
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
    final items = parseSbbListings(html, referenceYear: 2026);
    expect(items.single.category, 'İşçi');
    expect(items.single.quota, 2);
    expect(items.single.start, DateTime(2026, 12, 15));
    expect(items.single.deadline, DateTime(2027, 1, 5));
  });

  // PB-007 değerlendirme korpusundan gerçek satır (2026 tahtası, ikinci
  // şablon). Sayfadaki satırların çoğunluğu bu şablondadır.
  test('alt_p şablonundaki satırı okur', () {
    const html =
        "<a href='ilanDetay.aspx?kod=alt1' class='xx ' target='_blank'><div>"
        "<img class='limg2' src='./ilan_dosyalar/logolar/390.png#28.09.2026 00:00:00'/>"
        "<p class='alt_p1'>İZMİR BAKIRÇAY ÜNİVERSİTESİ</p>"
        "<p class='alt_p2'> 6 SÖZLEŞMELİ PERSONEL ALACAK"
        "<em style='color: #ff3d00' > ( 28 Eylül - 13 Ekim) </em> </p>"
        "</div></a>";
    final items = parseSbbListings(html, referenceYear: 2026);
    final item = items.single;
    expect(item.institution, 'İZMİR BAKIRÇAY ÜNİVERSİTESİ');
    expect(item.title, '6 SÖZLEŞMELİ PERSONEL ALACAK');
    expect(item.category, 'Sözleşmeli Personel');
    expect(item.quota, 6);
    expect(item.start, DateTime(2026, 9, 28));
    expect(item.deadline, DateTime(2026, 10, 13));
  });

  test('alt_p şablonunda aylar arası aralığı okur', () {
    const html =
        "<a href='ilanDetay.aspx?kod=alt2' class='xx ' target='_blank'><div>"
        "<img class='limg2' src='./ilan_dosyalar/logolar/407.png#28.09.2026 00:00:00'/>"
        "<p class='alt_p1'>ESKİŞEHİR TEKNİK ÜNİVERSİTESİ</p>"
        "<p class='alt_p2'> 3 ADET ÖĞRETİM ÜYESİ ALIMI"
        "<em style='color: #ff3d00' > ( 25 Eylül - 8 Aralık) </em> </p>"
        "</div></a>";
    final items = parseSbbListings(html, referenceYear: 2026);
    final item = items.single;
    expect(item.institution, 'ESKİŞEHİR TEKNİK ÜNİVERSİTESİ');
    expect(item.title, '3 ADET ÖĞRETİM ÜYESİ ALIMI');
    expect(item.quota, 3);
    expect(item.start, DateTime(2026, 9, 25));
    expect(item.deadline, DateTime(2026, 12, 8));
  });

  test('birden çok kadronun kontenjanı toplanır', () {
    const html =
        "<a href='ilanDetay.aspx?kod=cogul' class='xx'><h5>"
        "<span class='black'>DOĞU MARMARA KALKINMA AJANSI</span>"
        "<span class='patrol'>3 UZMAN, 2 DESTEK PERSONEL ALACAK</span>"
        "<span class='h5date'>12 Ekim - 27 Ekim</span></h5></a>";
    final items = parseSbbListings(html, referenceYear: 2026);
    expect(items.single.quota, 5);
    expect(items.single.category, 'Kamu Personeli');
  });

  test('yıl sayısı kontenjan sanılmaz', () {
    const html =
        "<a href='ilanDetay.aspx?kod=yil' class='xx'><h5>"
        "<span class='black'>MİLLİ SAVUNMA BAKANLIĞI</span>"
        "<span class='patrol'>TÜRK SİLAHLI KUVVETLERİ 2026 YILI HUKUK SINIFI "
        "MUVAZZAF SUBAY ADAYI TEMİNİ</span>"
        "<span class='h5date'>7 Eylül - 7 Ekim</span></h5></a>";
    final items = parseSbbListings(html, referenceYear: 2026);
    expect(items.single.quota, isNull);
  });

  test('düzen değişirse FormatException verir', () {
    expect(() => parseSbbListings('<html><body>boş</body></html>'), throwsFormatException);
  });
}
