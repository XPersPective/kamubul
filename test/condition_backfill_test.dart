import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/condition_backfill.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'AI kota hatası son metni kalıcı tutar; tekrar turu kaynağı yeniden okumaz',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 11,
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      );
      final store = ListingStore(database: db);
      addTearDown(store.close);
      final now = DateTime(2026, 10, 5);
      const url = 'https://www.ilan.gov.tr/ilan/123/x';
      await store.mergeFeed([
        ListingRecord(
          url: url,
          sourceId: kIlanGovSourceId,
          title: 'Belediye',
          publishedAt: now,
          category: 'Personel',
          fetchedAt: now,
        ),
      ]);
      var reads = 0;
      await backfillConditions(
        store,
        now: now,
        gap: Duration.zero,
        readText: (_) async {
          reads++;
          return 'Lisans mezunu olmak.';
        },
        aiExtract: (_) async => null,
      );
      expect((await store.uncheckedConditions(now: now)).length, 1);
      expect(await store.pendingConditionText(url), 'Lisans mezunu olmak.');
      await store.mergeFeed([
        ListingRecord(
          url: url,
          sourceId: kIlanGovSourceId,
          title: 'Belediye',
          publishedAt: now,
          category: 'Personel',
          fetchedAt: now,
        ),
      ]);
      await backfillConditions(
        store,
        now: now,
        gap: Duration.zero,
        readText: (_) async => fail('cached text must survive refresh/retry'),
        aiExtract: (_) async => [],
      );
      expect(reads, 1);
      expect(await store.uncheckedConditions(now: now), isEmpty);
      expect(await store.pendingConditionText(url), isNull);
    },
  );

  test('v10→11 göçü yerel metin retry alanını ekler, türetilmiş AI şartını yeniden kontrol eder', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE listings (url TEXT PRIMARY KEY, title TEXT, saved INTEGER, conditionsCheckedAt INTEGER, aiGroups TEXT)',
    );
    await db.insert('listings', {
      'url': 'official',
      'title': 'İlan',
      'saved': 1,
      'conditionsCheckedAt': 123,
      'aiGroups': '[]',
    });
    await ListingStore.upgradeSchema(db, 10, 11);
    final row = (await db.query('listings')).single;
    expect(row['saved'], 1);
    expect(row['title'], 'İlan');
    expect(row.containsKey('pendingConditionText'), isTrue);
    expect(row['conditionsCheckedAt'], isNull);
    expect(row['aiGroups'], isNull);
  });

  test(
    'ayıklanmamış ilanlar bir kez okunur, şartlar eşleştirmeye girer',
    () async {
      final store = ListingStore(
        database: await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 10,
            singleInstance: false,
            onCreate: ListingStore.createSchema,
          ),
        ),
      );
      addTearDown(store.close);
      final now = DateTime(2026, 10, 5, 9);
      ListingRecord rec(String id, String source) => ListingRecord(
        url: 'https://example.gov.tr/$id',
        sourceId: source,
        title: 'KURUM - $id',
        category: 'Personel',
        publishedAt: now,
        fetchedAt: now,
      );
      await store.mergeFeed([
        rec('a', kIlanGovSourceId),
        rec('b', kSbbSourceId),
      ]);
      final read = <String>[];
      final done = await backfillConditions(
        store,
        now: now,
        gap: Duration.zero,
        readText: (r) async {
          read.add(r.url);
          return r.sourceId == kSbbSourceId
              ? null
              : 'Adaylar lisans mezunu olmalıdır. KPSS P3 puan türünden en az '
                    '70 puan almış olmak. 35 yaşını doldurmamış olmak.';
        },
      );
      expect(done, 2);
      final a = (await store.allListings()).firstWhere(
        (r) => r.url.endsWith('/a'),
      );
      expect(a.education, 'Lisans');
      expect(a.kpss, 'P3');
      expect(
        SearchCriteria.parse({'version': 2, 'kpssType': 'P93'})
            .match(a.matchingData, now: now.toUtc()),
        CriteriaMatch.noMatch,
      );
      // İkinci tur aynı ilanları yeniden okumaz (metni olmayan SBB dahil).
      expect(
        await backfillConditions(
          store,
          now: now,
          gap: Duration.zero,
          readText: (_) async => fail('tekrar okunmamalı'),
        ),
        0,
      );
    },
  );

  test('kural boş kalırsa yapay zekâ grupları saklanır ve eşleştirmeye girer', () async {
    final store = ListingStore(
      database: await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 10,
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    addTearDown(store.close);
    final now = DateTime(2026, 10, 5, 9);
    await store.mergeFeed([
      ListingRecord(
        url: 'https://www.ilan.gov.tr/ilan/1/x',
        sourceId: kIlanGovSourceId,
        title: 'BELEDİYE — Zabıta',
        category: 'Personel',
        publishedAt: now,
        fetchedAt: now,
        places: const ['İstanbul'],
      ),
    ]);
    var aiCalls = 0;
    await backfillConditions(
      store,
      now: now,
      gap: Duration.zero,
      // Finding education must not prevent AI from completing the other fields.
      readText: (_) async =>
          'Adaylar lisans mezunu olmalıdır. Diğer şartlar ekteki tabloda.',
      aiExtract: (_) async {
        aiCalls++;
        return [
          {
            'label': 'Zabıta Memuru',
            'education': ['Lise'],
            'quotes': {'education': 'ortaöğretim mezunu olmak'},
          },
        ];
      },
    );
    expect(aiCalls, 1);
    final r = (await store.allListings()).single;
    expect(r.aiGroups.single['label'], 'Zabıta Memuru');
    CriteriaMatch m(String edu) => SearchCriteria.parse({
      'version': 2,
      'education': [edu],
    }).match(r.matchingData, now: now.toUtc());
    expect(m('Lise'), CriteriaMatch.match);
    expect(m('Lisans'), CriteriaMatch.noMatch);
  });
}
