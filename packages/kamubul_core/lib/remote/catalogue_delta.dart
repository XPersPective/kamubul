import 'snapshot.dart';

class CatalogueChange {
  const CatalogueChange(
    this.seq,
    this.id,
    this.revision,
    this.deleted,
    this.item,
  );
  final int seq;
  final String id;
  final int revision;
  final bool deleted;
  final Map<String, Object?> item;
}

/// Tek sayfa tek SQLite transaction'ında, cursor ile beraber uygulanmalıdır.
class CatalogueDeltaPage {
  const CatalogueDeltaPage(
    this.watermark,
    this.appliedThrough,
    this.hasMore,
    this.changes,
  );
  final int watermark;
  final int appliedThrough;
  final bool hasMore;
  final List<CatalogueChange> changes;

  static CatalogueDeltaPage decode(
    Object? raw, {
    required int after,
    int? expectedWatermark,
  }) {
    if (raw is! Map) throw const SnapshotFormatException('delta root');
    final watermark = raw['watermark'],
        applied = raw['appliedThrough'],
        more = raw['hasMore'],
        rows = raw['changes'];
    if (watermark is! int ||
        watermark < after ||
        watermark > 9007199254740991 ||
        applied is! int ||
        applied < after ||
        applied > watermark ||
        more is! bool ||
        more != (applied < watermark) ||
        rows is! List ||
        rows.length > 50 ||
        (expectedWatermark != null && watermark != expectedWatermark)) {
      throw const SnapshotFormatException('delta cursor');
    }
    var previous = after;
    final changes = <CatalogueChange>[];
    for (final r in rows) {
      if (r is! Map ||
          r['seq'] is! int ||
          r['id'] is! String ||
          r['revision'] is! int ||
          r['item'] is! Map ||
          !['upsert', 'tombstone'].contains(r['operation'])) {
        throw const SnapshotFormatException('delta change');
      }
      final seq = r['seq'] as int,
          id = r['id'] as String,
          revision = r['revision'] as int;
      final item = Map<String, Object?>.from(r['item'] as Map);
      if (seq <= previous ||
          seq > applied ||
          id.isEmpty ||
          id.length > 200 ||
          revision < 1 ||
          item['id'] != id ||
          item['revision'] != revision) {
        throw const SnapshotFormatException('delta identity');
      }
      final deleted = r['operation'] == 'tombstone';
      if (!deleted &&
          listingFromJson({
                ...item,
                'source': item['sourceId'],
                'fetched': item['updatedAt'],
                'published': item['publishedAt'],
                'summary': <String>[],
              }, fallbackFetchedAt: DateTime.utc(1970)) ==
              null) {
        throw const SnapshotFormatException('delta listing');
      }
      changes.add(
        CatalogueChange(seq, id, revision, deleted, Map.unmodifiable(item)),
      );
      previous = seq;
    }
    if ((rows.isEmpty && more) || (rows.isNotEmpty && previous != applied)) {
      throw const SnapshotFormatException('delta progress');
    }
    return CatalogueDeltaPage(
      watermark,
      applied,
      more,
      List.unmodifiable(changes),
    );
  }
}
