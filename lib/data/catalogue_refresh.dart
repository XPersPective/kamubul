import 'dart:convert';

import 'package:kamubul_core/kamubul_core.dart';

import 'listing_store.dart';
import 'remote_sync.dart';

class CatalogueRefreshResult {
  const CatalogueRefreshResult(
    this.checkedAt,
    this.failedSources, {
    this.sourceStatuses = const [],
    this.remoteLastSuccess,
    this.remoteFailed = false,
  });

  final DateTime checkedAt;
  final List<String> failedSources;
  final List<SourceStatus> sourceStatuses;
  final DateTime? remoteLastSuccess;
  final bool remoteFailed;
}

/// Kaynakları yalnız sunucu okur. Ağ hatasında son başarılı katalog korunur.
Future<CatalogueRefreshResult> refreshCatalogue(
  ListingStore store, {
  RemoteCatalogueClient? remote,
  DateTime? at,
}) async {
  final now = at ?? DateTime.now();
  var statuses = const <SourceStatus>[];
  DateTime? lastSuccess;
  final client = remote ?? defaultRemoteClient();
  if (client == null) {
    return CatalogueRefreshResult(now, const [], remoteFailed: true);
  }
  try {
    final generation = await store.bindRemoteOrigin(catalogueOrigin(client));
    final cached = await store.remoteMetadata(expectedGeneration: generation);
    lastSuccess = cached.lastSuccess;
    if (cached.metadata != null) {
      try {
        statuses = CatalogueMetadata.decode(jsonDecode(cached.metadata!))
            .sources;
      } on FormatException {
        // Bozuk metadata katalogu silmez; sunucu koşulsuz yeniden okunur.
      }
    }
    final metadata = await syncRemoteV2Catalogue(
      store: store,
      client: client,
      now: now,
    );
    return CatalogueRefreshResult(
      now,
      const [],
      sourceStatuses: metadata.sources,
      remoteLastSuccess: now,
    );
  } on Exception {
    return CatalogueRefreshResult(
      now,
      const [],
      sourceStatuses: statuses,
      remoteLastSuccess: lastSuccess,
      remoteFailed: true,
    );
  } finally {
    if (remote == null) client.close();
  }
}
