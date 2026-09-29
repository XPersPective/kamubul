/// Sunucunun yayınladığı katalog anlık görüntüsü (`/v1/listings.json`).
///
/// Şema sürümlüdür; bilinmeyen sürüm okunmaz ve uygulama yedek yola düşer.
/// Okuma güvenilmeyen girdi gibi doğrulanır: https olmayan bağlantılar,
/// sınır dışı sayılar ve aşırı uzun metinler kayıt düzeyinde reddedilir.
library;

import 'dart:convert';

import '../data/listing_models.dart';
import '../time/wall_clock.dart';

const int kSnapshotSchema = 1;
const int kSnapshotMaxListings = 5000;

class SnapshotFormatException implements Exception {
  const SnapshotFormatException(this.message);
  final String message;
  @override
  String toString() => 'SnapshotFormatException: $message';
}

/// Kaynağın son denetim sonucu; kaynak durumu ekranı bunu gösterir.
enum SourceState {
  ok,
  failed,

  /// WAF/oturum/coğrafi engel gibi kanıtlı erişim engeli.
  blocked,

  /// Bilinçli olarak kapalı.
  disabled;

  static SourceState parse(Object? raw) => switch (raw) {
    'ok' => SourceState.ok,
    'blocked' => SourceState.blocked,
    'disabled' => SourceState.disabled,
    _ => SourceState.failed,
  };
}

class SourceStatus {
  const SourceStatus({
    required this.id,
    required this.name,
    required this.state,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.listingCount = 0,
    this.note,
  });

  final String id;
  final String name;
  final SourceState state;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final int listingCount;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'state': state.name,
    if (lastAttemptAt != null) 'lastAttemptAt': wallIso(lastAttemptAt!),
    if (lastSuccessAt != null) 'lastSuccessAt': wallIso(lastSuccessAt!),
    'count': listingCount,
    if (note != null) 'note': note,
  };

  static SourceStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['id'], 40);
    final name = _text(raw['name'], 80);
    if (id == null || name == null) return null;
    final count = raw['count'];
    return SourceStatus(
      id: id,
      name: name,
      state: SourceState.parse(raw['state']),
      lastAttemptAt: parseWallIso(raw['lastAttemptAt']),
      lastSuccessAt: parseWallIso(raw['lastSuccessAt']),
      listingCount: count is int && count >= 0 && count <= 100000 ? count : 0,
      note: _text(raw['note'], 300),
    );
  }
}

class CatalogueSnapshot {
  const CatalogueSnapshot({
    required this.generatedAt,
    required this.sources,
    required this.listings,
    this.skipped = 0,
  });

  final DateTime generatedAt;
  final List<SourceStatus> sources;
  final List<ListingRecord> listings;

  /// Okuma sırasında geçersiz sayılıp atlanan kayıt sayısı (yalnızca okumada).
  final int skipped;

  String encode() => jsonEncode({
    'schema': kSnapshotSchema,
    'generatedAt': wallIso(generatedAt),
    'sources': [for (final source in sources) source.toJson()],
    'listings': [for (final record in listings) listingToJson(record)],
  });

  static CatalogueSnapshot decode(String body) {
    final Object? root;
    try {
      root = jsonDecode(body);
    } on FormatException {
      throw const SnapshotFormatException('JSON okunamadı');
    }
    if (root is! Map) throw const SnapshotFormatException('kök nesne değil');
    final schema = root['schema'];
    if (schema is! int || schema != kSnapshotSchema) {
      throw SnapshotFormatException('bilinmeyen şema sürümü: $schema');
    }
    final generatedAt = parseWallIso(root['generatedAt']);
    if (generatedAt == null) {
      throw const SnapshotFormatException('generatedAt geçersiz');
    }
    final rawListings = root['listings'];
    if (rawListings is! List) {
      throw const SnapshotFormatException('listings listesi yok');
    }
    if (rawListings.length > kSnapshotMaxListings) {
      throw const SnapshotFormatException('çok fazla kayıt');
    }
    final listings = <ListingRecord>[];
    var skipped = 0;
    final seen = <String>{};
    for (final raw in rawListings) {
      final record = listingFromJson(raw, fallbackFetchedAt: generatedAt);
      if (record == null || !seen.add(record.url)) {
        skipped++;
      } else {
        listings.add(record);
      }
    }
    final sources = <SourceStatus>[];
    final rawSources = root['sources'];
    if (rawSources is List) {
      for (final raw in rawSources.take(50)) {
        final source = SourceStatus.fromJson(raw);
        if (source != null) sources.add(source);
      }
    }
    return CatalogueSnapshot(
      generatedAt: generatedAt,
      sources: sources,
      listings: listings,
      skipped: skipped,
    );
  }
}

