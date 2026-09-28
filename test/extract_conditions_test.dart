import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/extract_conditions.dart';
import 'package:kamubul/listings/extraction_policy.dart';

void main() {
  // Fikstürler 2026-09-27'de canlı kamu ilan metinlerinde görülen kalıplardır.
  test('KPSS puan türü, taban puan, yaş ve eğitimi alıntıyla çıkarır', () {
    const text = '''
İşe girmeden önce adayların aşağıdaki şartları taşıması gerekir.
1- 2024 yılına ait KPSS B grubu KPSS P3 temel puan türünden en az 70 puan almış olmak.
2- Son başvuru tarihi itibariyle 35 yaşını doldurmamış olmak.
3- Dört yıllık lisans programlarından mezun olmak.
''';
    final fields = extractConditions(text);
    expect(fields.kpssType!.value, 'P3');
    expect(fields.kpssType!.quote, contains('KPSS P3'));
    expect(fields.kpssScore!.value, 70);
    expect(fields.maxAge!.value, 35);
    expect(fields.maxAge!.quote, contains('35 yaşını doldurmamış'));
    expect(fields.education!.value, 'Lisans');
    expect(fields.education!.quote, contains('lisans programlarından mezun'));
  });

  test('alternatif yaş ve puan kalıplarını okur', () {
    const text = 'Adayların 32 yaşından gün almamış olması; '
        'KPSS P93 puan türünden en az 60 (altmış) ve üzeri puan alması gerekir.';
    final fields = extractConditions(text);
    expect(fields.maxAge!.value, 32);
    expect(fields.kpssType!.value, 'P93');
    expect(fields.kpssScore!.value, 60);
  });

  test('aralık dışı değerleri reddeder', () {
    const text = 'KPSS P999 puan türü kullanılacaktır. '
        'Adaylar 99 yaşını doldurmamış olmak koşuluyla başvurabilir.';
    final fields = extractConditions(text);
    expect(fields.kpssType, isNull);
    expect(fields.maxAge, isNull);
  });

  test('kanıt cümlesi olmayan değer üretmez', () {
    final fields = extractConditions('Bu ilan herkese açıktır.');
    expect(fields.kpssType, isNull);
    expect(fields.kpssScore, isNull);
    expect(fields.maxAge, isNull);
    expect(fields.education, isNull);
  });

  test('sınav oturumu eşiği KPSS taban puanı sanılmaz (BDDK yanlış-pozitifi)', () {
    const text = '''
Yazılı sınav aşamasında, adayın katılmakla yükümlü olduğu her bir oturum 100 puan üzerinden değerlendirilir ve adayın başarılı sayılabilmesi için her oturumdan en az 60 puan alması ve sınav ortalamasının en az 70 puan olması gerekir.
2- 2024 yılına ait KPSS B grubu KPSS P3 temel puan türünden en az 70 puan almış olmak.
''';
    final fields = extractConditions(text);
    expect(fields.kpssScore!.value, 70);
    expect(fields.kpssScore!.quote, contains('KPSS P3'));
  });

  test('kota tipini ayırt eder', () {
    final fields = extractConditions(
      'Bu kadro 4/B sözleşmeli personel için ayrılmıştır.',
    );
    expect(fields.quotaType!.value, '4/B');
    final other = extractConditions('Engelli kontenjanı için ayrılmışdır.');
    expect(other.quotaType!.value, 'Engelli');
  });

  test('politikası kapalı alan düşürülür, açık alan korunur', () {
    const text = '2024 KPSS P3 puan türünden en az 70 puan almış olmak. '
        'Dört yıllık lisans programlarından mezun olmak.';
    final fields = extractConditions(text);
    final gated = applyExtractionPolicy(
      fields,
      policy: const {'education': true, 'kpssType': false},
    );
    expect(gated.education!.value, 'Lisans');
    expect(gated.kpssType, isNull);
    expect(gated.kpssScore, isNull); // politikada adı geçmiyorsa düşer
  });
}
