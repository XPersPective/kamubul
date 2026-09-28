import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../listings/extract_conditions.dart';
import 'dedupe.dart';

/// Yerel ilan kataloğu: sürümlü şema, birleştirmeli yenileme, budama.
///
/// Kullanıcının kaydettiği ilanlar asla sessizce silinmez; yalnızca kaydedilmemiş
/// ve uzun süredir görülmeyen ilanlar budanır.
class ListingRecord {
  ListingRecord({
    required this.url,
    required this.sourceId,
    required this.title,
    required this.category,
    required this.publishedAt,
    required this.fetchedAt,
    this.deadline,
    this.quota,
    this.places = const [],
    this.kpss,
    this.education,
    this.maxAge,
    this.quotaType,
    this.kpssQuote,
    this.educationQuote,
    this.maxAgeQuote,
    this.quotaTypeQuote,
    this.fingerprint,
    this.saved = false,
    this.savedAt,
  });

  final String url;
  final String sourceId;
  final String title;
  final String category;
  final DateTime? publishedAt;
  final DateTime fetchedAt;
  final DateTime? deadline;
  final int? quota;
  final List<String> places;
  final String? kpss;
  final String? education;
  final int? maxAge;
  final String? quotaType;
  final String? kpssQuote;
  final String? educationQuote;
  final String? maxAgeQuote;
  final String? quotaTypeQuote;
  String? fingerprint;
  final bool saved;
  final DateTime? savedAt;

  ListingRecord copyWith({
    DateTime? fetchedAt,
    int? quota,
    DateTime? deadline,
    List<String>? places,
    bool? saved,
    DateTime? savedAt,
  }) => ListingRecord(
    url: url,
    sourceId: sourceId,
    title: title,
    category: category,
    publishedAt: publishedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    deadline: deadline ?? this.deadline,
    quota: quota ?? this.quota,
    places: places ?? this.places,
    kpss: kpss,
    education: education,
    maxAge: maxAge,
    quotaType: quotaType,
    saved: saved ?? this.saved,
    savedAt: savedAt ?? this.savedAt,
  );

  bool get expired => deadline != null && deadline!.isBefore(DateTime.now());

  Map<String, Object?> toRow() => {
    'url': url,
    'sourceId': sourceId,
    'title': title,
    'category': category,
    'publishedAt': publishedAt?.millisecondsSinceEpoch,
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'deadline': deadline?.millisecondsSinceEpoch,
    'quota': quota,
    'places': jsonEncode(places),
    'kpss': kpss,
    'education': education,
    'maxAge': maxAge,
    'quotaType': quotaType,
    'fingerprint': fingerprint,
    'saved': saved ? 1 : 0,
    'savedAt': savedAt?.millisecondsSinceEpoch,
  };

  static ListingRecord fromRow(Map<String, Object?> row) {
    final places = _decodePlaces(row['places']);
    return ListingRecord(
      url: row['url'] as String,
      sourceId: row['sourceId'] as String? ?? 'kariyerkapisi',
      title: row['title'] as String? ?? '',
      category: row['category'] as String? ?? '',
      publishedAt: _date(row['publishedAt']),
      fetchedAt: _date(row['fetchedAt']) ?? DateTime.now(),
      deadline: _date(row['deadline']),
      quota: row['quota'] is int ? row['quota'] as int : null,
      places: places,
      kpss: row['kpss'] as String?,
      education: row['education'] as String?,
      maxAge: row['maxAge'] is int ? row['maxAge'] as int : null,
      quotaType: row['quotaType'] as String?,
      kpssQuote: row['kpssQuote'] as String?,
      educationQuote: row['educationQuote'] as String?,
      maxAgeQuote: row['maxAgeQuote'] as String?,
      quotaTypeQuote: row['quotaTypeQuote'] as String?,
      fingerprint: row['fingerprint'] as String?,
      saved: row['saved'] == 1,
      savedAt: _date(row['savedAt']),
    );
  }

  static List<String> _decodePlaces(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((place) {
              final halves = place.split(' / ');
              return halves.length == 2 && halves[0] == halves[1]
                  ? halves[0]
                  : place;
            })
            .toSet()
            .toList();
      }
    } on FormatException {
      // Bozuk kayıt tek alanı düşürür, uygulamayı çökertmez.
    }
    return const [];
  }

  static DateTime? _date(Object? raw) =>
      raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;
}

class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.filters,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final Map<String, String> filters;
  final DateTime createdAt;

  SavedSearch copyWith({String? name, Map<String, String>? filters}) =>
      SavedSearch(
        id: id,
        name: name ?? this.name,
        filters: filters ?? this.filters,
        createdAt: createdAt,
      );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'filters': jsonEncode(filters),
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static SavedSearch fromRow(Map<String, Object?> row) => SavedSearch(
    id: row['id'] as int?,
    name: row['name'] as String? ?? '',
    filters: _decodeFilters(row['filters']),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['createdAt'] as int? ?? 0,
    ),
  );

  static Map<String, String> _decodeFilters(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } on FormatException {
      // Bozuk kayıt boş süzgeç olarak okunur; uygulama çökmez.
    }
    return const {};
  }
}

class ListingStore {
  ListingStore({Database? database}) : _injected = database;

  final Database? _injected;
  Database? _db;

  Future<Database> get database async {
    final existing = _injected ?? _db;
    if (existing != null) return existing;
    final opened = await openDatabase(
      p.join(await getDatabasesPath(), 'kamubul_listings.db'),
      version: _schemaVersion,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    _db = opened;
    return opened;
  }

  static const int _schemaVersion = 3;

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
  }

  /// Şema yükseltmeleri: v1→v2 şart alıntısı sütunları, v2→v3 parmak izi
  /// sütunu. Mevcut veri korunur.
  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE listings ADD COLUMN fingerprint TEXT');
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
  /// Alıntısı olmayan değer yazılmaz; alan "belirtilmemiş" kalır.
  Future<void> applyConditions(String url, ConditionFields fields) async {
    final db = await database;
    await db.update(
      'listings',
      {
        'kpss': ?fields.kpssType?.value,
        'kpssQuote': ?fields.kpssType?.quote,
        'education': ?fields.education?.value,
        'educationQuote': ?fields.education?.quote,
        'maxAge': ?fields.maxAge?.value,
        'maxAgeQuote': ?fields.maxAge?.quote,
        'quotaType': ?fields.quotaType?.value,
        'quotaTypeQuote': ?fields.quotaType?.quote,
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

  Future<void> close() async {
    await (_injected ?? _db)?.close();
    _db = null;
  }
}
