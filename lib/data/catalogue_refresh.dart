import 'package:kamubul_core/listings/source_records.dart';

import '../listings/kariyer_feed.dart';
import '../listings/sbb_feed.dart';
import 'listing_store.dart';
import 'turkish_cities.dart';

const cataloguePruneAfter = Duration(days: 45);

class CatalogueRefreshResult {
  const CatalogueRefreshResult(this.checkedAt, this.failedSources);

  final DateTime checkedAt;
  final List<String> failedSources;
}

/// Seçilen şehri resmî Kariyer Kapısı liste süzgeciyle doğrular.
Future<int> refreshKariyerCity(ListingStore store, String city) async {
  final canonical = canonicalCity(city);
  if (canonical == null) throw const FormatException('Geçersiz şehir adı');
  final items = await loadKariyerCityListings(canonical);
  await store.addVerifiedCity(
    canonical,
    items.map((item) => item.url.toString()),
  );
  return items.length;
}

/// Ekran, elle denetim ve arka plan görevi aynı yenileme yolunu kullanır.
/// Bir kaynak bozulduğunda diğerleri ve mevcut yerel kayıtlar korunur.
Future<CatalogueRefreshResult> refreshCatalogue(
  ListingStore store, {
  Future<List<PublicListing>> Function()? kariyer,
  Future<List<SbbListing>> Function()? sbb,
  DateTime? at,
}) async {
  final now = at ?? DateTime.now();
  final incoming = <ListingRecord>[];
  final failed = <String>[];
  try {
    final items = await (kariyer ?? loadKariyerListings)();
    incoming.addAll([for (final item in items) kariyerRecord(item, now)]);
  } on Exception {
    failed.add('Kariyer Kapısı');
  }
  try {
    final items = await (sbb ?? loadSbbListings)();
    incoming.addAll([for (final item in items) sbbRecord(item, now)]);
  } on Exception {
    failed.add('Kamu İlanları (SBB)');
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
