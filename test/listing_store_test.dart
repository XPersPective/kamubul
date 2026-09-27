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
      record('a', fetchedAt: DateTime(2026, 9, 28), publishedAt: DateTime(2026, 9, 21)),
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
    await store.mergeFeed(
      [record('yeni', fetchedAt: DateTime(2026, 9, 27))],
      pruneBefore: DateTime(2026, 9, 26),
    );
    final items = await store.allListings();
    expect(items.map((item) => item.url), containsAll(['kayitli', 'yeni']));
    expect(items.map((item) => item.url), isNot(contains('eski')));
    expect(items.firstWhere((item) => item.url == 'kayitli').saved, isTrue);
    await store.close();
  });

  test('ayrıntı alanları kayda işler ve yeniden açılışta kalır', () async {
    final dbPath = '${DateTime.now().microsecondsSinceEpoch}.db';
    final store = ListingStore(
      database: await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 1, onCreate: ListingStore.createSchema),
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
        options: OpenDatabaseOptions(version: 1, onCreate: ListingStore.createSchema),
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

  test('kayıtlı arama ekleme, güncelleme, silme ve bozuk süzgeç okuma', () async {
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
  });

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
}