Map<String, Object?> listingToJson(ListingRecord r) => {
  'url': r.url,
  'source': r.sourceId,
  'title': r.title,
  'category': r.category,
  if (r.publishedAt != null) 'published': wallIso(r.publishedAt!),
  if (r.deadline != null) 'deadline': wallIso(r.deadline!),
  'fetched': wallIso(r.fetchedAt),
  if (r.quota != null) 'quota': r.quota,
  if (r.places.isNotEmpty) 'places': r.places,
  if (r.kpss != null) 'kpss': r.kpss,
  if (r.education != null) 'education': r.education,
  if (r.maxAge != null) 'maxAge': r.maxAge,
  if (r.quotaType != null) 'quotaType': r.quotaType,
  if (r.kpssQuote != null) 'kpssQuote': r.kpssQuote,
  if (r.educationQuote != null) 'educationQuote': r.educationQuote,
  if (r.maxAgeQuote != null) 'maxAgeQuote': r.maxAgeQuote,
  if (r.quotaTypeQuote != null) 'quotaTypeQuote': r.quotaTypeQuote,
  if (r.summary.isNotEmpty) 'summary': r.summary,
  if (r.fingerprint != null) 'fp': r.fingerprint,
};

/// Geçersiz kaydı `null` döndürür; tek kötü kayıt tüm kataloğu düşürmez.
ListingRecord? listingFromJson(
  Object? raw, {
  required DateTime fallbackFetchedAt,
}) {
  if (raw is! Map) return null;
  final url = raw['url'];
  if (url is! String || url.length > 1000) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  final source = _text(raw['source'], 40);
  final title = _text(raw['title'], 500);
  if (source == null || title == null) return null;
  final quota = raw['quota'];
  final maxAge = raw['maxAge'];
  return ListingRecord(
    url: url,
    sourceId: source,
    title: title,
    category: _text(raw['category'], 120) ?? '',
    publishedAt: parseWallIso(raw['published']),
    fetchedAt: parseWallIso(raw['fetched']) ?? fallbackFetchedAt,
    deadline: parseWallIso(raw['deadline']),
    quota: quota is int && quota >= 0 && quota <= 1000000 ? quota : null,
    places: _list(raw['places'], 50, 100),
    kpss: _text(raw['kpss'], 60),
    education: _text(raw['education'], 60),
    maxAge: maxAge is int && maxAge >= 14 && maxAge <= 100 ? maxAge : null,
    quotaType: _text(raw['quotaType'], 60),
    kpssQuote: _text(raw['kpssQuote'], 600),
    educationQuote: _text(raw['educationQuote'], 600),
    maxAgeQuote: _text(raw['maxAgeQuote'], 600),
    quotaTypeQuote: _text(raw['quotaTypeQuote'], 600),
    summary: _list(raw['summary'], 6, 300),
    fingerprint: _text(raw['fp'], 300),
  );
}

String? _text(Object? raw, int max) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty || value.length > max) return null;
  return value;
}

List<String> _list(Object? raw, int maxItems, int maxLength) {
  if (raw is! List) return const [];
  return [for (final item in raw.take(maxItems)) ?_text(item, maxLength)];
}
