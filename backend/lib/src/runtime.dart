/// Yapılandırmadan çalışma zamanı nesnelerini kurar (depolama, push, AI,
/// kaynaklar). Google kimlik bilgileri ortamdan çözülür: Cloud Run'da
/// metadata sunucusu, başka yerde `GOOGLE_APPLICATION_CREDENTIALS`.
library;

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:kamubul_core/kamubul_core.dart';

import 'config.dart';
import 'file_storage.dart';
import 'firestore_storage.dart';
import 'pipeline.dart';
import 'push.dart';
import 'sources.dart';
import 'storage.dart';

const List<String> _googleScopes = [
  'https://www.googleapis.com/auth/cloud-platform',
];

Future<http.Client> googleClient() =>
    clientViaApplicationDefaultCredentials(scopes: _googleScopes);

Future<Storage> buildStorage(BackendConfig config) async {
  if (config.storage == 'firestore') {
    return FirestoreStorage(
      client: await googleClient(),
      projectId: config.gcpProject!,
    );
  }
  return FileStorage(config.dataDir);
}

Future<PushSender> buildPush(
  BackendConfig config,
  void Function(String) log,
) async {
  switch (config.push) {
    case 'fcm':
      return FcmPushSender(
        client: await googleClient(),
        projectId: config.gcpProject!,
      );
    case 'off':
      return NoPushSender();
    default:
      return LogPushSender(log);
  }
}

List<SourceAdapter> buildSources(BackendConfig config) => [
  KariyerSource(),
  SbbSource(),
  if (config.probeSources) ...[
    ProbeSource(
      id: 'iskur',
      name: 'İŞKUR',
      url: Uri.parse('https://esube.iskur.gov.tr/'),
    ),
    ProbeSource(
      id: 'ilan_gov_tr',
      name: 'İlan.gov.tr',
      url: Uri.parse('https://ilan.gov.tr/'),
    ),
  ],
];

AiEnricher? buildEnricher(BackendConfig config) {
  final llm = config.llm;
  final policy = config.aiPolicy;
  if (llm == null || (policy.enabledFields.isEmpty && !policy.summaryEnabled)) {
    return null;
  }
  return AiEnricher(
    client: llm.build(),
    policy: policy,
    budget: TokenBudget(config.aiBudgetTokens),
  );
}

Future<PipelineDeps> buildPipeline(
  BackendConfig config,
  Storage storage,
  void Function(String) log,
) async => PipelineDeps(
  storage: storage,
  sources: buildSources(config),
  push: await buildPush(config, log),
  detailLoader: (uri) => loadKariyerDetail(uri),
  enricher: buildEnricher(config),
  detailFetchLimit: config.detailFetchLimit,
  requestDelay: config.requestDelay,
  log: log,
);
