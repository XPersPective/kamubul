import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/listing_facts.dart';
import 'package:kamubul/listings/notice_text.dart';

void main() {
  test('alternatif KPSS puan türleri tek etikette gösterilir', () {
    expect(
      kpssLabel({
        'kpssStatus': 'required',
        'kpssTypes': ['P3', 'P44', 'P45'],
        'kpssScore': 75,
      }),
      'KPSS P3/P44/P45 en az 75',
    );
    expect(
      kpssLabel({'kpssStatus': 'required', 'kpssType': 'P94', 'kpssScore': 60}),
      'KPSS P94 en az 60',
    );
    expect(
      kpssTypeText({
        'kpssTypes': ['P3', 'KPSS'],
      }),
      isNull,
    );
  });

  test('tablo satırı: kısa hücreler bilgi satırı, nitelik cümleleri madde', () {
    // Canlı Niğde ilanı: kişi sayısı başlıkta, cinsiyet koşulu kalır.
    final row = positionDetails(
      'Destek Personeli (Temizlik Görevlisi) (Hastane) | 6 (Erkek-Kadın) | KPSS (P94) 2024 | - 2024 Kpss B Grubu P94 Puan Türünden En Az 60 Puan Almış olmak.',
      'Destek Personeli (Temizlik Görevlisi) (Hastane)',
      6,
    );
    expect(row.facts, ['Erkek-Kadın', 'KPSS (P94) 2024']);
    expect(row.requirements, [
      '- 2024 Kpss B Grubu P94 Puan Türünden En Az 60 Puan Almış olmak.',
    ]);

    final academic = positionDetails(
      'Tıp Fakültesi | Kardiyoloji | Doktor Öğretim Üyesi | 1 | Kardiyoloji uzmanı olmak.',
      'Doktor Öğretim Üyesi',
      1,
    );
    expect(academic.facts, ['Tıp Fakültesi', 'Kardiyoloji']);
    expect(academic.requirements, ['Kardiyoloji uzmanı olmak.']);
  });

  test('dikey tablo anahtarları gösterilmez, değerleri kalır', () {
    final kv = positionDetails(
      'İLAN NO | 20260201\n\nPOZİSYON ADI | Büro Personeli\n\nÖĞRENİM | Önlisans\n\nADEDİ | 2\n\n'
          'ARANILAN ŞARTLAR | Büro Yönetimi ön lisans programından mezun olmak.',
      'Büro Personeli',
      2,
    );
    expect(kv.facts, ['Önlisans']);
    expect(kv.requirements, [
      'Büro Yönetimi ön lisans programından mezun olmak.',
    ]);
  });
}
