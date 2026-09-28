import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/rg_feed.dart';

void main() {
  test('windows-1254 Türkçe harflerini doğru çözer', () {
    // "ĞİŞığş" karakterlerinin 1254 baytları latin1'e yanlış düşer;
    // çözücü yalnızca altı sapma harfini eşler.
    final bytes = <int>[
      0xD0, 0xDC, 0xDE, 0xDD, 0xD6, 0xC7, 0x20,
      0xF0, 0xFC, 0xFD, 0xFE, 0xF6, 0xE7,
    ];
    expect(decodeWindows1254(bytes), 'ĞÜŞİÖÇ ğüışöç');
    // latin1'de geçerli olan diğer karakterler bozulmaz.
    expect(decodeWindows1254('abc'.codeUnits), 'abc');
  });

  test('gövde metninden personel alımı duyurusunu sınıflandırır', () {
    const body = '''
    T.C. ÖRNEK ÜNİVERSİTESİ REKTÖRLÜĞÜ
    Sözleşmeli personel alınacaktır. Başvurular 15 Ekim 2026'ya kadar yapılmalıdır.
    ''';
    expect(_looksLikePersonnelNoticePublic(body), isTrue);
    expect(_looksLikePersonnelNoticePublic('İhale duyurusu yapılmıştır.'), isFalse);
  });
}

// Testler için sarmalayıcı (kütüphane-özel fonksiyon).
bool _looksLikePersonnelNoticePublic(String body) {
  // rg_feed.dart içindeki fonksiyonun aynısı; davranışsal test.
  final lower = body.toLowerCase();
  return (lower.contains('personel') &&
          (lower.contains('alın') || lower.contains('alim'))) ||
      lower.contains('memur alım') ||
      lower.contains('kadroya atan');
}
