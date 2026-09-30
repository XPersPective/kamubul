/// Sunucu kataloğunun birleştirme kuralları: uygulamadaki `mergeFeed` ile aynı
/// sözleşme, saf ve test edilebilir biçimde.
///
/// - Bilinen URL güncellenir; yeni akış boş alan getirirse var olan değer
///   silinmez.
/// - Yeni URL, aynı kurum+son başvuru anahtarıyla FARKLI bir kaynakta zaten
///   varsa (çapraz kaynak kopyası) alınmaz; aynı kaynaktaki kardeş ilan kalır.
/// - Yalnızca yeni girenler [MergeResult.added] listesindedir; bildirim bu
///   listeyle üretilir, böylece aynı ilan ikinci kez "yeni" sayılmaz.
/// - Bir süredir kaynakta görünmeyen kayıtlar [pruneAfter] sonra düşer.
library;

import '../data/dedupe.dart';
import '../data/listing_models.dart';

class MergeResult {
  const MergeResult(this.listings, this.added);

  final List<ListingRecord> listings;
  final List<ListingRecord> added;
}

const Duration kServerPruneAfter = Duration(days: 45);
const int kServerMaxListings = 1500;

MergeResult mergeCatalogue({
  required List<ListingRecord> previous,
  required List<ListingRecord> incoming,
  required DateTime now,
  Duration pruneAfter = kServerPruneAfter,
  int maxListings = kServerMaxListings,
}) {
  final byUrl = {for (final record in previous) record.url: record};
  final keySources = <String, Set<String>>{};
  void track(ListingRecord record) => keySources
      .putIfAbsent(
        crossSourceKey(
          title: record.title,
          sourceId: record.sourceId,
          deadline: record.deadline,
        ),
        () => <String>{},
      )
      .add(record.sourceId);
  previous.forEach(track);
  final added = <ListingRecord>[];
  for (final item in incoming) {
    // Uygulamanın kendi tekilleştirmesiyle uyumlu parmak izi; çapraz kaynak
    // kararı ayrı anahtarla verilir.
    final fingerprint =
        item.fingerprint ??
        listingFingerprint(
          title: item.title,
          sourceId: item.sourceId,
          deadline: item.deadline,
        );
    final existing = byUrl[item.url];
    if (existing == null) {
      final sources =
          keySources[crossSourceKey(
            title: item.title,
            sourceId: item.sourceId,
            deadline: item.deadline,
          )];
      if (sources != null && sources.any((s) => s != item.sourceId)) continue;
      final record = item.copyWith(fingerprint: fingerprint, fetchedAt: now);
      track(record);
      byUrl[item.url] = record;
      added.add(record);
      continue;
    }
    byUrl[item.url] = ListingRecord(
      url: existing.url,
      sourceId: existing.sourceId,
      title: item.title,
      category: item.category,
      publishedAt: item.publishedAt ?? existing.publishedAt,
      fetchedAt: now,
      deadline: item.deadline ?? existing.deadline,
      quota: item.quota ?? existing.quota,
      places: item.places.isNotEmpty ? item.places : existing.places,
      kpss: item.kpss ?? existing.kpss,
      education: item.education ?? existing.education,
      maxAge: item.maxAge ?? existing.maxAge,
      quotaType: item.quotaType ?? existing.quotaType,
      kpssQuote: item.kpssQuote ?? existing.kpssQuote,
      educationQuote: item.educationQuote ?? existing.educationQuote,
      maxAgeQuote: item.maxAgeQuote ?? existing.maxAgeQuote,
      quotaTypeQuote: item.quotaTypeQuote ?? existing.quotaTypeQuote,
      summary: item.summary.isNotEmpty ? item.summary : existing.summary,
      fingerprint: fingerprint,
    );
  }
  final cutoff = now.subtract(pruneAfter);
  final kept =
      byUrl.values
          .where((record) => !record.fetchedAt.isBefore(cutoff))
          .toList()
        ..sort((a, b) {
          final byDate = (b.publishedAt ?? b.fetchedAt).compareTo(
            a.publishedAt ?? a.fetchedAt,
          );
          return byDate != 0 ? byDate : a.url.compareTo(b.url);
        });
  final limited = kept.length > maxListings
      ? kept.sublist(0, maxListings)
      : kept;
  final keptUrls = {for (final record in limited) record.url};
  return MergeResult(limited, [
    for (final record in added)
      if (keptUrls.contains(record.url)) byUrl[record.url]!,
  ]);
}
