/// Ortam değişkenlerinden okunan arka uç ayarı. Sırlar (AI anahtarı, servis
/// hesabı) yalnızca ortamdan gelir; günlüğe ve hatalara yazılmaz.
library;

import 'package:kamubul_core/kamubul_core.dart';

class BackendConfig {
  const BackendConfig({
    required this.storage,
    required this.dataDir,
    required this.gcpProject,
    required this.push,
    required this.port,
    required this.llm,
    required this.aiPolicy,
    required this.aiBudgetTokens,
    required this.probeSources,
    required this.detailFetchLimit,
    required this.requestDelay,
    required this.writesPerHourPerIp,
    required this.scheduleTimes,
  });

  /// `firestore` (Google öncelikli) veya `file` (taşınabilir).
  final String storage;
  final String dataDir;
  final String? gcpProject;

  /// `fcm`, `log` (yalnızca günlüğe yaz) veya `off`.
  final String push;
  final int port;
  final LlmConfig? llm;
  final AiEnrichmentPolicy aiPolicy;
  final int aiBudgetTokens;
  final bool probeSources;
  final int detailFetchLimit;
  final Duration requestDelay;
  final int writesPerHourPerIp;

  /// `SCHEDULE_TIMES=08:00,13:00,18:00` (Türkiye saati) verilirse iş kendi
  /// zamanlayıcısıyla döner; boşsa tek seferlik çalışır (Cloud Scheduler/cron).
  final List<String> scheduleTimes;

  static BackendConfig fromEnv(Map<String, String> env) {
    final storage = (env['STORAGE'] ?? 'file').trim().toLowerCase();
    if (storage != 'file' && storage != 'firestore') {
      throw ArgumentError.value(storage, 'STORAGE', 'file|firestore');
    }
    final push = (env['PUSH'] ?? 'log').trim().toLowerCase();
    if (!const {'fcm', 'log', 'off'}.contains(push)) {
      throw ArgumentError.value(push, 'PUSH', 'fcm|log|off');
    }
    final project = (env['GCP_PROJECT'] ?? env['GOOGLE_CLOUD_PROJECT'] ?? '')
        .trim();
    if ((storage == 'firestore' || push == 'fcm') && project.isEmpty) {
      throw ArgumentError('GCP_PROJECT gerekli (firestore/fcm için)');
    }
    int number(String key, int fallback, {int min = 0, int max = 1 << 30}) {
      final value = int.tryParse(env[key] ?? '');
      return value != null && value >= min && value <= max ? value : fallback;
    }

    final times = (env['SCHEDULE_TIMES'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(e))
        .toList();
    return BackendConfig(
      storage: storage,
      dataDir: (env['DATA_DIR'] ?? 'data').trim(),
      gcpProject: project.isEmpty ? null : project,
      push: push,
      port: number('PORT', 8080, min: 1, max: 65535),
      llm: LlmConfig.fromEnv(env),
      aiPolicy: AiEnrichmentPolicy.fromEnv(env),
      aiBudgetTokens: number('AI_BUDGET_TOKENS', 300000),
      probeSources: env['PROBE_SOURCES'] == '1',
      detailFetchLimit: number('DETAIL_FETCH_LIMIT', 60, max: 500),
      requestDelay: Duration(
        milliseconds: number('REQUEST_DELAY_MS', 400, max: 10000),
      ),
      writesPerHourPerIp: number('WRITES_PER_HOUR_PER_IP', 30, min: 1),
      scheduleTimes: times,
    );
  }
}
