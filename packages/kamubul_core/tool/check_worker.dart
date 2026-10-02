import 'package:kamubul_core/kamubul_core.dart';

/// Kalıcı Worker'a yalnız okuma yapar; test kaydı veya bildirim üretmez.
Future<void> main(List<String> args) async {
  final client = RemoteCatalogueClient(
    baseUrl: Uri.parse(
      args.isEmpty ? 'https://kamubul-api.devx8585.workers.dev' : args.single,
    ),
  );
  try {
    final meta = await client.fetchMetadata();
    if (meta.metadata == null) throw StateError('initial metadata missing');
    final conditional = await client.fetchMetadata(etag: meta.etag);
    var catalogueAfter = '', catalogueCount = 0;
    Map<String, Object?>? firstItem;
    do {
      final page = await client.fetchCataloguePage(
        watermark: meta.metadata!.latestSeq,
        after: catalogueAfter,
      );
      catalogueCount += page.items.length;
      if (firstItem == null && page.items.isNotEmpty) {
        firstItem = page.items.first;
      }
      if (catalogueCount > 10000) {
        throw StateError('bounded catalogue verification limit');
      }
      if (page.next == null) break;
      catalogueAfter = page.next!;
    } while (true);
    if (firstItem != null) {
      final detail = await client.fetchListing(firstItem['id'] as String);
      if (detail == null ||
          (detail['revision'] as int) < (firstItem['revision'] as int)) {
        throw StateError('live detail missing or older than catalogue');
      }
    }
    if (await client.fetchListing('kamubul:readonly-missing-probe') != null) {
      throw StateError('missing detail returned an item');
    }
    var after = 0, count = 0;
    int? watermark = meta.metadata!.latestSeq;
    do {
      final page = await client.fetchChanges(
        after: after,
        watermark: watermark,
      );
      watermark ??= page.watermark;
      count += page.changes.length;
      after = page.appliedThrough;
      if (!page.hasMore) break;
      if (count > 10000) throw StateError('bounded verification limit');
    } while (true);
    print(
      'Verified live Worker: watermark=$watermark, catalogue=$catalogueCount, appliedThrough=$after, changes=$count, detailChecked=${firstItem != null}, missingDetail=404, metadataConditional=${conditional.metadata == null ? 304 : 200}, sources=${meta.metadata!.sources.map((s) => '${s.id}:${s.state.name}').join(',')}',
    );
  } finally {
    client.close();
  }
}
