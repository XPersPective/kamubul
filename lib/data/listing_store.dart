import 'dart:convert';

import 'package:kamubul_core/data/listing_models.dart';
import 'package:kamubul_core/remote/catalogue_delta.dart';
import 'package:kamubul_core/remote/snapshot.dart' show listingFromJson;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../listings/extract_conditions.dart';
import '../listings/extraction_policy.dart';
import 'dedupe.dart';

export 'package:kamubul_core/data/listing_models.dart';

class ListingStore {
  ListingStore({Database? database}) : _injected = database;

  final Database? _injected;
  Database? _db;

  Future<Database> get database async {
    final injected = _injected;
    if (injected != null) return injected;
    // sqflite aynı veritabanı yolu için tek ortak örnek döndürür; örnek
    // başka bir kullanıcı tarafından kapatılmışsa yeniden açmak gerekir.
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final opened = await openDatabase(
      p.join(await getDatabasesPath(), 'kamubul_listings.db'),
      version: _schemaVersion,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    _db = opened;
    return opened;
  }

  static const int _schemaVersion = 5;

  Future<void> _create(Database db, int version) => createSchema(db, version);

  /// Şemayı oluşturur; testler bellek içi veritabanında aynı şemayı kullanır.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE listings (
        url TEXT PRIMARY KEY,
        sourceId TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        publishedAt INTEGER,
        fetchedAt INTEGER NOT NULL,
        deadline INTEGER,
        quota INTEGER,
        places TEXT NOT NULL DEFAULT '[]',
        kpss TEXT,
        education TEXT,
        maxAge INTEGER,
        quotaType TEXT,
        kpssQuote TEXT,
        educationQuote TEXT,
        maxAgeQuote TEXT,
        quotaTypeQuote TEXT,
        summary TEXT,
        fingerprint TEXT,
        saved INTEGER NOT NULL DEFAULT 0,
        savedAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE saved_searches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        filters TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
    await _createRemoteTables(db);
  }

