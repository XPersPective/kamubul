import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

final _now = DateTime(2026, 9, 29, 8);

ListingRecord _r(
  String url, {
  String source = 'kariyerkapisi',
  String title = 'KURUM A - İlan',
  DateTime? deadline,
  DateTime? fetched,
  int? maxAge,
  List<String> places = const [],
}) => ListingRecord(
  url: url,
  sourceId: source,
  title: title,
  category: 'Personel',
  publishedAt: DateTime(2026, 9, 28),
  fetchedAt: fetched ?? _now,
  deadline: deadline ?? DateTime(2026, 10, 5),
  maxAge: maxAge,
  places: places,
);

void main() {
  test(
    'yeni ilan added listesine girir; aynı URL ikinci kez yeni sayılmaz',
    () {
      final first = mergeCatalogue(
        previous: const [],
        incoming: [_r('https://x/1')],
        now: _now,
      );
      expect(first.added.map((r) => r.url), ['https://x/1']);
      final second = mergeCatalogue(
        previous: first.listings,
        incoming: [_r('https://x/1')],
        now: _now.add(const Duration(hours: 6)),
      );
      expect(second.added, isEmpty);
      expect(second.listings, hasLength(1));
    },
  );

  test('çapraz kaynak kopyası (aynı kurum + son gün) alınmaz', () {
    final a = _r(
      'https://kk/1',
      title: 'ANKARA ÜNİVERSİTESİ REKTÖRLÜĞÜ - İlan',
    );
    final b = _r(
      'https://sbb/9',
      source: 'kamuilan_sbb',
      title: 'ANKARA ÜNİVERSİTESİ REKTÖRLÜĞÜ — Sürekli işçi',
    );
    final result = mergeCatalogue(
      previous: const [],
      incoming: [a, b],
      now: _now,
    );
    expect(result.listings, hasLength(1));
    expect(result.added.single.url, 'https://kk/1');
  });

  test('aynı kaynaktaki aynı kurum + son gün ilanları ayrı kalır', () {
    final result = mergeCatalogue(
      previous: const [],
      incoming: [
        _r(
          'https://kk/1',
          title: 'ANKARA ÜNİVERSİTESİ REKTÖRLÜĞÜ - Memur alımı',
        ),
        _r(
          'https://kk/2',
          title: 'ANKARA ÜNİVERSİTESİ REKTÖRLÜĞÜ - İşçi alımı',
        ),
      ],
      now: _now,
    );
    expect(result.listings, hasLength(2));
    expect(result.added, hasLength(2));
  });

  test('yeni akış boş alan getirirse var olan ayrıntı silinmez', () {
    final enriched = _r('https://x/1', maxAge: 35, places: const ['ANKARA']);
    final result = mergeCatalogue(
      previous: [enriched],
      incoming: [_r('https://x/1')],
      now: _now.add(const Duration(hours: 6)),
    );
    final record = result.listings.single;
    expect(record.maxAge, 35);
    expect(record.places, ['ANKARA']);
    expect(record.fetchedAt, _now.add(const Duration(hours: 6)));
  });

  test('görünmeyen kayıt 45 gün sonra düşer, öncesinde kalır', () {
    final old = _r(
      'https://x/old',
      fetched: _now.subtract(const Duration(days: 44)),
    );
    final gone = _r(
      'https://x/gone',
      title: 'BAŞKA KURUM - X',
      fetched: _now.subtract(const Duration(days: 46)),
    );
    final result = mergeCatalogue(
      previous: [old, gone],
      incoming: const [],
      now: _now,
    );
    expect(result.listings.map((r) => r.url), ['https://x/old']);
  });

  test('üst sınır aşılırsa en yeni kayıtlar tutulur', () {
    final incoming = [
      for (var i = 0; i < 5; i++)
        _r(
          'https://x/$i',
          title: 'KURUM $i - İlan',
        ).copyWith(publishedAt: DateTime(2026, 9, 20 + i)),
    ];
    final result = mergeCatalogue(
      previous: const [],
      incoming: incoming,
      now: _now,
      maxListings: 3,
    );
    expect(result.listings, hasLength(3));
    expect(result.listings.first.url, 'https://x/4');
    expect(result.added.length, 3);
  });

  test(
    'applyConditionFields yalnızca alıntılı ve politikası açık alanları yazar',
    () {
      final record = applyConditionFields(
        _r('https://x/1'),
        const ConditionFields(
          maxAge: ExtractedField<int>(35, '35 yaşını doldurmamış olmak'),
          education: ExtractedField<String>('Lisans', 'Lisans mezunu olmak'),
        ),
      );
      expect(record.maxAge, 35);
      expect(record.maxAgeQuote, '35 yaşını doldurmamış olmak');
      expect(record.education, 'Lisans');
      expect(record.kpss, isNull);
    },
  );
}
