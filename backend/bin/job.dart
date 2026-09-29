import 'dart:async';
import 'dart:io';

import 'package:kamubul_backend/src/config.dart';
import 'package:kamubul_backend/src/pipeline.dart';
import 'package:kamubul_backend/src/runtime.dart';
import 'package:kamubul_core/kamubul_core.dart';

/// Çekim işi. `SCHEDULE_TIMES` boşsa bir kez çalışır ve çıkar (Cloud Run Job +
/// Cloud Scheduler ya da cron). Doluysa (`08:00,13:00,18:00`, Türkiye saati)
/// kendi zamanlayıcısıyla döner: Cloud Scheduler olmayan tek konteyner/VPS
/// kurulumu için.
///
/// Çıkış kodu: hiçbir kaynak okunamadıysa 1, aksi halde 0.
Future<void> main() async {
  final config = BackendConfig.fromEnv(Platform.environment);
  final storage = await buildStorage(config);
  void log(String line) =>
      stdout.writeln('${DateTime.now().toUtc().toIso8601String()} $line');
  try {
    Future<RunReport> once() async =>
        runPipeline(await buildPipeline(config, storage, log));

    if (config.scheduleTimes.isEmpty) {
      final report = await once();
      exitCode = report.sourcesOk == 0 && report.sourcesFailed > 0 ? 1 : 0;
      return;
    }
    while (true) {
      final wait = _untilNext(config.scheduleTimes, DateTime.now().toUtc());
      log('sonraki çalışma ${wait.inMinutes} dk sonra');
      await Future<void>.delayed(wait);
      try {
        await once();
      } on Exception catch (error) {
        log('çalışma başarısız: ${error.runtimeType}');
      }
    }
  } finally {
    await storage.close();
  }
}

/// Türkiye saatine göre bir sonraki zamanlanmış slota kalan süre.
Duration _untilNext(List<String> times, DateTime nowUtc) {
  final wall = wallClock(nowUtc);
  Duration? best;
  for (final time in times) {
    final parts = time.split(':');
    var slot = DateTime(
      wall.year,
      wall.month,
      wall.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (!slot.isAfter(wall)) slot = slot.add(const Duration(days: 1));
    final diff = slot.difference(wall);
    if (best == null || diff < best) best = diff;
  }
  return best!;
}
