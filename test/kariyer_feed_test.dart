import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/listings/kariyer_feed.dart';
import 'package:kamubul/data/turkish_cities.dart';

void main() {
  test('81 il adı yazım farklarından resmî ada çevrilir', () {
    expect(turkishCities, hasLength(81));
    expect(canonicalCity('Istanbul'), 'İstanbul');
    expect(canonicalCity('Sanliurfa'), 'Şanlıurfa');
    expect(canonicalCity('Izmir'), 'İzmir');
    expect(canonicalCity('Uydurma'), isNull);
  });

  test('resmi bağlantıyı okur, sahte ve tekrar bağlantıyı atlar', () {
    const xml = '''<rss><channel>
      <item><title>Belediye personel alımı</title><category>Personel</category>
        <link>https://kariyerkapisi.gov.tr/IlanDetay?i=123</link>
        <pubDate>Mon, 14 Sep 2026 00:00:00 +0300</pubDate></item>
      <item><title>Yinelenen</title><link>https://kariyerkapisi.gov.tr/IlanDetay?i=123</link></item>
      <item><title>Yurt dışı staj</title><category>Yurt Dışı Eğitim İlanları</category>
        <link>https://kariyerkapisi.gov.tr/IlanDetay?i=456</link></item>
      <item><title>Sahte</title><link>https://evil.example/IlanDetay?i=123</link></item>
    </channel></rss>''';
    final items = parseKariyerFeed(xml);
    expect(items, hasLength(1));
    expect(items.single.title, 'Belediye personel alımı');
    expect(items.single.publishedAt, isNotNull);
    expect(items.single.publishedAt!.day, 14);
  });

  test('geçersiz akış hata verir', () {
    expect(() => parseKariyerFeed('<html/>'), throwsFormatException);
  });

  test(
    'toplu resmî liste son tarihi verir, RSS yayın gününü tamamlar',
    () async {
      const id = '27cf966f-b2b9-4671-a21a-731cb060436a';
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          expect(request.url.toString(), kariyerIndexUrl);
          return http.Response(
            '''{"searchIlan":[
          {"guid":"$id","ilanBaslik":"29 kişi alımı","ilanTuru":"Personel",
           "bitTarih":"2026-09-29T13:00:00"},
          {"guid":"0b99929b-9164-4adc-b4fb-78894857f700","ilanBaslik":"Yurt dışı staj",
           "ilanTuru":"Yurt Dışı Eğitim İlanları","bitTarih":"2026-09-29T13:00:00"},
          {"guid":"kötü","ilanBaslik":"Sahte","bitTarih":"2026-09-29T13:00:00"}
        ]}''',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          '''<rss><channel><item>
        <title>29 kişi alımı</title>
        <link>https://kariyerkapisi.gov.tr/IlanDetay?i=$id</link>
        <pubDate>Mon, 14 Sep 2026 00:00:00 +0300</pubDate>
      </item></channel></rss>''',
          200,
          headers: {'content-type': 'application/xml; charset=utf-8'},
        );
      });
      final items = await loadKariyerListings(client: client);
      expect(items, hasLength(1));
      expect(items.single.deadline, DateTime(2026, 9, 29, 13));
      expect(items.single.publishedAt, DateTime(2026, 9, 14));
    },
  );

  test('toplu liste arızalanırsa RSS ilanları korunur', () async {
    final client = MockClient(
      (request) async => request.method == 'POST'
          ? http.Response('', 500)
          : http.Response(
              '''<rss><channel><item>
          <title>Resmî ilan</title>
          <link>https://kariyerkapisi.gov.tr/IlanDetay?i=123</link>
          </item></channel></rss>''',
              200,
              headers: {'content-type': 'application/xml; charset=utf-8'},
            ),
    );
    final items = await loadKariyerListings(client: client);
    expect(items.single.title, 'Resmî ilan');
    expect(items.single.deadline, isNull);
  });

  test('şehir sorgusu resmî API parametresini kullanır', () async {
    const id = '27cf966f-b2b9-4671-a21a-731cb060436a';
    final client = MockClient((request) async {
      expect(jsonDecode(request.body)['il'], 'Ankara');
      return http.Response(
        '{"searchIlan":[{"guid":"$id","ilanBaslik":"İş ilanı",'
        '"ilanTuru":"Personel","bitTarih":"2026-09-29T13:00:00"}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final items = await loadKariyerCityListings(' Ankara ', client: client);
    expect(items.single.url.queryParameters['i'], id);
    expect(
      () => loadKariyerCityListings('Ankara\nİzmir', client: client),
      throwsFormatException,
    );
  });
}
