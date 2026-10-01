import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/data/remote_sync.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> item(String id, {int revision = 1}) => {
  'id': id,
  'revision': revision,
  'url': 'https://example.gov.tr/$id',
  'title': 'İlan $id',
  'sourceId': 'kariyerkapisi',
  'category': 'Personel',
  'updatedAt': '2026-10-01T08:00:00Z',
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late ListingStore store;
  setUp(() async {
    store = ListingStore(
      database: await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 7,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
  });
  tearDown(() => store.close());
  final now = DateTime.utc(2026, 10, 1);
  Future<void> seed() async {
    await store.applyDeltaPage(
      CatalogueDeltaPage(2, 2, false, [
        CatalogueChange(1, 'old', 9, false, item('old', revision: 9)),
        CatalogueChange(2, 'saved', 9, false, item('saved', revision: 9)),
      ]),
      after: 0,
    );
    await store.setSaved('https://example.gov.tr/saved', true);
    await store.addSavedSearch(
      SavedSearch(id: null, name: 'Aramam', filters: const {}, createdAt: now),
    );
  }

  test(
    'staging resumes and publishes atomically; missing favorite stays inactive',
    () async {
      await seed();
      await store.beginBootstrap(latest: 4, oldest: 3);
      await store.stageCataloguePage(
        CataloguePage(4, [item('a')], 'a'),
        after: '',
      );
      expect(await store.remoteCursor(), 2);
      expect((await store.allListings()).map((x) => x.title).toSet(), {
        'İlan old',
        'İlan saved',
      });
      final reopened = ListingStore(database: await store.database);
      final pending = await reopened.beginBootstrap(latest: 5, oldest: 3);
      expect(pending, (watermark: 4, after: 'a'));
      await reopened.stageCataloguePage(
        CataloguePage(4, [item('b')], null),
        after: 'a',
      );
      expect(await store.remoteCursor(), 4);
      final listings = await store.allListings();
      expect(listings.map((x) => x.title).toSet(), {
        'İlan a',
        'İlan b',
        'İlan saved',
      });
      final saved = listings.singleWhere((x) => x.saved);
      expect(saved.criteriaListing!['active'], false);
      expect((await store.savedSearches()).single.name, 'Aramam');
      expect((await store.remoteMetadata()).pendingBootstrap, false);
      // A reset server may reuse an older ID with a lower revision.
      await store.applyDeltaPage(
        CatalogueDeltaPage(5, 5, false, [
          CatalogueChange(5, 'saved', 1, false, item('saved')),
        ]),
        after: 4,
      );
      expect(
        (await store.allListings())
            .singleWhere((x) => x.saved)
            .criteriaListing!['active'],
        true,
      );
    },
  );

  test(
    'empty snapshot reconciles remote rows without deleting personal data',
    () async {
      await seed();
      await store.beginBootstrap(latest: 0, oldest: 0);
      await store.stageCataloguePage(
        const CataloguePage(0, [], null),
        after: '',
      );
      expect(await store.remoteCursor(), 0);
      expect((await store.allListings()).single.saved, true);
      expect(
        (await store.allListings()).single.criteriaListing!['active'],
        false,
      );
      expect(await store.savedSearches(), hasLength(1));
    },
  );

  test(
    'failed final transaction preserves visible cache and staging cursor',
    () async {
      await seed();
      await store.beginBootstrap(latest: 4, oldest: 3);
      await store.stageCataloguePage(
        CataloguePage(4, [item('a')], 'a'),
        after: '',
      );
      await expectLater(
        store.stageCataloguePage(
          CataloguePage(4, [
            {...item('b'), 'sourceId': null},
          ], null),
          after: 'a',
        ),
        throwsFormatException,
      );
      expect(await store.remoteCursor(), 2);
      expect(await store.allListings(), hasLength(2));
      expect(await store.beginBootstrap(latest: 4, oldest: 3), (
        watermark: 4,
        after: 'a',
      ));
      await store.stageCataloguePage(
        const CataloguePage(4, [], null),
        after: 'a',
      );
      expect((await store.allListings()).map((x) => x.title).toSet(), {
        'İlan a',
        'İlan saved',
      });
    },
  );

  test(
    'concurrent delta invalidates staging instead of overwriting newer data',
    () async {
      await seed();
      await store.beginBootstrap(latest: 4, oldest: 3);
      await store.stageCataloguePage(
        CataloguePage(4, [item('a')], 'a'),
        after: '',
      );
      await store.applyDeltaPage(
        const CatalogueDeltaPage(3, 3, false, []),
        after: 2,
      );
      await expectLater(
        store.stageCataloguePage(const CataloguePage(4, [], null), after: 'a'),
        throwsFormatException,
      );
      expect(await store.remoteCursor(), 3);
      expect(await store.beginBootstrap(latest: 5, oldest: 3), (
        watermark: 5,
        after: '',
      ));
      expect((await (await store.database).query('remote_bootstrap')), isEmpty);
    },
  );

  test('over 20 pages resumes next refresh without early success or cache replacement', () async {
    var calls = 0;
    final remote = RemoteCatalogueClient(
      baseUrl: Uri.parse('https://kamubul.example'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v2/meta') {
          return http.Response(
            jsonEncode({
              'schemaVersion': 2,
              'taxonomyVersion': 1,
              'latestSeq': 25,
              'oldestRetainedSeq': 1,
              'sources': [],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/v2/listings');
        expect(request.url.queryParameters['watermark'], '25');
        final after = request.url.queryParameters['after']!;
        final n = after.isEmpty ? 1 : int.parse(after) + 1;
        final id = '$n'.padLeft(3, '0');
        calls++;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'watermark': 25,
              'items': [item(id)],
              'next': n == 25 ? null : id,
            }),
          ),
          200,
        );
      }),
    );
    await expectLater(
      syncRemoteV2Catalogue(store: store, client: remote, now: now),
      throwsA(isA<RemoteCatalogueException>()),
    );
    expect(calls, 20);
    expect(await store.remoteCursor(), 0);
    expect(await store.allListings(), isEmpty);
    expect((await store.remoteMetadata()).lastSuccess, isNull);
    await syncRemoteV2Catalogue(store: store, client: remote, now: now);
    expect(calls, 25);
    expect(await store.remoteCursor(), 25);
    expect(await store.allListings(), hasLength(25));
    expect((await store.remoteMetadata()).lastSuccess!.toUtc(), now);
  });

  test(
    'pinned snapshot survives new metadata then catches up with delta',
    () async {
      await seed();
      var latest = 4;
      var fail = true;
      final requests = <String>[];
      final remote = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://kamubul.example'),
        client: MockClient((request) async {
          final path = request.url.path;
          final after = request.url.queryParameters['after'];
          requests.add('$path/$after');
          Object body;
          if (path == '/api/v2/meta') {
            body = {
              'schemaVersion': 2,
              'taxonomyVersion': 1,
              'latestSeq': latest,
              'oldestRetainedSeq': 4,
              'sources': [],
            };
          } else if (path == '/api/v2/listings') {
            expect(request.url.queryParameters['watermark'], '4');
            if (after == 'a' && fail) return http.Response('', 503);
            body = {
              'watermark': 4,
              'items': [item(after == '' ? 'a' : 'b')],
              'next': after == '' ? 'a' : null,
            };
          } else {
            expect(path, '/api/v2/changes');
            expect(after, '4');
            expect(request.url.queryParameters['watermark'], '5');
            body = {
              'watermark': 5,
              'appliedThrough': 5,
              'hasMore': false,
              'changes': [
                {
                  'seq': 5,
                  'id': 'b',
                  'revision': 2,
                  'operation': 'upsert',
                  'item': item('b', revision: 2),
                },
              ],
            };
          }
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );
      await expectLater(
        syncRemoteV2Catalogue(store: store, client: remote, now: now),
        throwsA(isA<RemoteCatalogueException>()),
      );
      expect(await store.remoteCursor(), 2);
      expect(await store.allListings(), hasLength(2));
      latest = 5;
      fail = false;
      await syncRemoteV2Catalogue(store: store, client: remote, now: now);
      expect(requests.where((x) => x == '/api/v2/listings/'), hasLength(1));
      expect(requests.last, '/api/v2/changes/4');
      expect(await store.remoteCursor(), 5);
      final b = (await (await store.database).query(
        'remote_catalogue',
        where: 'id=?',
        whereArgs: ['b'],
      )).single;
      expect(b['revision'], 2);
    },
  );

  test(
    'schema6 to7 preserves cursor metadata favorites and searches',
    () async {
      await seed();
      await store.saveRemoteMetadata('{"schemaVersion":2}', '"kept"', now);
      final db = await store.database;
      await db.execute('DROP TABLE remote_bootstrap');
      await db.execute('ALTER TABLE remote_sync_state RENAME TO old_sync');
      await db.execute(
        'CREATE TABLE remote_sync_state (id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL, metadata TEXT, metadata_etag TEXT, last_success INTEGER)',
      );
      await db.execute(
        'INSERT INTO remote_sync_state SELECT id,cursor,metadata,metadata_etag,last_success FROM old_sync',
      );
      await db.execute('DROP TABLE old_sync');
      await ListingStore.upgradeSchema(db, 6, 7);
      expect(await store.remoteCursor(), 2);
      expect((await store.remoteMetadata()).etag, '"kept"');
      expect((await store.remoteMetadata()).pendingBootstrap, false);
      expect((await store.allListings()).where((x) => x.saved), hasLength(1));
      expect(await store.savedSearches(), hasLength(1));
      await store.beginBootstrap(latest: 4, oldest: 3);
      await store.stageCataloguePage(
        const CataloguePage(4, [], null),
        after: '',
      );
      expect(await store.remoteCursor(), 4);
    },
  );

  test('snapshot parser rejects changing watermark, duplicate IDs and non-progress', () {
    for (final raw in [
      {
        'watermark': 3,
        'items': [item('a')],
        'next': null,
      },
      {
        'watermark': 4,
        'items': [item('a'), item('a')],
        'next': null,
      },
      {
        'watermark': 4,
        'items': [item('a')],
        'next': 'b',
      },
      {'watermark': 4, 'items': [], 'next': 'a'},
    ]) {
      expect(
        () => CataloguePage.decode(raw, watermark: 4),
        throwsA(isA<SnapshotFormatException>()),
      );
    }
  });
}
