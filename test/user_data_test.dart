import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/data/user_data.dart';
import 'package:kamubul_core/kamubul_core.dart' show SearchCriteria;

/// Elle doldurulmuş tek bir arama + yer imi; tur sonrası alan alan eşitlenir.
SavedSearch _search() => SavedSearch(
  id: 7,
  name: 'Ankara işçi',
  filters: const {'q': 'bekçi', 'sehir': 'Ankara', 'kategori': '1'},
  createdAt: DateTime(2026, 9, 1, 10),
);

ListingRecord _bookmark() => ListingRecord(
  url: 'https://kariyerkapisi.gov.tr/ilan/123',
  sourceId: 'kariyerkapisi',
  title: 'Sürekli işçi alımı',
  category: 'İşçi',
  publishedAt: DateTime(2026, 8, 20, 9),
  fetchedAt: DateTime(2026, 9, 1, 12),
  deadline: DateTime(2026, 9, 30, 23, 59),
  quota: 4,
  places: const ['Ankara', 'Çankaya'],
  kpss: 'P94',
  kpssQuote: 'KPSS P94 puan türünden en az 60 puan almış olmak.',
  education: 'Lise',
  educationQuote: 'En az lise mezunu olmak.',
  maxAge: 35,
  maxAgeQuote: '35 yaşını doldurmamış olmak.',
  quotaType: '4/B',
  quotaTypeQuote: '4857 sayılı İş Kanununun 4. maddesinin (B) fıkrası.',
  savedAt: DateTime(2026, 9, 2, 8),
);

String _envelope(Object? data, {String packageName = kUserDataPackageName}) =>
    jsonEncode({
      'kind': 'napp-backup',
      'formatVersion': 1,
      'packageName': packageName,
      'data': data,
    });

