/// Kullanıcı verisinin taşınabilir JSON dışa/içe aktarımı (C-021).
///
/// Dışa aktarılan veri kayıtlı aramalar (profil etiketleri dahil) ve yer
/// imleridir; yalnızca bu cihazdan çıkar, hiçbir sunucuya gitmez. Dosya
/// [BackupCodec] zarfına sarılır (ORTAK 3.8): paket adı bağlanır, başka
/// uygulamanın yedeği kabul edilmez ve ayrılmış anahtarlar (Pro durumu,
/// reklam sayaçları, sırlar) yedeğe girmez; zarfta görünürse dosya
/// reddedilir.
///
/// İçe aktarma şema sürümü doğrulanmış girdiyi kabul eder: bozuk JSON,
/// bilinmeyen sürüm, https olmayan ya da tanımsız kaynak bağlantıları
/// reddedilir; var olan kayıtlar hiçbir koşulda üzerine yazılmaz.
library;

import 'package:napp_core/napp_core.dart';
import 'package:kamubul_core/kamubul_core.dart' show SearchCriteria;

import 'listing_store.dart';

/// Yedek zarfının ait olduğu uygulama paketi; başka uygulamanın yedeği
/// kabul edilmez.
const String kUserDataPackageName = 'com.crazypenguin.kamubul';

/// Uygulama veri bölümünün şema sürümü (zarf sürümünden bağımsız).
const int kUserDataSchemaVersion = 2;

/// İçe aktarmada kabul edilen resmî kaynak kimlikleri.
const Set<String> kUserDataSourceIds = {
  'kariyerkapisi',
  'kamuilan_sbb',
  'sbb',
  'resmigazete',
};

/// İzin verilen azami kayıt sayıları; girdi güvenilmez kabul edilir.
const int _maxSearches = 100;
const int _maxBookmarks = 2000;
const int _maxPlaces = 100;
const int _maxFilters = 50;

BackupCodec _codec() => BackupCodec(
  packageName: kUserDataPackageName,
  maxDataBytes: 16 * 1024 * 1024,
);

/// Kayıtlı aramalar + yer imlerini şemalı yedek zarfına yazar.
///
/// [exportedAt] yalnızca test içindir; üretime zamanda bırakılır. Veri
/// boyutu zarf sınırını aşarsa [StateError] fırlatılır.
String exportUserDataJson({
  required List<SavedSearch> searches,
  required List<ListingRecord> bookmarks,
  DateTime? exportedAt,
}) {
  for (final search in searches) {
    if (search.hasInvalidCriteria) {
      throw const FormatException('Kriterleri okunamayan arama yedeklenemez.');
    }
  }
  return _codec().export({
    'schema': kUserDataSchemaVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'searches': [
      for (final search in searches)
        {
          'name': search.name,
          'filters': search.filters,
          if (search.criteria != null) 'criteria': search.criteria!.values,
          'createdAt': search.createdAt.toIso8601String(),
        },
    ],
    'bookmarks': [
      for (final record in bookmarks)
        {
          'url': record.url,
          'sourceId': record.sourceId,
          'title': record.title,
          'category': record.category,
          'publishedAt': record.publishedAt?.toIso8601String(),
          'fetchedAt': record.fetchedAt.toIso8601String(),
          'deadline': record.deadline?.toIso8601String(),
          'quota': record.quota,
          'places': record.places,
          'kpss': record.kpss,
          'kpssQuote': record.kpssQuote,
          'education': record.education,
          'educationQuote': record.educationQuote,
          'maxAge': record.maxAge,
          'maxAgeQuote': record.maxAgeQuote,
          'quotaType': record.quotaType,
          'quotaTypeQuote': record.quotaTypeQuote,
          'savedAt': record.savedAt?.toIso8601String(),
        },
    ],
  });
}

/// Doğrulanmış içe aktarma sonucu; kimlikler sıfırdan verilir.
class UserDataImport {
  const UserDataImport({required this.searches, required this.bookmarks});

  final List<SavedSearch> searches;
  final List<ListingRecord> bookmarks;
}

/// Yedek zarfını doğrular, veri bölümünü ayrıştırır.
///
/// Girdi güvenilmez kabul edilir: her alanın tipi ve sınırı denetlenir,
/// bağlantılar yalnızca https ve bilinen resmî kaynak olabilir. Kural
/// ihlalinde [FormatException] fırlatılır; çağıran hiçbir şey yazmaz.
UserDataImport parseUserDataJson(String source) {
  final envelope = _codec().import(source);
  final decoded = envelope.data;
  if (decoded == null) {
    throw const FormatException('Yedek dosyası okunamadı.');
  }
  final schema = decoded['schema'];
  if (schema != 1 && schema != kUserDataSchemaVersion) {
    throw FormatException('Desteklenmeyen veri sürümü: $schema');
  }

  // Eksik liste boş sayılır; var olan liste tip ve sınır denetiminden geçer.
  final rawSearches = decoded['searches'] ?? const <Object?>[];
  final rawBookmarks = decoded['bookmarks'] ?? const <Object?>[];
  if (rawSearches is! List || rawBookmarks is! List) {
    throw const FormatException('searches/bookmarks listeleri geçersiz.');
  }
  if (rawSearches.length > _maxSearches ||
      rawBookmarks.length > _maxBookmarks) {
    throw const FormatException('Dosya beklenenden çok kayıt içeriyor.');
  }

  return UserDataImport(
    searches: [for (final row in rawSearches) _readSearch(row, schema as int)],
    bookmarks: [for (final row in rawBookmarks) _readBookmark(row)],
  );
}

