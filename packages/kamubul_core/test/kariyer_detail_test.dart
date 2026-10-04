import 'package:test/test.dart';
import 'package:kamubul_core/listings/kariyer_detail.dart';

void main() {
  // Alan adları 2026-09-27'de canlı GetIlanPreviewPublic /
  // GetAltIlanInfoByIlanIdPublic yanıtlarından doğrulanmıştır.
  const mainJson = <String, dynamic>{
    'kurumAdi': 'TÜRKİYE İNSAN HAKLARI VE EŞİTLİK KURUMU BAŞKANLIĞI',
    'ilanMetni': '[b]Genel Şartlar[/b]\n657 sayılı kanuna göre sözleşmeli personel alınacaktır.\nLisans mezunu olmak.\u00a0 ',
    'basTarih': '2026-09-20T00:00:00',
    'bitTarih': '2026-09-27T23:59:00',
    'eDevletteGorunsun': 1,
    'eDevletServisURL':
        'https://www.turkiye.gov.tr/thve-kariyer-kapisi-kamu-ise-alim',
    'basvuruLinki': '',
  };

  final positionsJson = <Object?>[
    <String, dynamic>{
      'ilanBaslik': 'Hukuk Müşaviri',
      'unvan': 'Hukuk Müşaviri',
      'ilanMetni': 'KPSS P3 puan türü kullanılacaktır.\nLisans mezunu olmak.',
      'kontenjanList': [
        {'kontenjan': 3, 'il': 'ANKARA'},
        {'kontenjan': 1, 'il': 'ANKARA'},
        {'kontenjan': 2, 'il': 'İSTANBUL'},
        {'kontenjan': 'bozuk', 'il': ''},
      ],
    },
    'bozuk-oge',
  ];

  test(
    'kurum, kontenjan, yer ve tarihleri okur; e-Devlet bağlantısını seçer',
    () {
      final detail = parseKariyerDetail(mainJson, positionsJson);
      expect(detail.institution, contains('İNSAN HAKLARI'));
      expect(detail.quota, 6);
      expect(detail.places, ['ANKARA', 'İSTANBUL']);
      expect(detail.deadline, DateTime(2026, 9, 27, 23, 59));
      expect(detail.applyUrl, isNotNull);
      expect(detail.applyUrl!.host, 'www.turkiye.gov.tr');
      expect(detail.positions, hasLength(1));
      expect(detail.positions.single.quota, 6);
      expect(detail.positions.single.keyConditions, isNotEmpty);
    },
  );

  test('e-Devlet dışı ilanda başvuru bağlantısını kullanır', () {
    final detail = parseKariyerDetail(<String, dynamic>{
      ...mainJson,
      'eDevletteGorunsun': 0,
      'basvuruLinki': 'https://kurum.gov.tr/basvuru',
    }, []);
    expect(detail.applyUrl!.toString(), 'https://kurum.gov.tr/basvuru');
  });

  test('http ve bozuk başvuru bağlantısını reddeder', () {
    final detail = parseKariyerDetail(<String, dynamic>{
      ...mainJson,
      'eDevletteGorunsun': 0,
      'basvuruLinki': 'http://kurum.gov.tr/basvuru',
    }, []);
    expect(detail.applyUrl, isNull);
  });

  test('biçim değişiminde FormatException verir', () {
    expect(
      () => parseKariyerDetail('beklenmeyen', positionsJson),
      throwsFormatException,
    );
    expect(
      () => parseKariyerDetail(mainJson, 'liste-değil'),
      throwsFormatException,
    );
  });

  test('ilan metnindeki BBCode ve bozuk boşluklar temizlenir', () {
    final text = plainNoticeText(
      '[b]Şartlar:[/b]\u00a0 KPSS puanı   en az 70\n\n\n\n[Türkçe olmalı]',
    );
    expect(text, 'Şartlar: KPSS puanı en az 70\n\n[Türkçe olmalı]');
  });

  test('kaynakta iki kez yazılan yer tek gösterilir', () {
    final detail = parseKariyerDetail(mainJson, [
      {
        'kontenjanList': [
          {
            'kontenjan': 1,
            'il': 'BAKANLIK MERKEZ TEŞKİLATI / BAKANLIK MERKEZ TEŞKİLATI',
          },
          {'kontenjan': 1, 'il': 'BAKANLIK MERKEZ TEŞKİLATI'},
        ],
      },
    ]);
    expect(detail.places, ['BAKANLIK MERKEZ TEŞKİLATI']);
    expect(detail.positions.single.places, ['BAKANLIK MERKEZ TEŞKİLATI']);
  });

  test('tekrarlı yer adı tekilleşir', () {
    expect(
      cleanKariyerPlace('BAKANLIK MERKEZ TEŞKİLATI /  BAKANLIK MERKEZ TEŞKİLATI '),
      'BAKANLIK MERKEZ TEŞKİLATI',
    );
    expect(cleanKariyerPlace('ANKARA / ÇANKAYA'), 'ANKARA / ÇANKAYA');
  });
}
