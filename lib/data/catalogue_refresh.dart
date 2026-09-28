import '../listings/kariyer_feed.dart';
import '../listings/rg_feed.dart';
import '../listings/sbb_feed.dart';
import 'listing_store.dart';

const cataloguePruneAfter = Duration(days: 45);

class CatalogueRefreshResult {
  const CatalogueRefreshResult(this.checkedAt, this.failedSources);

  final DateTime checkedAt;
  final List<String> failedSources;
}

/// Ekran, elle denetim ve arka plan görevi aynı yenileme yolunu kullanır.
/// Bir kaynak bozulduğunda diğerleri ve mevcut yerel kayıtlar korunur.
Future<CatalogueRefreshResult> refreshCatalogue(
  ListingStore store, {
  Future<List<PublicListing>> Function()? kariyer,
  Future<List<SbbListing>> Function()? sbb,
  Future<List<RgNotice>> Function()? gazete,
  DateTime? at,
}) async {
  final now = at ?? DateTime.now();
  final incoming = <ListingRecord>[];
  final failed = <String>[];
  try {
    final items = await (kariyer ?? loadKariyerListings)();
    incoming.addAll([
      for (final item in items)
        ListingRecord(
          url: item.url.toString(),
          sourceId: 'kariyerkapisi',
          title: item.title,
          category: item.category,
          publishedAt: item.publishedAt,
          deadline: item.deadline,
          fetchedAt: now,
        ),
    ]);
  } on Exception {
    failed.add('Kariyer Kapısı');
  }
  try {
    final items = await (sbb ?? loadSbbListings)();
    incoming.addAll([
      for (final item in items)
        ListingRecord(
          url: item.url.toString(),
          sourceId: 'kamuilan_sbb',
          title: '${item.institution} — ${item.title}',
          category: item.category,
          publishedAt: item.publishedAt,
          deadline: item.deadline,
          quota: item.quota,
          fetchedAt: now,
        ),
    ]);
  } on Exception {
    failed.add('Kamu İlanları (SBB)');
  }
  try {
    final items = await (gazete ?? loadRgPersonnelNotices)();
    incoming.addAll([
      for (final item in items)
        ListingRecord(
          url: item.url.toString(),
          sourceId: 'resmigazete',
          title: item.title,
          category: 'Resmî Gazete',
          publishedAt: item.publishedAt,
          fetchedAt: now,
        ),
    ]);
  } on Exception {
    failed.add('Resmî Gazete');
  }
  if (incoming.isNotEmpty) {
    try {
      await store.mergeFeed(
        incoming,
        pruneBefore: now.subtract(cataloguePruneAfter),
      );
    } on Exception {
      failed.add('Yerel katalog');
    }
  }
  return CatalogueRefreshResult(now, failed);
}
