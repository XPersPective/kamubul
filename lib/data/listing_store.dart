import 'dart:convert';

import 'package:kamubul_core/data/listing_models.dart';
import 'package:kamubul_core/listings/extract_conditions.dart';
import 'package:kamubul_core/listings/extraction_policy.dart';
import 'package:kamubul_core/remote/catalogue_delta.dart';
import 'package:kamubul_core/remote/snapshot.dart' show listingFromJson;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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

  static const int _schemaVersion = 11;

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
        savedAt INTEGER,
        conditionsCheckedAt INTEGER,
        aiGroups TEXT,
        pendingConditionText TEXT
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
    await _addRemoteMetadata(db);
    await _addRemoteBootstrap(db);
    await _addRemoteOrigin(db);
    await _addRemoteDetails(db);
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
    if (oldVersion < 6 && newVersion >= 6) await _addRemoteMetadata(db);
    if (oldVersion < 7 && newVersion >= 7) await _addRemoteBootstrap(db);
    if (oldVersion < 8 && newVersion >= 8) await _addRemoteOrigin(db);
    if (oldVersion < 9 && newVersion >= 9) await _addRemoteDetails(db);
    if (oldVersion < 10 && newVersion >= 10) {
      await db.execute(
        'ALTER TABLE listings ADD COLUMN conditionsCheckedAt INTEGER',
      );
      await db.execute('ALTER TABLE listings ADD COLUMN aiGroups TEXT');
    }
    if (oldVersion < 11 && newVersion >= 11) {
      await db.execute(
        'ALTER TABLE listings ADD COLUMN pendingConditionText TEXT',
      );
      // Recheck derived results against the corrected server evidence contract.
      await db.execute(
        'UPDATE listings SET conditionsCheckedAt=NULL, aiGroups=NULL',
      );
    }
  }

  static Future<void> _addRemoteDetails(Database db) async {
    await db.execute(
      'CREATE TABLE remote_details (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, payload TEXT NOT NULL, touched INTEGER NOT NULL, epoch INTEGER NOT NULL)',
    );
    await db.execute(
      'ALTER TABLE remote_sync_state ADD COLUMN detail_epoch INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _addRemoteOrigin(Database db) async {
    await db.execute('ALTER TABLE remote_sync_state ADD COLUMN origin TEXT');
    await db.execute(
      'ALTER TABLE remote_sync_state ADD COLUMN generation INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// Bind before network; a new server resets transport state, never visible bookmarks.
  Future<int> bindRemoteOrigin(String origin) async =>
      (await database).transaction((txn) async {
        final row = (await txn.query('remote_sync_state')).single;
        final generation = row['generation'] as int;
        if (row['origin'] == origin) return generation;
        await txn.delete('remote_bootstrap');
        await txn.delete('remote_details');
        await txn.update('remote_sync_state', {
          'origin': origin,
          'generation': generation + 1,
          'detail_epoch': (row['detail_epoch'] as int) + 1,
          'cursor': 0,
          'metadata': null,
          'metadata_etag': null,
          'last_success': null,
          'bootstrap_watermark': null,
          'bootstrap_after': null,
          'bootstrap_base_cursor': null,
        }, where: 'id=1');
        return generation + 1;
      });

  static void _checkRemoteGeneration(
    Map<String, Object?> state,
    int? expected,
  ) {
    if (expected != null && state['generation'] != expected) {
      throw const FormatException('remote origin changed');
    }
  }

  static Future<void> _addRemoteMetadata(Database db) async {
    for (final column in [
      'metadata TEXT',
      'metadata_etag TEXT',
      'last_success INTEGER',
    ]) {
      await db.execute('ALTER TABLE remote_sync_state ADD COLUMN $column');
    }
  }

  Future<
    ({
      String? metadata,
      String? etag,
      DateTime? lastSuccess,
      bool pendingBootstrap,
    })
  >
  remoteMetadata({int? expectedGeneration}) async {
    final row = (await (await database).query('remote_sync_state')).single;
    _checkRemoteGeneration(row, expectedGeneration);
    return (
      pendingBootstrap: row['bootstrap_watermark'] != null,
      metadata: row['metadata'] as String?,
      etag: row['metadata_etag'] as String?,
      lastSuccess: row['last_success'] is int
          ? DateTime.fromMillisecondsSinceEpoch(row['last_success'] as int)
          : null,
    );
  }

  Future<void> saveRemoteMetadata(
    String metadata,
    String? etag,
    DateTime succeededAt, {
    int? expectedCursor,
    int? expectedGeneration,
  }) async {
    final changed = await (await database).update(
      'remote_sync_state',
      {
        'metadata': metadata,
        'metadata_etag': etag,
        'last_success': succeededAt.millisecondsSinceEpoch,
      },
      where:
          'id=1${expectedCursor == null ? '' : ' AND cursor=?'}${expectedGeneration == null ? '' : ' AND generation=?'}',
      whereArgs: [?expectedCursor, ?expectedGeneration],
    );
    if (changed != 1) throw const FormatException('concurrent metadata sync');
  }

  static Future<void> _addRemoteBootstrap(Database db) async {
    await db.execute(
      'CREATE TABLE remote_bootstrap (id TEXT PRIMARY KEY, url TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    await db.execute(
      'ALTER TABLE remote_sync_state ADD COLUMN bootstrap_watermark INTEGER',
    );
    await db.execute(
      'ALTER TABLE remote_sync_state ADD COLUMN bootstrap_after TEXT',
    );
    await db.execute(
      'ALTER TABLE remote_sync_state ADD COLUMN bootstrap_base_cursor INTEGER',
    );
  }

  Future<({int watermark, String after})> beginBootstrap({
    required int latest,
    required int oldest,
    int? expectedGeneration,
  }) async {
    return (await database).transaction((txn) async {
      final state = (await txn.query('remote_sync_state')).single;
      _checkRemoteGeneration(state, expectedGeneration);
      final watermark = state['bootstrap_watermark'] as int?;
      if (watermark != null &&
          watermark <= latest &&
          watermark >= oldest &&
          state['bootstrap_base_cursor'] == state['cursor']) {
        return (
          watermark: watermark,
          after: state['bootstrap_after'] as String,
        );
      }
      await txn.delete('remote_bootstrap');
      // A new snapshot may represent a reset server. Reject old in-flight details;
      // details read after this pin remain separate from the frozen catalogue.
      if ((state['cursor'] as int) > latest) {
        await txn.delete('remote_details');
      }
      await txn.update('remote_sync_state', {
        'detail_epoch': (state['detail_epoch'] as int) + 1,
        'bootstrap_watermark': latest,
        'bootstrap_after': '',
        'bootstrap_base_cursor': state['cursor'],
      }, where: 'id=1');
      return (watermark: latest, after: '');
    });
  }

  /// Staging pages survive interruption. Only a complete snapshot replaces cache.
  Future<void> stageCataloguePage(
    CataloguePage page, {
    required String after,
    int? expectedGeneration,
  }) async {
    await (await database).transaction((txn) async {
      final state = (await txn.query('remote_sync_state')).single;
      _checkRemoteGeneration(state, expectedGeneration);
      if (state['bootstrap_watermark'] != page.watermark ||
          state['bootstrap_after'] != after ||
          state['cursor'] != state['bootstrap_base_cursor']) {
        throw const FormatException('concurrent catalogue bootstrap');
      }
      for (final item in page.items) {
        await txn.insert('remote_bootstrap', {
          'id': item['id'],
          'url': item['url'],
          'payload': jsonEncode(item),
        });
      }
      if (page.next != null) {
        await txn.update('remote_sync_state', {
          'bootstrap_after': page.next,
        }, where: 'id=1');
        return;
      }
      // Saved rows remain available as inactive bookmarks; local-only rows are untouched.
      await txn.delete(
        'listings',
        where: '''
        saved=0 AND url IN (SELECT url FROM remote_catalogue)
        AND url NOT IN (SELECT url FROM remote_bootstrap)
      ''',
      );
      await txn.rawUpdate('UPDATE remote_catalogue SET active=0, revision=0');
      var id = '';
      while (true) {
        final rows = await txn.query(
          'remote_bootstrap',
          where: 'id>?',
          whereArgs: [id],
          orderBy: 'id',
          limit: 50,
        );
        if (rows.isEmpty) break;
        final changes = <CatalogueChange>[];
        for (final row in rows) {
          final item = Map<String, Object?>.from(
            jsonDecode(row['payload'] as String) as Map,
          );
          changes.add(
            CatalogueChange(
              0,
              row['id'] as String,
              item['revision'] as int,
              false,
              item,
            ),
          );
        }
        await _applyRemoteChanges(txn, changes, replace: true);
        id = rows.last['id'] as String;
      }
      await txn.update('remote_sync_state', {
        'cursor': page.watermark,
        'bootstrap_watermark': null,
        'bootstrap_after': null,
        'bootstrap_base_cursor': null,
      }, where: 'id=1');
      await txn.delete('remote_bootstrap');
    });
  }

  Future<int> remoteCursor({int? expectedGeneration}) async {
    final db = await database;
    final state = (await db.query('remote_sync_state')).single;
    _checkRemoteGeneration(state, expectedGeneration);
    return state['cursor'] as int;
  }

  Future<int> remoteDetailEpoch({required int expectedGeneration}) async {
    final state = (await (await database).query('remote_sync_state')).single;
    _checkRemoteGeneration(state, expectedGeneration);
    return state['detail_epoch'] as int;
  }

  static void _checkDetailEpoch(Map<String, Object?> state, int epoch) {
    if (state['detail_epoch'] != epoch) {
      throw const FormatException('remote detail snapshot changed');
    }
  }

  Future<Map<String, Object?>?> cachedRemoteDetail(
    String id, {
    required int expectedGeneration,
    required int expectedEpoch,
  }) async => (await database).transaction((txn) async {
    final state = (await txn.query('remote_sync_state')).single;
    _checkRemoteGeneration(state, expectedGeneration);
    _checkDetailEpoch(state, expectedEpoch);
    return _cachedRemoteDetail(txn, state, id);
  });

  static Future<Map<String, Object?>?> _cachedRemoteDetail(
    DatabaseExecutor txn,
    Map<String, Object?> state,
    String id,
  ) async {
    final details = await txn.query(
      'remote_details',
      where: 'id=?',
      whereArgs: [id],
    );
    final detail = details.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(details.single['payload'] as String) as Map,
          );
    // Visible cache can still belong to the prior origin or a resetting snapshot.
    if (state['metadata'] == null || state['bootstrap_watermark'] != null) {
      return detail;
    }
    final rows = await txn.query(
      'remote_catalogue',
      where: 'id=? AND revision>0',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      // A prior-pin detail missing from the completed active snapshot is unavailable.
      return detail != null &&
              (details.single['epoch'] as int) < (state['detail_epoch'] as int)
          ? {...detail, 'active': false}
          : detail;
    }
    final row = rows.single;
    if (detail != null &&
        (detail['revision'] as int) >= (row['revision'] as int)) {
      return detail;
    }
    final item = Map<String, Object?>.from(
      jsonDecode(row['payload'] as String) as Map,
    );
    if (projectRemoteListing(item) == null) {
      // A minimal tombstone still overrides availability of an older full detail.
      return detail == null
          ? null
          : {...detail, 'active': false, 'revision': row['revision']};
    }
    return {
      ...item,
      'id': id,
      'revision': row['revision'],
      'active': row['active'] == 1,
    };
  }

  /// Isolated detail cache: never advances catalogue cursor or mutates favorites.
  Future<Map<String, Object?>> cacheRemoteDetail(
    String id,
    Map<String, Object?> item, {
    required int expectedGeneration,
    required int expectedEpoch,
  }) async {
    if (id.isEmpty ||
        id.length > 200 ||
        item['id'] != id ||
        item['active'] is! bool) {
      throw const FormatException('remote detail identity');
    }
    final validated = CataloguePage.decode({
      'watermark': 0,
      'items': [item],
      'next': null,
    }, watermark: 0).items.single;
    final payload = jsonEncode(validated);
    if (utf8.encode(payload).length > 2 * 1024 * 1024) {
      throw const FormatException('remote detail size');
    }
    return (await database).transaction((txn) async {
      final state = (await txn.query('remote_sync_state')).single;
      _checkRemoteGeneration(state, expectedGeneration);
      _checkDetailEpoch(state, expectedEpoch);
      final cached = await _cachedRemoteDetail(txn, state, id);
      if (cached != null &&
          (cached['revision'] as int) > (validated['revision'] as int)) {
        return cached;
      }
      final order = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COALESCE(MAX(touched),0)+1 FROM remote_details',
        ),
      )!;
      await txn.insert('remote_details', {
        'id': id,
        'revision': validated['revision'],
        'payload': payload,
        'touched': order,
        'epoch': expectedEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // ponytail: newest 20 details / 8MiB; catalogue and bookmarks are retained
      // independently. Increase only after measuring phone storage/JSON costs.
      final rows = await txn.rawQuery(
        'SELECT id,length(CAST(payload AS BLOB)) bytes FROM remote_details ORDER BY touched DESC,id',
      );
      var bytes = 0;
      for (var i = 0; i < rows.length; i++) {
        bytes += rows[i]['bytes'] as int;
        if (i >= 20 || bytes > 8 * 1024 * 1024) {
          await txn.delete(
            'remote_details',
            where: 'id=?',
            whereArgs: [rows[i]['id']],
          );
        }
      }
      return (await _cachedRemoteDetail(txn, state, id))!;
    });
  }

  /// Upsert/tombstone ve cursor birlikte commit olur; kesilen sayfa tekrar okunabilir.
  Future<void> applyDeltaPage(
    CatalogueDeltaPage page, {
    required int after,
    int? expectedGeneration,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final state = (await txn.query('remote_sync_state')).single;
      _checkRemoteGeneration(state, expectedGeneration);
      final cursor = state['cursor'] as int;
      if (cursor != after) throw const FormatException('concurrent delta sync');
      await _applyRemoteChanges(txn, page.changes);
      await txn.update('remote_sync_state', {
        'cursor': page.appliedThrough,
      }, where: 'id=1');
    });
  }

  Future<void> _applyRemoteChanges(
    DatabaseExecutor txn,
    List<CatalogueChange> changes, {
    bool replace = false,
  }) async {
    for (final change in changes) {
      final previous = await txn.query(
        'remote_catalogue',
        where: 'id=?',
        whereArgs: [change.id],
      );
      final old = previous.isEmpty ? null : previous.single;
      if (!replace &&
          old != null &&
          (old['revision'] as int) >= change.revision) {
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
        final record = projectRemoteListing(item);
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
        // Cihazdaki ayıklama durumu replace ile silinmesin (gereksiz yeniden
        // okuma/AI isteği olmasın).
        final extraction = await txn.query(
          'listings',
          columns: ['conditionsCheckedAt', 'aiGroups', 'pendingConditionText'],
          where: 'url=?',
          whereArgs: [record.url],
        );
        if (oldUrl != null && oldUrl != record.url) {
          await txn.delete('listings', where: 'url=?', whereArgs: [oldUrl]);
        }
        await txn.insert('listings', {
          ...record
              .copyWith(
                saved: saved,
                savedAt: savedMs == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(savedMs),
              )
              .toRow(),
          if (extraction.isNotEmpty) ...extraction.single,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('remote_catalogue', {
        'id': change.id,
        'revision': change.revision,
        'url': url,
        'active': change.deleted ? 0 : 1,
        'payload': jsonEncode({
          if (change.deleted && old != null)
            ...Map<String, Object?>.from(
              jsonDecode(old['payload'] as String) as Map,
            ),
          ...item,
          if (change.deleted) 'active': false,
        }),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Detail and delta share the same source/UTC/scoped-summary projection.
  static ListingRecord? projectRemoteListing(Map<String, Object?> item) {
    final summary = (item['summary'] as List? ?? const [])
        .map((s) {
          if (s is! Map) return s;
          final text = s['text'];
          final label = s['scopeLabel'];
          if (text is! String) return null;
          if (label == null) return text;
          return label is String &&
                  label.trim().isNotEmpty &&
                  label.length <= 50
              ? '$label: $text'
              : null;
        })
        .whereType<String>()
        .take(5)
        .toList();
    return listingFromJson(
      {
        ...item,
        'source': item['sourceId'],
        'fetched': item['updatedAt'],
        'published': item['publishedAt'],
        'summary': summary,
      },
      fallbackFetchedAt: DateTime.now(),
      utcDates: true,
    )?.copyWith(criteriaListing: item);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) =>
      upgradeSchema(db, oldVersion, newVersion);

  /// Kaynaktan en son ne zaman yerel çekim yapıldı (nazik aralık için).
  Future<DateTime?> lastFetched(String sourceId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MAX(fetchedAt) AS t FROM listings WHERE sourceId = ?',
      [sourceId],
    );
    final t = rows.first['t'] as int?;
    return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

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
    // URL/native ID kimliktir; kurum ve tarih eşitliği ayrı ilanları silemez.
    for (final record in incoming) {
      record.fingerprint ??= listingFingerprint(
        title: record.title,
        sourceId: record.sourceId,
        deadline: record.deadline,
      );
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
    return db.transaction((txn) async {
      final rows = await txn.query(
        'listings',
        orderBy: 'publishedAt DESC, url',
      );
      final byUrl = <String, Map<String, Object?>>{};
      final ambiguous = <String>{};
      var after = '';
      // Android's system SQLite does not always have JSON1. Decode bounded pages.
      // ponytail: O(cached catalogue); add visible-ID projection if retention leaves a large archive.
      while (true) {
        final remote = await txn.query(
          'remote_catalogue',
          columns: ['id', 'url', 'active', 'payload'],
          where: 'id > ?',
          whereArgs: [after],
          orderBy: 'id',
          limit: 50,
        );
        if (remote.isEmpty) break;
        for (final row in remote) {
          final url = row['url'] as String?;
          if (url == null) continue;
          if (byUrl.containsKey(url)) {
            ambiguous.add(url);
            continue;
          }
          final payload = jsonDecode(row['payload'] as String) as Map;
          byUrl[url] = {
            ...Map<String, Object?>.from(payload),
            'id': row['id'],
            'active': row['active'] == 1 && payload['active'] != false,
          };
        }
        after = remote.last['id'] as String;
      }
      return [
        for (final row in rows)
          ListingRecord.fromRow(row).copyWith(
            criteriaListing: ambiguous.contains(row['url'])
                ? {
                    'requirementGroups': [null],
                  }
                : byUrl[row['url']],
          ),
      ];
    });
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
  Future<void> applyConditions(
    String url,
    ConditionFields fields, {
    DateTime? at,
    bool complete = true,
  }) async {
    final claimed = applyExtractionPolicy(fields);
    final db = await database;
    await db.update(
      'listings',
      {
        'conditionsCheckedAt': complete
            ? (at ?? DateTime.now()).millisecondsSinceEpoch
            : null,
        if (complete) 'pendingConditionText': null,
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

  Future<String?> pendingConditionText(String url) async =>
      (await (await database).query(
            'listings',
            columns: ['pendingConditionText'],
            where: 'url = ?',
            whereArgs: [url],
          )).firstOrNull?['pendingConditionText']
          as String?;

  Future<void> cachePendingConditionText(String url, String text) async {
    await (await database).update(
      'listings',
      {'pendingConditionText': text},
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  /// Yapay zekâyla ayıklanmış, alıntısı sunucuda doğrulanmış koşul grupları.
  Future<void> applyAiGroups(
    String url,
    List<Map<String, Object?>> groups,
  ) async {
    final db = await database;
    await db.update(
      'listings',
      {'aiGroups': jsonEncode(groups)},
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  /// Şartları henüz ayıklanmamış, süresi geçmemiş ilanlar (yeniden eskiye).
  Future<List<ListingRecord>> uncheckedConditions({
    required DateTime now,
    int limit = 12,
  }) async {
    final db = await database;
    final rows = await db.query(
      'listings',
      where:
          'conditionsCheckedAt IS NULL AND (deadline IS NULL OR deadline > ?)',
      whereArgs: [now.millisecondsSinceEpoch],
      orderBy: 'publishedAt DESC',
      limit: limit,
    );
    return rows.map(ListingRecord.fromRow).toList();
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
      criteria: search.criteria,
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
