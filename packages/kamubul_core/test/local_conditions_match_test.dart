import 'package:test/test.dart';
import 'package:kamubul_core/kamubul_core.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 9);
  ListingRecord record({bool quoted = true}) => ListingRecord(
    url: 'https://kariyerkapisi.gov.tr/IlanDetay?i=1',
    sourceId: kKariyerSourceId,
    title: 'TEST - Memur',
    category: 'Personel',
    publishedAt: DateTime.utc(2026, 10, 1),
    fetchedAt: now,
    deadline: DateTime.utc(2026, 10, 20),
    places: const ['Ankara'],
    kpss: 'P3',
    kpssQuote: quoted ? 'KPSS P3 puan türünden en az 70 puan almış olmak.' : null,
    education: 'Lisans',
    educationQuote: quoted ? 'Lisans mezunu olmak.' : null,
    maxAge: 35,
    maxAgeQuote: quoted ? '35 yaşını doldurmamış olmak.' : null,
  );
  CriteriaMatch match(Map<String, Object?> c, {bool quoted = true}) =>
      SearchCriteria.parse({'version': 2, ...c})
          .match(record(quoted: quoted).matchingData, now: now);

  test('alıntılı yerel şartlar eşleştirmede kullanılır', () {
    expect(match({'education': ['Lisans']}), CriteriaMatch.match);
    expect(match({'education': ['Lise']}), CriteriaMatch.noMatch);
    expect(match({'kpssType': 'P3'}), CriteriaMatch.match);
    expect(match({'kpssType': 'P93'}), CriteriaMatch.noMatch);
    expect(match({'age': 34, 'ageAsOf': '2026-10-05'}), CriteriaMatch.match);
    expect(
      match({'age': 35, 'ageAsOf': '2026-10-05'}),
      CriteriaMatch.noMatch,
      reason: '"35 yaşını doldurmamış" 35 yaşındakini dışlar',
    );
  });

  test('alıntısız alan koşul sayılmaz; bilinmiyor kalır', () {
    expect(match({'education': ['Lisans']}, quoted: false), CriteriaMatch.unknown);
    expect(match({'kpssType': 'P3'}, quoted: false), CriteriaMatch.unknown);
  });

  test('yaş sınırı ifadesine göre kapsayıcı üst sınır', () {
    expect(inclusiveMaxAge(35, '35 yaşını doldurmamış olmak'), 34);
    expect(inclusiveMaxAge(36, '36 yaşından gün almamış olmak'), 35);
    expect(inclusiveMaxAge(35, '35 yaşından büyük olmamak'), 35);
  });

  test('başvuru dışı yaş referansı kesin eleme yapmaz', () {
    expect(ageReferenceIsApplication('Son başvuru tarihi itibarıyla 35 yaşını doldurmamış'), isTrue);
    expect(ageReferenceIsApplication('35 yaşını doldurmamış olmak'), isTrue);
    expect(ageReferenceIsApplication('Sınav yılının ocak ayının birinci günü itibariyle otuz beş yaşını doldurmamış'), isFalse);
    final r = ListingRecord(
      url: 'u', sourceId: kIlanGovSourceId, title: 't', category: 'c',
      publishedAt: null, fetchedAt: now, maxAge: 35,
      maxAgeQuote: 'Sınav yılının ocak ayının birinci günü itibariyle 35 yaşını doldurmamış olmak',
    );
    expect(
      SearchCriteria.parse({'version': 2, 'age': 40, 'ageAsOf': '2026-10-05'})
          .match(r.matchingData, now: now),
      CriteriaMatch.unknown,
    );
  });
}
