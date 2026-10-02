import 'dart:convert';
import 'dart:io';

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

  test('v5→v6 metadata göçü cursor, favori ve aramaları korur', () async {
    await store.applyDeltaPage(page(1, 1), after: 0);
    await store.setSaved(url, true);
    await store.addSavedSearch(
      SavedSearch(
        id: null,
        name: 'Kişisel',
        filters: const {'kpss': 'P3'},
        createdAt: DateTime(2026),
      ),
    );
    final db = await store.database;
    // Exact pre-v6 sync table; remaining tables keep their real cached rows.
    await db.execute('DROP TABLE remote_sync_state');
    await db.execute(
      'CREATE TABLE remote_sync_state (id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL)',
    );
    await db.insert('remote_sync_state', {'id': 1, 'cursor': 1});
    await ListingStore.upgradeSchema(db, 5, 6);
    expect(await store.remoteCursor(), 1);
    expect((await store.allListings()).single.saved, isTrue);
    expect((await store.savedSearches()).single.name, 'Kişisel');
    expect((await store.remoteMetadata()).metadata, isNull);
    final now = DateTime(2026, 10, 1);
    await store.saveRemoteMetadata('{"schemaVersion":2}', '"etag"', now);
    final reopened = ListingStore(database: db);
    expect((await reopened.remoteMetadata()).etag, '"etag"');
    expect((await reopened.remoteMetadata()).lastSuccess, now);
    await expectLater(
      store.saveRemoteMetadata('new', '"wrong"', now, expectedCursor: 2),
      throwsFormatException,
    );
    expect((await reopened.remoteMetadata()).etag, '"etag"');
  });

  test(
    'Worker ortak corpus SQLite projeksiyonundan da aynı sonucu verir',
    () async {
      final corpus = jsonDecode(
        File('contracts/criteria-v2.json').readAsStringSync(),
      ) as List;
      var seq = 0;
      for (final raw in corpus) {
        final row = raw as Map;
        final id = 'corpus-${++seq}';
        final data = <String, Object?>{
          ...item(1),
          ...Map<String, Object?>.from(row['listing'] as Map),
          'id': id,
          'url': 'https://kariyerkapisi.gov.tr/IlanDetay?i=$seq',
        };
        await store.applyDeltaPage(
          CatalogueDeltaPage(seq, seq, false, [
            CatalogueChange(seq, id, 1, false, data),
          ]),
          after: seq - 1,
        );
        final record = (await store.allListings()).firstWhere(
          (r) => r.url == data['url'],
        );
        final criteria = row['legacy'] != null
            ? SearchCriteria.fromLegacy(
                Map<String, String>.from(row['legacy'] as Map),
              )
            : SearchCriteria.parse(
                Map<String, Object?>.from(row['criteria'] as Map),
              );
        final search = SavedSearch(
          id: 1,
          name: 'Corpus',
          filters: const {},
          criteria: criteria,
          createdAt: DateTime(2026),
        );
        final outcome = search.matchListing(
          record,
          now: DateTime.utc(2026, 9, 30, 12),
        );
        expect(
          outcome == CriteriaMatch.noMatch ? 'no_match' : outcome.name,
          row['expected'],
          reason: '${row['name']}',
        );
      }
    },
  );
  test('canonical kadrolar cache okumasında ayrıdır; UI ve bildirim aynı puan sınırını kullanır', () async {
    final data = {
      ...item(1),
      'active': true,
      'publishedAt': '2026-09-29T12:00:00Z',
      'requirementGroups': [
        {
          'cities': ['Ankara'],
          'occupations': ['Mühendis'],
          'education': ['Lisans'],
          'kpssStatus': 'required',
          'kpssType': 'P3',
          'kpssScore': 70,
          'kpssYear': 2024,
          'ageStatus': 'known',
          'maxAge': 35,
        },
        {
          'cities': ['İzmir'],
          'occupations': ['Mimar'],
          'education': ['Lisans'],
          'kpssStatus': 'required',
          'kpssType': 'P3',
          'kpssScore': 80,
          'ageStatus': 'known',
          'maxAge': 30,
        },
      ],
      'documentText': 'large source document',
    };
    await store.applyDeltaPage(
      CatalogueDeltaPage(1, 1, false, [
        CatalogueChange(1, 'stable', 1, false, data),
      ]),
      after: 0,
    );
    final record = (await store.allListings()).single;
    expect(
      record.criteriaListing!['requirementGroups'],
      data['requirementGroups'],
    );
    expect(record.criteriaListing!.containsKey('documentText'), isFalse);
    SavedSearch candidate(num score, String city) => SavedSearch(
      id: 1,
      name: 'Kişisel',
      filters: const {},
      createdAt: DateTime(2026),
      criteria: SearchCriteria.parse({
        'version': 2,
        'cities': [city],
        'occupations': ['Mühendis'],
        'age': 34,
        'ageAsOf': '2026-09-29',
        'kpssType': 'P3',
        'kpssScore': score,
        'kpssYear': 2024,
      }),
    );
    final now = DateTime.utc(2026, 9, 30, 12);
    expect(
      candidate(70, 'Ankara').matchListing(record, now: now),
      CriteriaMatch.match,
    );
    expect(
      candidate(69.99, 'Ankara').matchListing(record, now: now),
      CriteriaMatch.noMatch,
    );
    expect(
      candidate(90, 'İzmir').matchListing(record, now: now),
      CriteriaMatch.noMatch,
      reason: 'Farklı kadroların şartları birleştirilmez',
    );
    expect(
      decideAlerts(
        search: candidate(69.99, 'Ankara'),
        listings: [record],
        previouslySeen: {},
        config: AlertConfig(
          now: now,
          quietStartHour: 22,
          quietEndHour: 8,
          maxInstantPerDay: 6,
          instantSentToday: 0,
          digestSentDay: null,
        ),
      ).notifications,
      isEmpty,
    );
    await store.setSaved(record.url, true);
    await store.applyDeltaPage(page(2, 2, deleted: true), after: 1);
    final removed = (await store.allListings()).single;
    expect(removed.saved, isTrue);
    expect(
      candidate(90, 'Ankara').matchListing(removed, now: now),
      CriteriaMatch.noMatch,
    );
  });
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
