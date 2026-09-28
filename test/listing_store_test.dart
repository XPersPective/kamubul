import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<ListingStore> freshStore() async {
    final store = ListingStore(
      database: await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          // ffi ':memory:' yolunu tek örnek olarak paylaşır; her test kendi
          // boş bellek veritabanını almalı.
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    return store;
  }

  ListingRecord record(
    String url, {
    DateTime? fetchedAt,
    DateTime? publishedAt,
    bool saved = false,
  }) => ListingRecord(
    url: url,
    sourceId: 'kariyerkapisi',
    title: 'İlan $url',
    category: 'Personel',
    publishedAt: publishedAt ?? DateTime(2026, 9, 20),
    fetchedAt: fetchedAt ?? DateTime(2026, 9, 27),
    saved: saved,
  );

  test('birleştirme ilanları ekler ve yenilemede günceller', () async {
    final store = await freshStore();
    await store.mergeFeed([record('a')]);
    var items = await store.allListings();
    expect(items, hasLength(1));
    await store.mergeFeed([
      record(
        'a',
        fetchedAt: DateTime(2026, 9, 28),
        publishedAt: DateTime(2026, 9, 21),
      ),
      record('b'),
    ]);
    items = await store.allListings();
    expect(items, hasLength(2));
    final a = items.firstWhere((item) => item.url == 'a');
    expect(a.fetchedAt, DateTime(2026, 9, 28));
    expect(a.publishedAt, DateTime(2026, 9, 21));
    await store.close();
  });

  test('kaydedilen ilan yenilemede ve budamada korunur', () async {
    final store = await freshStore();
    await store.mergeFeed([
      record('kayitli'),
      // Kaydedilmemiş ve uzun süredir görülmeyen ilan: budanacak.
      record('eski', fetchedAt: DateTime(2026, 6, 1)),
    ]);
    await store.setSaved('kayitli', true);
    // Budama sınırı: 2026-09-26'dan eski görülen kaydedilmemiş ilanlar silinir.
    await store.mergeFeed([
      record('yeni', fetchedAt: DateTime(2026, 9, 27)),
    ], pruneBefore: DateTime(2026, 9, 26));
    final items = await store.allListings();
    expect(items.map((item) => item.url), containsAll(['kayitli', 'yeni']));
    expect(items.map((item) => item.url), isNot(contains('eski')));
    expect(items.firstWhere((item) => item.url == 'kayitli').saved, isTrue);
    await store.close();
  });

  test('akıştan gelen yeni alanlar kayıtlı ilanda da güncellenir', () async {
    final store = await freshStore();
    await store.mergeFeed([record('a')]);
    await store.setSaved('a', true);
    final refreshed = record(
      'a',
      fetchedAt: DateTime(2026, 9, 28),
    ).copyWith(deadline: DateTime(2026, 10, 10), quota: 12, places: ['ANKARA']);
    await store.mergeFeed([refreshed]);
    final result = (await store.allListings()).single;
    expect(result.saved, isTrue);
    expect(result.deadline, DateTime(2026, 10, 10));
    expect(result.quota, 12);
    expect(result.places, ['ANKARA']);
    await store.close();
  });

  test('ayrıntı alanları kayda işler ve yeniden açılışta kalır', () async {
    final dbPath = '${DateTime.now().microsecondsSinceEpoch}.db';
    final store = ListingStore(
      database: await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    await store.mergeFeed([record('detay')]);
    await store.applyDetail(
      'detay',
      deadline: DateTime(2026, 10, 1),
      quota: 12,
      places: const ['ANKARA', 'İZMİR'],
    );
    await store.close();
    // Yeniden açılış: veri ve şema kalıcı olmalı.
    final reopened = ListingStore(
      database: await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    final items = await reopened.allListings();
    expect(items.single.quota, 12);
    expect(items.single.deadline, DateTime(2026, 10, 1));
    expect(items.single.places, ['ANKARA', 'İZMİR']);
    expect(items.single.expired, isFalse);
    await reopened.close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('bozuk yerler kaydı uygulamayı çökertmez', () async {
    final store = await freshStore();
    final db = await store.database;
    await db.insert('listings', {
      'url': 'bozuk',
      'sourceId': 'kariyerkapisi',
      'title': 'Bozuk',
      'category': '',
      'fetchedAt': DateTime(2026, 9, 27).millisecondsSinceEpoch,
      'places': '{kesik json',
      'saved': 0,
    });
    final items = await store.allListings();
    expect(items.single.places, isEmpty);
    await store.close();
  });

  test('önbellekte tekrarlanan yer tek gösterilir', () async {
    final store = await freshStore();
    await store.mergeFeed([
      record('yer').copyWith(
        places: [
          'BAKANLIK MERKEZ TEŞKİLATI / BAKANLIK MERKEZ TEŞKİLATI',
          'BAKANLIK MERKEZ TEŞKİLATI',
        ],
      ),
    ]);
    expect((await store.allListings()).single.places, [
      'BAKANLIK MERKEZ TEŞKİLATI',
    ]);
    await store.close();
  });

  test(
    'kayıtlı arama ekleme, güncelleme, silme ve bozuk süzgeç okuma',
    () async {
      final store = await freshStore();
      final created = await store.addSavedSearch(
        SavedSearch(
          id: null,
          name: 'Ankara P3',
          filters: const {'sehir': 'ANKARA', 'kpss': 'P3'},
          createdAt: DateTime(2026, 9, 27),
        ),
      );
      expect(created.id, isNotNull);
      await store.updateSavedSearch(created.copyWith(name: 'Ankara P3 Lisans'));
      var searches = await store.savedSearches();
      expect(searches.single.name, 'Ankara P3 Lisans');
      expect(searches.single.filters['sehir'], 'ANKARA');
      await store.deleteSavedSearch(created.id!);
      expect(await store.savedSearches(), isEmpty);
      await store.close();
    },
  );

  test(
    'v1 veritabanı v2ye göçerken veri korunur ve alıntı sütunları eklenir',
    () async {
      final dbPath = '${DateTime.now().microsecondsSinceEpoch}-mig.db';
      // v1 şemasını elle kur, örnek kayıt yaz.
      final v1 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
          CREATE TABLE listings (
            url TEXT PRIMARY KEY, sourceId TEXT NOT NULL, title TEXT NOT NULL,
            category TEXT NOT NULL, publishedAt INTEGER, fetchedAt INTEGER NOT NULL,
            deadline INTEGER, quota INTEGER, places TEXT NOT NULL DEFAULT '[]',
            kpss TEXT, education TEXT, maxAge INTEGER, quotaType TEXT,
            saved INTEGER NOT NULL DEFAULT 0, savedAt INTEGER
          )
        ''');
            await db.execute('''
          CREATE TABLE saved_searches (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            filters TEXT NOT NULL, createdAt INTEGER NOT NULL
          )
        ''');
          },
        ),
      );
      await v1.insert('listings', {
        'url': 'eski',
        'sourceId': 'kariyerkapisi',
        'title': 'Eski kayıt',
        'category': '',
        'fetchedAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'saved': 1,
      });
      await v1.close();
      // v2 ile yeniden aç: upgradeSchema çalışmalı, veri durmalı.
      final v2 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: ListingStore.createSchema,
          onUpgrade: ListingStore.upgradeSchema,
        ),
      );
      final rows = await v2.query('listings');
      expect(rows.single['title'], 'Eski kayıt');
      expect(rows.single['kpssQuote'], isNull);
      final columns = await v2.rawQuery('PRAGMA table_info(listings)');
      expect(
        columns.map((c) => c['name']),
        containsAll([
          'kpssQuote',
          'educationQuote',
          'maxAgeQuote',
          'quotaTypeQuote',
        ]),
      );
      await v2.close();
      await databaseFactory.deleteDatabase(dbPath);
    },
  );

  test(
    'v2 veritabanı v3e göçerken veri korunur ve parmak izi sütunu eklenir',
    () async {
      final dbPath = '${DateTime.now().microsecondsSinceEpoch}-mig3.db';
      // v2 şemasını elle kur (alıntı sütunları var, parmak izi yok), örnek kayıt yaz.
      final v2 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
          CREATE TABLE listings (
            url TEXT PRIMARY KEY, sourceId TEXT NOT NULL, title TEXT NOT NULL,
            category TEXT NOT NULL, publishedAt INTEGER, fetchedAt INTEGER NOT NULL,
            deadline INTEGER, quota INTEGER, places TEXT NOT NULL DEFAULT '[]',
            kpss TEXT, education TEXT, maxAge INTEGER, quotaType TEXT,
            kpssQuote TEXT, educationQuote TEXT, maxAgeQuote TEXT, quotaTypeQuote TEXT,
            saved INTEGER NOT NULL DEFAULT 0, savedAt INTEGER
          )
        ''');
            await db.execute('''
          CREATE TABLE saved_searches (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            filters TEXT NOT NULL, createdAt INTEGER NOT NULL
          )
        ''');
          },
        ),
      );
      await v2.insert('listings', {
        'url': 'eski',
        'sourceId': 'kariyerkapisi',
        'title': 'Eski kayıt',
        'category': '',
        'fetchedAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'saved': 1,
      });
      await v2.close();
      // v3 ile yeniden aç: fingerprint sütunu eklenmeli, veri durmalı.
      final v3 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: ListingStore.createSchema,
          onUpgrade: ListingStore.upgradeSchema,
        ),
      );
      final rows = await v3.query('listings');
      expect(rows.single['title'], 'Eski kayıt');
      expect(rows.single['fingerprint'], isNull);
      final columns = await v3.rawQuery('PRAGMA table_info(listings)');
      expect(columns.map((c) => c['name']), contains('fingerprint'));
      await v3.close();
      await databaseFactory.deleteDatabase(dbPath);
    },
  );

  test('bozuk kayıtlı arama süzgeci boş okunur', () async {
    final search = SavedSearch.fromRow({
      'id': 1,
      'name': 'x',
      'filters': '{bozuk',
      'createdAt': 0,
    });
    expect(search.filters, isEmpty);
    expect(search.name, 'x');
    // Doğrudan kurulumda id null verilebilir (yeni kayıt).
    final pending = SavedSearch(
      id: null,
      name: 'yeni',
      filters: const {'sehir': 'ANKARA'},
      createdAt: DateTime(2026, 9, 27),
    );
    expect(pending.id, isNull);
  });

  test(
    'resmî şehir eşleşmesi mevcut yerlere eklenir, başka ilana taşmaz',
    () async {
      final store = await freshStore();
      await store.mergeFeed([record('a'), record('b')]);
      await store.addVerifiedCity('Ankara', ['a', 'yok']);
      await store.addVerifiedCity('İzmir', ['a']);
      await store.addVerifiedCity('Ankara', ['a']);
      final listings = await store.allListings();
      expect(listings.firstWhere((item) => item.url == 'a').places, [
        'Ankara',
        'İzmir',
      ]);
      expect(listings.firstWhere((item) => item.url == 'b').places, isEmpty);
      await store.close();
    },
  );
}
