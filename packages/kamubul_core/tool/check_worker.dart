import 'package:kamubul_core/kamubul_core.dart';

/// Kalıcı Worker'a yalnız okuma yapar; test kaydı veya bildirim üretmez.
Future<void> main(List<String> args) async {
  final client = RemoteCatalogueClient(
    baseUrl: Uri.parse(
      args.isEmpty ? 'https://kamubul-api.devx8585.workers.dev' : args.single,
    ),
  );
  try {
    var after = 0, count = 0;
    int? watermark;
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
      'Verified live Worker: watermark=$watermark, appliedThrough=$after, changes=$count',
    );
  } finally {
    client.close();
  }
}