SavedSearch _readSearch(Object? row, int schema) {
  final map = _asMap(row, 'arama');
  final name = _asString(map, 'name', 'arama');
  if (name.isEmpty) {
    throw const FormatException('Adsız kayıtlı arama olamaz.');
  }
  final rawFilters = map['filters'];
  if (rawFilters is! Map || rawFilters.length > _maxFilters) {
    throw const FormatException('Süzgeçler sözlük değil ya da çok büyük.');
  }
  final filters = <String, String>{};
  rawFilters.forEach((key, value) {
    if (key is! String || value is! String) {
      throw const FormatException('Süzgeç değerleri metin olmalı.');
    }
    filters[key] = value;
  });
  SearchCriteria? criteria;
  if (map.containsKey('criteria')) {
    final raw = map['criteria'];
    if (schema != 2 || raw is! Map<String, dynamic>) {
      throw const FormatException('Arama kriterleri geçersiz.');
    }
    criteria = SearchCriteria.parse(raw);
  }
  return SavedSearch(
    id: null,
    name: name,
    filters: filters,
    criteria: criteria,
    createdAt: _asDateTime(map, 'createdAt', 'arama'),
  );
}

ListingRecord _readBookmark(Object? row) {
  final map = _asMap(row, 'yer imi');
  final url = _asString(map, 'url', 'yer imi');
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException(
      'Yalnızca https bağlantıları içe aktarılabilir: $url',
    );
  }
  final sourceId = _asString(map, 'sourceId', 'yer imi');
  if (!kUserDataSourceIds.contains(sourceId)) {
    throw FormatException('Bilinmeyen kaynak: $sourceId');
  }
  final title = _asString(map, 'title', 'yer imi');
  if (title.isEmpty) {
    throw const FormatException('Başlıksız yer imi olamaz.');
  }
  // Eksik yer listesi boş sayılır; var olan liste tip ve sınır denetiminden geçer.
  final rawPlaces = map['places'] ?? const <Object?>[];
  if (rawPlaces is! List || rawPlaces.length > _maxPlaces) {
    throw const FormatException('places listesi geçersiz.');
  }
  final places = <String>[
    for (final place in rawPlaces)
      if (place is! String)
        throw const FormatException('Yer adları metin olmalı.')
      else
        place,
  ];
  final fetchedAt = _asDateTime(map, 'fetchedAt', 'yer imi');
  final savedAt = _asDateTimeOrNull(map, 'savedAt', 'yer imi');
  return ListingRecord(
    url: url,
    sourceId: sourceId,
    title: title,
    category: _asString(map, 'category', 'yer imi', fallback: ''),
    publishedAt: _asDateTimeOrNull(map, 'publishedAt', 'yer imi'),
    fetchedAt: fetchedAt,
    deadline: _asDateTimeOrNull(map, 'deadline', 'yer imi'),
    quota: _asIntOrNull(map, 'quota', 'yer imi'),
    places: places,
    kpss: _asStringOrNull(map, 'kpss', 'yer imi'),
    kpssQuote: _asStringOrNull(map, 'kpssQuote', 'yer imi'),
    education: _asStringOrNull(map, 'education', 'yer imi'),
    educationQuote: _asStringOrNull(map, 'educationQuote', 'yer imi'),
    maxAge: _asIntOrNull(map, 'maxAge', 'yer imi'),
    maxAgeQuote: _asStringOrNull(map, 'maxAgeQuote', 'yer imi'),
    quotaType: _asStringOrNull(map, 'quotaType', 'yer imi'),
    quotaTypeQuote: _asStringOrNull(map, 'quotaTypeQuote', 'yer imi'),
    saved: true,
    savedAt: savedAt ?? fetchedAt,
  );
}

Map<String, dynamic> _asMap(Object? row, String kind) {
  if (row is! Map<String, dynamic>) {
    throw FormatException('$kind kaydı JSON nesnesi değil.');
  }
  return row;
}

String _asString(
  Map<String, dynamic> map,
  String key,
  String kind, {
  String fallback = '',
}) {
  final value = map[key];
  if (value == null) return fallback;
  if (value is! String || value.length > 5000) {
    throw FormatException('$kind/$key metin değil.');
  }
  return value;
}

String? _asStringOrNull(Map<String, dynamic> map, String key, String kind) {
  if (!map.containsKey(key) || map[key] == null) return null;
  return _asString(map, key, kind);
}

int? _asIntOrNull(Map<String, dynamic> map, String key, String kind) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('$kind/$key sayı değil.');
  }
  return value;
}

DateTime _asDateTime(Map<String, dynamic> map, String key, String kind) {
  final value = _asDateTimeOrNull(map, key, kind);
  if (value == null) {
    throw FormatException('$kind/$key tarihi eksik.');
  }
  return value;
}

DateTime? _asDateTimeOrNull(Map<String, dynamic> map, String key, String kind) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$kind/$key tarih metni değil.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$kind/$key tarihi okunamadı.');
  }
  return parsed;
}
