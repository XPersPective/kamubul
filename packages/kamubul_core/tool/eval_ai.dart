import 'dart:convert';
import 'dart:io';

import 'package:kamubul_core/ai/ai_eval.dart';
import 'package:kamubul_core/kamubul_core.dart';

/// C-005 ölçüm CLI'sı: yapay zekâ adayını Kariyer altın etiketlerine karşı
/// ölçer. GERÇEK model çağrısı yapar ve para harcar; önce `--limit` ile küçük
/// başlayın.
///
///   AI_PROVIDER=anthropic AI_MODEL=... AI_API_KEY=... \
///     dart run tool/eval_ai.dart --limit 10 [--budget-tokens 400000] [--verbose]
///
/// Çıkış kodu: örnek olan her alanda precision >= 0.95 ise 0, aksi halde 1.
/// Geçen alanlar sunucuda `AI_FIELDS=maxAge,education,...` ile açılabilir.
Future<void> main(List<String> args) async {
  int? intArg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? int.tryParse(args[i + 1]) : null;
  }

  final config = LlmConfig.fromEnv(Platform.environment);
  if (config == null) {
    stderr.writeln('AI_PROVIDER/AI_MODEL/AI_API_KEY ayarlı değil.');
    exitCode = 64;
    return;
  }
  final limit = intArg('--limit') ?? 10;
  final budget = TokenBudget(intArg('--budget-tokens') ?? 400000);
  final enricher = AiEnricher(
    client: config.build(),
    policy: AiEnrichmentPolicy(
      enabledFields: kAiFieldNames,
      minConfidence: AiEnrichmentPolicy.fromEnv(Platform.environment)
          .minConfidence,
    ),
    budget: budget,
  );

  final dir = 'test/fixtures/eval';
  final records = File('$dir/kariyer.jsonl')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
  final gold = {
    for (final cell in (jsonDecode(
      File('$dir/gold_kariyer.json').readAsStringSync(),
    ) as Map<String, dynamic>).values)
      (cell as Map<String, dynamic>)['id'] as String: cell,
  };

  final report = await evaluateAi(
    records: records,
    goldById: gold,
    enricher: enricher,
    limit: limit,
  );
  stdout.writeln(
    '${config.provider}/${config.model}: ${report.evaluated} ilan ölçüldü, ${report.skipped} atlandı, ${report.tokens} token',
  );
  stdout.writeln('${'alan'.padRight(10)} doğru yanlış çekimser precision');
  var failed = false;
  for (final score in report.fields.values) {
    if (score.filled > 0 && !score.passes) failed = true;
    stdout.writeln(
      '${score.field.padRight(10)} ${score.tp.toString().padRight(5)} ${score.fp.toString().padRight(6)} '
      '${score.abstained.toString().padRight(8)} ${score.precision.toStringAsFixed(3)}'
      '${score.filled == 0
          ? "  (örnek yok)"
          : score.passes
          ? "  AÇILABİLİR"
          : "  KAPALI KALMALI"}',
    );
    if (args.contains('--verbose')) {
      for (final m in score.mismatches) {
        stdout.writeln('    $m');
      }
    }
  }
  exitCode = failed ? 1 : 0;
}
