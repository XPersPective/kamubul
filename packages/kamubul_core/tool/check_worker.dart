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
    do {
      final page = await client.fetchCataloguePage(
        watermark: meta.metadata!.latestSeq,
        after: catalogueAfter,
      );
      catalogueCount += page.items.length;
      if (catalogueCount > 10000) {
        throw StateError('bounded catalogue verification limit');
      }
      if (page.next == null) break;
      catalogueAfter = page.next!;
    } while (true);
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
      'Verified live Worker: watermark=$watermark, catalogue=$catalogueCount, appliedThrough=$after, changes=$count, metadataConditional=${conditional.metadata == null ? 304 : 200}, sources=${meta.metadata!.sources.map((s) => '${s.id}:${s.state.name}').join(',')}',
    );
  } finally {
    client.close();
  }
}
