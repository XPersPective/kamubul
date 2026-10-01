import 'dart:convert';

import 'search_criteria.dart';

import 'turkish_cities.dart' show foldTurkish;

bool placeMatchesCity(String place, String city) {
  return foldTurkish(place).contains(foldTurkish(city));
}

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
    this.summary = const [],
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

  /// Sunucunun yapay zekâ ile ürettiği kısa madde özeti; boşsa özet yoktur.
  /// Her madde "Yapay zekâ özeti" olarak etiketlenerek gösterilir.
  final List<String> summary;
  String? fingerprint;
  final bool saved;
  final DateTime? savedAt;

  ListingRecord copyWith({
    DateTime? fetchedAt,
    int? quota,
    DateTime? deadline,
    DateTime? publishedAt,
    List<String>? places,
    String? kpss,
    String? education,
    int? maxAge,
    String? quotaType,
    String? kpssQuote,
    String? educationQuote,
    String? maxAgeQuote,
    String? quotaTypeQuote,
    List<String>? summary,
    String? fingerprint,
    bool? saved,
    DateTime? savedAt,
  }) => ListingRecord(
    url: url,
    sourceId: sourceId,
    title: title,
    category: category,
    publishedAt: publishedAt ?? this.publishedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    deadline: deadline ?? this.deadline,
    quota: quota ?? this.quota,
    places: places ?? this.places,
    kpss: kpss ?? this.kpss,
    education: education ?? this.education,
    maxAge: maxAge ?? this.maxAge,
    quotaType: quotaType ?? this.quotaType,
    kpssQuote: kpssQuote ?? this.kpssQuote,
    educationQuote: educationQuote ?? this.educationQuote,
    maxAgeQuote: maxAgeQuote ?? this.maxAgeQuote,
    quotaTypeQuote: quotaTypeQuote ?? this.quotaTypeQuote,
    summary: summary ?? this.summary,
    fingerprint: fingerprint ?? this.fingerprint,
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
    'kpssQuote': kpssQuote,
    'educationQuote': educationQuote,
    'maxAgeQuote': maxAgeQuote,
    'quotaTypeQuote': quotaTypeQuote,
    'summary': summary.isEmpty ? null : jsonEncode(summary),
    'fingerprint': fingerprint,
    'saved': saved ? 1 : 0,
    'savedAt': savedAt?.millisecondsSinceEpoch,
  };

  static ListingRecord fromRow(Map<String, Object?> row) {
    final places = decodePlaces(row['places']);
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
      summary: decodeSummary(row['summary']),
      fingerprint: row['fingerprint'] as String?,
      saved: row['saved'] == 1,
      savedAt: _date(row['savedAt']),
    );
  }

  static List<String> decodePlaces(Object? raw) {
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

  /// Bozuk özet alanı boş okunur; kayıt kaybolmaz.
  static List<String> decodeSummary(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } on FormatException {
      // Bozuk özet yalnızca özeti düşürür.
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
    this.criteria,
    this.hasInvalidCriteria = false,
  });

  final int? id;
  final String name;
  final Map<String, String> filters;
  final DateTime createdAt;
  final SearchCriteria? criteria;
  final bool hasInvalidCriteria;

  SearchCriteria get effectiveCriteria {
    if (hasInvalidCriteria) {
      throw const FormatException('saved_search_criteria');
    }
    return criteria ?? SearchCriteria.fromLegacy(filters);
  }

  SavedSearch copyWith({
    String? name,
    Map<String, String>? filters,
    SearchCriteria? criteria,
  }) => SavedSearch(
    id: id,
    name: name ?? this.name,
    filters: filters ?? this.filters,
    createdAt: createdAt,
    criteria: criteria ?? this.criteria,
    hasInvalidCriteria: criteria == null && hasInvalidCriteria,
  );

  Map<String, Object?> toRow() {
    if (hasInvalidCriteria) {
      throw const FormatException('saved_search_criteria');
    }
    return {
      if (id != null) 'id': id,
      'name': name,
      'filters': jsonEncode(
        criteria == null
            ? filters
            : {
                'criteriaVersion': 2,
                'filters': filters,
                'criteria': criteria!.values,
              },
      ),
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  static SavedSearch fromRow(Map<String, Object?> row) {
    var filters = <String, String>{};
    SearchCriteria? criteria;
    var invalid = false;
    try {
      final raw = jsonDecode(row['filters'] as String);
      if (raw is! Map) throw const FormatException('search_filters');
      final version = raw['criteriaVersion'];
      final legacy = version == null ? raw : raw['filters'];
      if (legacy is! Map ||
          legacy.entries.any((e) => e.key is! String || e.value is! String)) {
        throw const FormatException('search_filters');
      }
      filters = Map<String, String>.from(legacy);
      if (version != null) {
        if (version != 2 || raw['criteria'] is! Map) {
          throw const FormatException('criteria_version');
        }
        criteria = SearchCriteria.parse(
          Map<String, Object?>.from(raw['criteria'] as Map),
        );
      }
    } on FormatException {
      invalid = true;
    } on TypeError {
      invalid = true;
    }
    return SavedSearch(
      id: row['id'] as int?,
      name: row['name'] as String? ?? '',
      filters: filters,
      criteria: criteria,
      hasInvalidCriteria: invalid,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['createdAt'] as int? ?? 0,
      ),
    );
  }
}
