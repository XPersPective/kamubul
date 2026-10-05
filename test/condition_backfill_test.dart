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
}
