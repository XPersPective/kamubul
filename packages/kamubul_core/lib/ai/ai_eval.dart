/// Yapay zekâ adayı için ölçüm çekirdeği (C-005).
///
/// Bir alan ancak altın etiketlere karşı precision >= [kExtractionPrecisionBar]
/// ölçüldüğünde `AI_FIELDS` ile açılabilir. Yapay zekâ yalnızca deterministik
/// çıkarıcının boş bıraktığı alanı doldurduğu için ölçüm de yalnızca o
/// dolgulara bakar: doğru dolgu TP, yanlış ya da altın etiketi olmayan dolgu FP.
library;

import '../listings/extract_conditions.dart';
import '../listings/extraction_policy.dart';
import 'enrichment.dart';

class AiFieldScore {
  AiFieldScore(this.field);

  final String field;
  int tp = 0;
  int fp = 0;
  int abstained = 0;
  final List<String> mismatches = [];

  int get filled => tp + fp;
  double get precision => filled == 0 ? 1 : tp / filled;
  bool get passes => precision >= kExtractionPrecisionBar;
}

class AiEvalReport {
  AiEvalReport(this.fields, this.evaluated, this.skipped, this.tokens);

  final Map<String, AiFieldScore> fields;
  final int evaluated;
  final int skipped;
  final int tokens;
}

Object? _detValue(ConditionFields f, String name) => switch (name) {
  'maxAge' => f.maxAge?.value,
  'education' => f.education?.value,
  'kpssType' => f.kpssType?.value,
  'quotaType' => f.quotaType?.value,
  _ => null,
};

Object? _aiValue(AiEnrichment e, String name) => switch (name) {
  'maxAge' => e.maxAge?.value,
  'education' => e.education?.value,
  'kpssType' => e.kpssType?.value,
  'quotaType' => e.quotaType?.value,
  _ => null,
};

/// [records]: `id`, `title`, `text` alanlı korpus; [goldById]: kimliğe göre
/// `{alan: {value, quote} | null}`. [limit] maliyeti sınırlar.
Future<AiEvalReport> evaluateAi({
  required List<Map<String, dynamic>> records,
  required Map<String, dynamic> goldById,
  required AiEnricher enricher,
  int? limit,
  ConditionFields Function(String text) extract = extractConditions,
}) async {
  final scores = {for (final name in kAiFieldNames) name: AiFieldScore(name)};
  var evaluated = 0;
  var skipped = 0;
  for (final record in records.take(limit ?? records.length)) {
    final id = record['id'] as String;
    final gold = goldById[id] as Map<String, dynamic>?;
    if (gold == null) continue;
    final text = record['text'] as String;
    final result = await enricher.enrich(
      title: record['title'] as String? ?? '',
      text: text,
    );
    if (result.enrichment == null) {
      skipped++;
      continue;
    }
    evaluated++;
    final deterministic = extract(text);
    for (final name in kAiFieldNames) {
      if (_detValue(deterministic, name) != null) continue;
      final predicted = _aiValue(result.enrichment!, name);
      final score = scores[name]!;
      if (predicted == null) {
        score.abstained++;
        continue;
      }
      final goldCell = gold[name];
      final goldValue = goldCell is Map ? goldCell['value'] : null;
      if (goldValue == predicted) {
        score.tp++;
      } else {
        score.fp++;
        score.mismatches.add('$id $name: model=$predicted altın=$goldValue');
      }
    }
  }
  return AiEvalReport(scores, evaluated, skipped, enricher.budget.used);
}
