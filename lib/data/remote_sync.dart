/// Sunucu kataloğunu yerel veritabanına işler.
///
/// Sunucu anlık görüntüsü (`/v1/listings.json`) resmî kaynaklardan derlenmiş,
/// şart alanları alıntılı doğrulanmış ilanları taşır. Yerel kayıtlar
/// korunur: kaydedilen ilanlar sıfırlanmaz, sunucudan boş gelen alan var olan
/// ayrıntıyı silmez (bkz. `ListingStore.mergeFeed`).
library;

import 'package:kamubul_core/kamubul_core.dart';

import 'listing_store.dart';

/// Uygulama derlemesine `--dart-define=KAMUBUL_API=https://...` ile verilir.
/// Boşsa uzak katalog kapalıdır ve uygulama yalnızca gömülü çekimi kullanır.
const String kApiBaseUrl = String.fromEnvironment('KAMUBUL_API');

/// Yapılandırma geçersizse ya da boşsa `null`; çağıran gömülü yola düşer.
RemoteCatalogueClient? defaultRemoteClient() {
  if (kApiBaseUrl.isEmpty) return null;
  try {
    return RemoteCatalogueClient(baseUrl: Uri.parse(kApiBaseUrl));
  } on ArgumentError {
    return null;
  }
}

class RemoteSyncResult {
  const RemoteSyncResult({
    required this.generatedAt,
    required this.sources,
    required this.listingCount,
    required this.skipped,
  });

  /// Sunucunun anlık görüntüyü ürettiği zaman (Türkiye duvar saati).
  final DateTime generatedAt;
  final List<SourceStatus> sources;
  final int listingCount;
  final int skipped;

  SourceState? stateOf(String sourceId) {
    for (final source in sources) {
      if (source.id == sourceId) return source.state;
    }
    return null;
  }
}

/// Anlık görüntüyü çeker ve yerel kataloğa birleştirir. Ağ ya da biçim hatası
/// istisna fırlatır; yerel kayıtlar dokunulmaz kalır.
Future<RemoteSyncResult> syncRemoteCatalogue({
  required ListingStore store,
  required RemoteCatalogueClient client,
  required DateTime now,
  required DateTime pruneBefore,
}) async {
  final result = await client.fetchListings();
  final snapshot = result.snapshot;
  if (snapshot == null) {
    throw const RemoteCatalogueException('boş yanıt');
  }
  if (snapshot.listings.isNotEmpty) {
    await store.mergeFeed([
      for (final record in snapshot.listings) record.copyWith(fetchedAt: now),
    ], pruneBefore: pruneBefore);
  }
  return RemoteSyncResult(
    generatedAt: snapshot.generatedAt,
    sources: snapshot.sources,
    listingCount: snapshot.listings.length,
    skipped: snapshot.skipped,
  );
}

/// V2 geçiş yolu; üretim cutover kabul kapıları geçmeden varsayılan yapılmaz.
Future<int> syncRemoteChanges({
  required ListingStore store,
  required RemoteCatalogueClient client,
}) async {
  var after = await store.remoteCursor();
  int? watermark;
  while (true) {
    final page = await client.fetchChanges(after: after, watermark: watermark);
    watermark ??= page.watermark;
    await store.applyDeltaPage(page, after: after);
    after = page.appliedThrough;
    if (!page.hasMore) return after;
  }
}
