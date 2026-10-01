/// Sunucu kataloğunu yerel veritabanına işler.
///
/// V2 metadata ve immutable değişiklik sayfaları kalıcı SQLite cursor'a işlenir.
/// Sayfa kesilirse kayıt/cursor birlikte korunur; tüm senkronizasyon bitmeden
/// son başarı zamanı ilerlemez. Gömülü kaynakların geçiş sahibi refreshCatalogue'dır.
library;

import 'dart:convert';

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

/// Metadata/ETag kalıcıdır; başarılı tüm sayfalar sonrasında tazelik kaydedilir.
Future<CatalogueMetadata> syncRemoteV2Catalogue({
  required ListingStore store,
  required RemoteCatalogueClient client,
  required DateTime now,
}) async {
  final cached = await store.remoteMetadata();
  CatalogueMetadata? previous;
  try {
    if (cached.metadata != null) {
      previous = CatalogueMetadata.decode(jsonDecode(cached.metadata!));
    }
  } on FormatException {
    /* Bozuk metadata için koşulsuz GET; katalog/cursor korunur. */
  }
  final fetched = await client.fetchMetadata(
    etag: previous == null ? null : cached.etag,
  );
  final metadata = fetched.metadata ?? previous;
  if (metadata == null) {
    throw const RemoteCatalogueException('metadata missing after 304');
  }
  final cursor = await store.remoteCursor();
  if ((cursor == 0 && cached.metadata == null) ||
      cursor > metadata.latestSeq ||
      cursor + 1 < metadata.oldestRetainedSeq ||
      cached.pendingBootstrap) {
    await syncRemoteBootstrap(store: store, client: client, metadata: metadata);
  }
  await syncRemoteChanges(
    store: store,
    client: client,
    through: metadata.latestSeq,
  );
  await store.saveRemoteMetadata(
    jsonEncode(metadata.json),
    fetched.etag,
    now,
    expectedCursor: metadata.latestSeq,
  );
  return metadata;
}

/// Sayfa cache+cursor atomik; network failure bir sonraki açılışta devam eder.
Future<int> syncRemoteChanges({
  required ListingStore store,
  required RemoteCatalogueClient client,
  int? through,
}) async {
  var after = await store.remoteCursor();
  int? watermark = through;
  // ponytail: 20 pages per refresh; persisted cursor resumes a larger backlog next time.
  for (var i = 0; i < 20; i++) {
    if (after == watermark) return after;
    final page = await client.fetchChanges(after: after, watermark: watermark);
    watermark ??= page.watermark;
    await store.applyDeltaPage(page, after: after);
    after = page.appliedThrough;
    if (!page.hasMore) return after;
  }
  throw const RemoteCatalogueException('delta backlog; resume next refresh');
}

Future<void> syncRemoteBootstrap({
  required ListingStore store,
  required RemoteCatalogueClient client,
  required CatalogueMetadata metadata,
}) async {
  final state = await store.beginBootstrap(
    latest: metadata.latestSeq,
    oldest: metadata.oldestRetainedSeq,
  );
  var after = state.after;
  // ponytail: 20 pages per refresh; persistent staging resumes without discarding visible cache.
  for (var i = 0; i < 20; i++) {
    final page = await client.fetchCataloguePage(
      watermark: state.watermark,
      after: after,
    );
    await store.stageCataloguePage(page, after: after);
    if (page.next == null) return;
    after = page.next!;
  }
  throw const RemoteCatalogueException(
    'bootstrap backlog; resume next refresh',
  );
}
