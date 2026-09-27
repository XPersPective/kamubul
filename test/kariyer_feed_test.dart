import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/kariyer_feed.dart';

void main() {
  test('resmi bağlantıyı okur, sahte ve tekrar bağlantıyı atlar', () {
    const xml = '''<rss><channel>
      <item><title>Belediye personel alımı</title><category>Personel</category>
        <link>https://kariyerkapisi.gov.tr/IlanDetay?i=123</link>
        <pubDate>Mon, 14 Sep 2026 00:00:00 +0300</pubDate></item>
      <item><title>Yinelenen</title><link>https://kariyerkapisi.gov.tr/IlanDetay?i=123</link></item>
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
}