  static Future<void> _createRemoteTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE remote_catalogue (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, url TEXT, active INTEGER NOT NULL, payload TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE remote_sync_state (id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL)',
    );
    await db.insert('remote_sync_state', {'id': 1, 'cursor': 0});
  }

  /// Şema yükseltmeleri: v1→v2 şart alıntısı sütunları, v2→v3 parmak izi
  /// sütunu, v3→v4 yapay zekâ özeti sütunu. Mevcut veri korunur.
  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE listings ADD COLUMN fingerprint TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE listings ADD COLUMN summary TEXT');
    }
    if (oldVersion < 2) {
      for (final column in [
        'kpssQuote TEXT',
        'educationQuote TEXT',
        'maxAgeQuote TEXT',
        'quotaTypeQuote TEXT',
      ]) {
        await db.execute('ALTER TABLE listings ADD COLUMN $column');
      }
    }
    if (oldVersion < 5 && newVersion >= 5) await _createRemoteTables(db);
  }

  Future<int> remoteCursor() async {
    final db = await database;
    return (await db.query(
          'remote_sync_state',
          columns: ['cursor'],
        )).single['cursor']
        as int;
  }

  /// Upsert/tombstone ve cursor birlikte commit olur; kesilen sayfa tekrar okunabilir.
  Future<void> applyDeltaPage(
    CatalogueDeltaPage page, {
    required int after,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final cursor =
          (await txn.query('remote_sync_state')).single['cursor'] as int;
      if (cursor != after) throw const FormatException('concurrent delta sync');
      for (final change in page.changes) {
        final previous = await txn.query(
          'remote_catalogue',
          where: 'id=?',
          whereArgs: [change.id],
        );
        final old = previous.isEmpty ? null : previous.single;
        if (old != null && (old['revision'] as int) >= change.revision) {
          continue;
        }
        final item = change.item;
        final oldUrl = old?['url'] as String?;
        final url = change.deleted
            ? oldUrl ?? item['url'] as String?
            : item['url'] as String? ?? oldUrl;
        if (change.deleted) {
          if (url != null) {
            await txn.delete(
              'listings',
              where: 'url=? AND saved=0',
              whereArgs: [url],
            );
          }
        } else {
          final summary = (item['summary'] as List? ?? const [])
              .map((s) => s is Map ? s['text'] : s)
              .whereType<String>()
              .take(5)
              .toList();
          final record = listingFromJson({
            ...item,
            'source': item['sourceId'],
            'fetched': item['updatedAt'],
            'published': item['publishedAt'],
            'summary': summary,
          }, fallbackFetchedAt: DateTime.now());
          if (record == null) {
            throw const FormatException('invalid delta record');
          }
          final favorites = await txn.query(
            'listings',
            columns: ['saved', 'savedAt'],
            where: 'url IN (?,?)',
            whereArgs: [oldUrl ?? record.url, record.url],
            orderBy: 'saved DESC, savedAt DESC',
            limit: 1,
          );
          final saved = favorites.isNotEmpty && favorites.single['saved'] == 1;
          final savedMs = favorites.isEmpty
              ? null
              : favorites.single['savedAt'] as int?;
          if (oldUrl != null && oldUrl != record.url) {
            await txn.delete('listings', where: 'url=?', whereArgs: [oldUrl]);
          }
          await txn.insert(
            'listings',
            record
                .copyWith(
                  saved: saved,
                  savedAt: savedMs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(savedMs),
                )
                .toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await txn.insert('remote_catalogue', {
          'id': change.id,
          'revision': change.revision,
          'url': url,
          'active': change.deleted ? 0 : 1,
          'payload': jsonEncode(item),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update('remote_sync_state', {
        'cursor': page.appliedThrough,
      }, where: 'id=1');
    });
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) =>
      upgradeSchema(db, oldVersion, newVersion);

  /// Akıştan gelen ilanları birleştirir: mevcut kayıt korunur, kaydedilen
  /// ilanların saved bayrağı asla sıfırlanmaz. Kaydedilmemiş ve [pruneBefore]
  /// tarihinden eski görülmeyen ilanlar budanır. Dönen değer işlem sonrası
  /// katalogdur.
  Future<void> mergeFeed(
    Iterable<ListingRecord> incoming, {
    DateTime? pruneBefore,
  }) async {
    // Arka plan denetimi ve ön plan yenilemesi aynı veritabanına erişebilir;
    // kilit çakışması tek denemede kaybolabilir.
    try {
      await _mergeFeedInner(incoming, pruneBefore: pruneBefore);
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _mergeFeedInner(incoming, pruneBefore: pruneBefore);
    }
  }

  Future<void> _mergeFeedInner(
    Iterable<ListingRecord> incoming, {
    DateTime? pruneBefore,
  }) async {
    final db = await database;
    final batch = db.batch();
    final pruneLimit =
        pruneBefore ?? DateTime.now().subtract(const Duration(days: 45));
    // Kaynaklar-arasi kopyalar: ayni kurum+son basvuru parmak izine sahip
    // farkli URL'ler yalnizca ilk gelen olarak alinir.
    final known = <String, String?>{};
    for (final row in await db.query(
      'listings',
      columns: ['url', 'fingerprint'],
    )) {
      known[row['url'] as String] = row['fingerprint'] as String?;
    }
    final seenFingerprints = <String>{for (final fp in known.values) ?fp};
    for (final record in incoming) {
      record.fingerprint ??= listingFingerprint(
        title: record.title,
        sourceId: record.sourceId,
        deadline: record.deadline,
      );
      if (!known.containsKey(record.url)) {
        if (seenFingerprints.contains(record.fingerprint)) {
          continue;
        }
        seenFingerprints.add(record.fingerprint!);
      }
      batch.insert(
        'listings',
        record.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'listings',
        {
          'fetchedAt': record.fetchedAt.millisecondsSinceEpoch,
          'title': record.title,
          'category': record.category,
          'fingerprint': record.fingerprint,
          'publishedAt': ?record.publishedAt?.millisecondsSinceEpoch,
          'deadline': ?record.deadline?.millisecondsSinceEpoch,
          'quota': ?record.quota,
          if (record.places.isNotEmpty) 'places': jsonEncode(record.places),
          // Sunucudan gelen doğrulanmış şart alanları ve özet; boş gelen
          // değer var olan ayrıntı değerini silmez.
          'kpss': ?record.kpss,
          'kpssQuote': ?record.kpssQuote,
          'education': ?record.education,
          'educationQuote': ?record.educationQuote,
          'maxAge': ?record.maxAge,
          'maxAgeQuote': ?record.maxAgeQuote,
          'quotaType': ?record.quotaType,
          'quotaTypeQuote': ?record.quotaTypeQuote,
          if (record.summary.isNotEmpty) 'summary': jsonEncode(record.summary),
        },
        where: 'url = ?',
        whereArgs: [record.url],
      );
    }
    await batch.commit(noResult: true);
    await db.delete(
      'listings',
      where: 'saved = 0 AND fetchedAt < ?',
      whereArgs: [pruneLimit.millisecondsSinceEpoch],
    );
  }

  Future<List<ListingRecord>> allListings() async {
    final db = await database;
    final rows = await db.query('listings', orderBy: 'publishedAt DESC, url');
    return rows.map(ListingRecord.fromRow).toList();
  }

  /// Resmî şehir sorgusunun döndürdüğü mevcut ilanlara doğrulanmış yeri ekler.
  Future<void> addVerifiedCity(String city, Iterable<String> urls) async {
    final db = await database;
    for (final url in urls.toSet()) {
      final rows = await db.query(
        'listings',
        columns: ['places'],
        where: 'url = ? AND sourceId = ?',
        whereArgs: [url, 'kariyerkapisi'],
      );
      if (rows.isEmpty) continue;
      final places = ListingRecord.decodePlaces(rows.single['places']);
      if (places.any((place) => placeMatchesCity(place, city))) {
        continue;
      }
      await db.update(
        'listings',
        {
          'places': jsonEncode([...places, city]),
        },
        where: 'url = ? AND sourceId = ?',
        whereArgs: [url, 'kariyerkapisi'],
      );
    }
  }

  Future<void> setSaved(String url, bool saved) async {
    final db = await database;
    await db.update(
      'listings',
      {
        'saved': saved ? 1 : 0,
        'savedAt': saved ? DateTime.now().millisecondsSinceEpoch : null,
      },
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  /// Ayrıntı okumasından gelen yapılandırılmış alanları kayda işler.
  Future<void> applyDetail(
    String url, {
    DateTime? deadline,
    int? quota,
    List<String> places = const [],
  }) async {
    final db = await database;
    await db.update(
      'listings',
      {
        'deadline': ?deadline?.millisecondsSinceEpoch,
        'quota': ?quota,
        if (places.isNotEmpty) 'places': jsonEncode(places),
      },
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  /// Şart çıkarımı sonuçlarını alıntı kanıtlarıyla birlikte yazar.
  /// Alıntısı olmayan ya da politikası kapalı alan yazılmaz; alan
  /// "belirtilmemiş" kalır.
  Future<void> applyConditions(String url, ConditionFields fields) async {
    final claimed = applyExtractionPolicy(fields);
    final db = await database;
    await db.update(
      'listings',
      {
        'kpss': ?claimed.kpssType?.value,
        'kpssQuote': ?claimed.kpssType?.quote,
        'education': ?claimed.education?.value,
        'educationQuote': ?claimed.education?.quote,
        'maxAge': ?claimed.maxAge?.value,
        'maxAgeQuote': ?claimed.maxAge?.quote,
        'quotaType': ?claimed.quotaType?.value,
        'quotaTypeQuote': ?claimed.quotaType?.quote,
      },
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  Future<List<SavedSearch>> savedSearches() async {
    final db = await database;
    final rows = await db.query('saved_searches', orderBy: 'createdAt DESC');
    return rows.map(SavedSearch.fromRow).toList();
  }

  Future<SavedSearch> addSavedSearch(SavedSearch search) async {
    final db = await database;
    final id = await db.insert('saved_searches', search.toRow());
    return SavedSearch(
      id: id,
      name: search.name,
      filters: search.filters,
      createdAt: search.createdAt,
    );
  }

  Future<void> updateSavedSearch(SavedSearch search) async {
    if (search.id == null) return;
    final db = await database;
    await db.update(
      'saved_searches',
      search.toRow(),
      where: 'id = ?',
      whereArgs: [search.id],
    );
  }

  Future<void> deleteSavedSearch(int id) async {
    final db = await database;
    await db.delete('saved_searches', where: 'id = ?', whereArgs: [id]);
  }

  /// Yalnızca enjekte edilen (test) veritabanını kapatır. Uygulama
  /// veritabanı sqflite'ın yol başına tek ortak örneğidir; kapatmak
  /// arayüzün elindeki diğer mağazaları database_closed ile bozar.
  Future<void> close() async {
    await _injected?.close();
    _db = null;
  }
}