void main() {
  test('dışa aktarma → içe aktarma turu tüm alanları korur', () {
    final exportedAt = DateTime(2026, 9, 28, 12);
    final json = exportUserDataJson(
      searches: [_search()],
      bookmarks: [_bookmark()],
      exportedAt: exportedAt,
    );
    final imported = parseUserDataJson(json);

    expect(imported.searches, hasLength(1));
    final search = imported.searches.single;
    expect(search.id, isNull, reason: 'kimlikler sıfırdan verilir');
    expect(search.name, 'Ankara işçi');
    expect(search.filters, _search().filters);
    expect(search.createdAt, DateTime(2026, 9, 1, 10));

    expect(imported.bookmarks, hasLength(1));
    final record = imported.bookmarks.single;
    final source = _bookmark();
    expect(record.url, source.url);
    expect(record.sourceId, source.sourceId);
    expect(record.title, source.title);
    expect(record.category, source.category);
    expect(record.publishedAt, source.publishedAt);
    expect(record.fetchedAt, source.fetchedAt);
    expect(record.deadline, source.deadline);
    expect(record.quota, source.quota);
    expect(record.places, source.places);
    expect(record.kpss, source.kpss);
    expect(record.kpssQuote, source.kpssQuote);
    expect(record.education, source.education);
    expect(record.educationQuote, source.educationQuote);
    expect(record.maxAge, source.maxAge);
    expect(record.maxAgeQuote, source.maxAgeQuote);
    expect(record.quotaType, source.quotaType);
    expect(record.quotaTypeQuote, source.quotaTypeQuote);
    expect(record.savedAt, source.savedAt);
    expect(record.saved, isTrue);
  });

  test('içe aktarılan yer imi kayıtlı sayılır, kaydetme zamanı geri düşer', () {
    final json = _envelope({
      'schema': 1,
      'bookmarks': [
        {
          'url': 'https://kariyerkapisi.gov.tr/ilan/9',
          'sourceId': 'kariyerkapisi',
          'title': 'İlan',
          'fetchedAt': '2026-09-01T00:00:00.000',
        },
      ],
    });
    final record = parseUserDataJson(json).bookmarks.single;
    expect(record.saved, isTrue);
    expect(record.savedAt, DateTime(2026, 9, 1));
    expect(record.category, '');
  });

  test('zarfsız JSON reddedilir', () {
    final bare = jsonEncode({
      'schema': 1,
      'searches': <Object?>[],
      'bookmarks': <Object?>[],
    });
    expect(() => parseUserDataJson(bare), throwsFormatException);
  });

  test('başka uygulamanın yedeği reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'searches': [],
      'bookmarks': [],
    }, packageName: 'com.example.baska');
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('ayrılmış anahtar (Pro durumu) yedeğe girerse dosya reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'pro': true,
      'searches': [],
      'bookmarks': [],
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('gelecek zarf sürümü reddedilir', () {
    final json = jsonEncode({
      'kind': 'napp-backup',
      'formatVersion': 2,
      'packageName': kUserDataPackageName,
      'data': {'schema': 1, 'searches': [], 'bookmarks': []},
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('bozuk JSON reddedilir', () {
    expect(() => parseUserDataJson('bu json değil'), throwsFormatException);
  });

  test('şema sürümü uyuşmazsa reddedilir', () {
    final json = _envelope({'schema': 99, 'searches': [], 'bookmarks': []});
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('typed arama yedeği puanı, tarih ve alternatifleri korur; eski yedek okunur', () {
    final criteria = SearchCriteria.parse({
      'version': 2,
      'cities': ['Ankara', 'İzmir'],
      'age': 30,
      'ageAsOf': '2026-09-29',
      'kpssType': 'P3',
      'kpssScore': 69.99,
      'kpssYear': 2024,
    });
    final search = _search().copyWith(criteria: criteria);
    final json = exportUserDataJson(searches: [search], bookmarks: []);
    final restored = parseUserDataJson(json).searches.single;
    expect(restored.criteria!.values, criteria.values);
    expect(restored.id, isNull);
    final legacy = parseUserDataJson(
      _envelope({
        'schema': 1,
        'searches': [
          {
            'name': 'Eski',
            'filters': {'yas': '30'},
            'createdAt': '2026-09-01T00:00:00.000',
          },
        ],
      }),
    ).searches.single;
    expect(legacy.effectiveCriteria.values['ageAsOf'], '1970-01-01');
  });

  test(
    'bozuk typed kriter içe aktarmayı ve kayıplı dışa aktarmayı engeller',
    () {
      final row = {
        'name': 'Bozuk',
        'filters': {},
        'createdAt': '2026-09-01T00:00:00.000',
        'criteria': {'version': 2, 'kpssScore': 70},
      };
      expect(
        () => parseUserDataJson(
          _envelope({
            'schema': 2,
            'searches': [row],
          }),
        ),
        throwsFormatException,
      );
      final broken = SavedSearch.fromRow({
        'id': 1,
        'name': 'Bozuk',
        'filters': '{bad',
        'createdAt': 0,
      });
      expect(
        () => exportUserDataJson(searches: [broken], bookmarks: []),
        throwsFormatException,
      );
    },
  );

  test('http bağlantı reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'bookmarks': [
        {
          'url': 'http://ornek.test/ilan',
          'sourceId': 'kariyerkapisi',
          'title': 'İlan',
          'fetchedAt': '2026-09-01T00:00:00.000',
        },
      ],
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('bilinmeyen kaynak reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'bookmarks': [
        {
          'url': 'https://ornek.test/ilan',
          'sourceId': 'rakip_site',
          'title': 'İlan',
          'fetchedAt': '2026-09-01T00:00:00.000',
        },
      ],
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('yanlış tipler reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'bookmarks': [
        {
          'url': 'https://kariyerkapisi.gov.tr/ilan/1',
          'sourceId': 'kariyerkapisi',
          'title': 'İlan',
          'fetchedAt': '2026-09-01T00:00:00.000',
          'quota': 'çok',
        },
      ],
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('adsız arama reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'searches': [
        {'name': '', 'filters': {}, 'createdAt': '2026-09-01T00:00:00.000'},
      ],
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });

  test('aşırı kayıt sayısı reddedilir', () {
    final json = _envelope({
      'schema': 1,
      'searches': [
        for (var i = 0; i < 101; i++)
          {
            'name': 'arama $i',
            'filters': <String, String>{},
            'createdAt': '2026-09-01T00:00:00.000',
          },
      ],
    });
    expect(() => parseUserDataJson(json), throwsFormatException);
  });
}
