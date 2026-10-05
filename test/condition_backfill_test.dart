import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/condition_backfill.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('ayıklanmamış ilanlar bir kez okunur, şartlar eşleştirmeye girer', () async {
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
    final a = (await store.allListings()).firstWhere((r) => r.url.endsWith('/a'));
    expect(a.education, 'Lisans');
    expect(a.kpss, 'P3');
    expect(
      SearchCriteria.parse({'version': 2, 'kpssType': 'P93'})
          .match(a.matchingData, now: now.toUtc()),
      CriteriaMatch.noMatch,
    );
    // İkinci tur aynı ilanları yeniden okumaz (metni olmayan SBB dahil).
    expect(
      await backfillConditions(store, now: now, gap: Duration.zero,
          readText: (_) async => fail('tekrar okunmamalı')),
      0,
    );
  });

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
      readText: (_) async => 'Kadro ve şartlar ekteki tabloda.',
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
