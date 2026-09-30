import 'dart:async';
import 'dart:io';

import 'package:kamubul_backend/src/api.dart';
import 'package:kamubul_backend/src/config.dart';
import 'package:kamubul_backend/src/rate_limit.dart';
import 'package:kamubul_backend/src/runtime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// API sunucusu (Cloud Run hizmeti ya da VPS). Günlükte yalnızca yöntem, yol
/// ve durum kodu vardır: sorgu, IP ve Authorization başlığı yazılmaz.
Future<void> main() async {
  final config = BackendConfig.fromEnv(Platform.environment);
  final storage = await buildStorage(config);
  final api = ApiHandler(
    storage: storage,
    writeLimiter: RateLimiter(maxPerWindow: config.writesPerHourPerIp),
  );
  final handler = const Pipeline()
      .addMiddleware(_secureAndLog)
      .addHandler(api.call);
  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln('KamuBul API :${server.port} (depolama: ${config.storage})');

  Future<void> shutdown(ProcessSignal _) async {
    await server.close(force: false);
    await storage.close();
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}

Middleware get _secureAndLog =>
    (inner) => (request) async {
      final response = await inner(request);
      stdout.writeln(
        '${request.method} /${request.url.path} ${response.statusCode}',
      );
      return response.change(
        headers: {
          'X-Content-Type-Options': 'nosniff',
          'Referrer-Policy': 'no-referrer',
        },
      );
    };
