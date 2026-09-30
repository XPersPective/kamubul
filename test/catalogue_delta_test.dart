import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late ListingStore store;
  setUp(() async {
    store = ListingStore(
      database: await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 5,
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
  });
  tearDown(() => store.close());
  const url = 'https://kariyerkapisi.gov.tr/IlanDetay?i=7';
  Map<String, Object?> item(int revision, {String title = 'Memur'}) => {
    'id': 'stable',
    'revision': revision,
    'sourceId': 'kariyerkapisi',
    'url': url,
    'title': title,
    'category': 'Personel',
    'updatedAt': '2026-09-30T12:00:00Z',
  };
  CatalogueDeltaPage page(
    int seq,
    int revision, {
    bool deleted = false,
    int? after,
  }) => CatalogueDeltaPage.decode({
    'watermark': seq,
    'appliedThrough': seq,
    'hasMore': false,
    'changes': [
      {
        'seq': seq,
        'id': 'stable',
        'revision': revision,
        'operation': deleted ? 'tombstone' : 'upsert',
        'item': item(revision),
      },
    ],
  }, after: after ?? seq - 1);
  test(
    'delta updates preserve favorite; tombstone keeps saved record and cursor',
    () async {
      await store.applyDeltaPage(page(1, 1), after: 0);
      await store.setSaved(url, true);
      await store.applyDeltaPage(page(2, 2), after: 1);
      expect((await store.allListings()).single.saved, isTrue);
      await store.applyDeltaPage(page(3, 3, deleted: true), after: 2);
      expect((await store.allListings()).single.saved, isTrue);
      expect(await store.remoteCursor(), 3);
    },
  );
  test('invalid second change rolls back data and cursor together', () async {
    final invalid = CatalogueDeltaPage(2, 2, false, [
      CatalogueChange(1, 'stable', 1, false, item(1)),
      const CatalogueChange(2, 'bad', 1, false, {'url': 'http://unsafe'}),
    ]);
    await expectLater(
      store.applyDeltaPage(invalid, after: 0),
      throwsFormatException,
    );
    expect(await store.remoteCursor(), 0);
    expect(await store.allListings(), isEmpty);
    await store.applyDeltaPage(page(1, 1), after: 0);
    await expectLater(
      store.applyDeltaPage(page(1, 1), after: 0),
      throwsFormatException,
    );
    expect(await store.remoteCursor(), 1);
  });
  test(
    'unsaved tombstone disappears; non-monotonic response is rejected',
    () async {
      await store.applyDeltaPage(page(1, 1), after: 0);
      await store.applyDeltaPage(page(2, 2, deleted: true), after: 1);
      expect(await store.allListings(), isEmpty);
      expect(
        () => CatalogueDeltaPage.decode({
          'watermark': 2,
          'appliedThrough': 1,
          'hasMore': true,
          'changes': [],
        }, after: 0),
        throwsA(isA<SnapshotFormatException>()),
      );
    },
  );
  test(
    'v4 to v5 keeps existing favorites and starts delta cursor at zero',
    () async {
      final db = await store.database;
      await db.execute('DROP TABLE remote_catalogue');
      await db.execute('DROP TABLE remote_sync_state');
      await store.mergeFeed([
        ListingRecord(
          url: url,
          sourceId: 'kariyerkapisi',
          title: 'Saved',
          category: 'Personel',
          publishedAt: null,
          fetchedAt: DateTime.now(),
          saved: true,
        ),
      ]);
      await ListingStore.upgradeSchema(db, 4, 5);
      expect(await store.remoteCursor(), 0);
      expect((await store.allListings()).single.saved, isTrue);
    },
  );
}
