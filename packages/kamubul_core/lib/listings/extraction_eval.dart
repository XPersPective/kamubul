/// PB-007 ölçüm motoru: çıkarıcı çıktılarını altın etiketlerle karşılaştırır.
///
/// Sözleşme (altın üretimiyle aynı):
///  - altın null + çıkarılan değer = FP (yanlış bilgi göstermek "hatasız" değil)
///  - altın değer + çıkarılan null = FN (kayıp; recall düşer, kabul edilebilir)
///  - farklı değerler = FP + FN
///  - alıntılar kaynak metinde birebir alt dize olmalı
///  - karşılaştırma: boşluk sıkıştırma + Türkçe büyük harf katlama
library;

import '../data/turkish_cities.dart' show foldTurkish;
import 'extract_conditions.dart';
import 'sbb_feed.dart';

/// Kariyer şart alanları (extractConditions).
const kariyerFieldNames = [
  'kpssType',
  'kpssScore',
  'maxAge',
  'education',
  'quotaType',
];

/// SBB liste alanları (parseSbbListings).
const sbbFieldNames = [
  'institution',
  'title',
  'category',
  'start',
  'deadline',
  'quota',
];

/// Bir alanın TP/FP/FN sayaçları ve uyuşmazlık notları.
class FieldEval {
  FieldEval(this.field);

  final String field;
  int tp = 0;
  int fp = 0;
  int fn = 0;
  int tn = 0;
  final List<String> mismatches = [];

  double get precision => (tp + fp) == 0 ? 1.0 : tp / (tp + fp);

  double get recall => (tp + fn) == 0 ? 1.0 : tp / (tp + fn);
}

/// Kaynak başına alan skorları ve alıntı ihlalleri.
class EvalReport {
  EvalReport(this.source, this.fields);

  final String source;
  final List<FieldEval> fields;
  final List<String> quoteIssues = [];

  FieldEval field(String name) => fields.firstWhere((f) => f.field == name);
}

/// Etiket karşılaştırma normalizasyonu.
String normalizeLabel(String value) =>
    foldTurkish(value.replaceAll(RegExp(r'\s+'), ' ').trim());

Object? _norm(Object? value) {
  if (value == null) return null;
  if (value is String) return normalizeLabel(value);
  if (value is DateTime) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }
  return value;
}

void _score(FieldEval score, Object? gold, Object? predicted, String id) {
  final g = _norm(gold);
  final p = _norm(predicted);
  if (g == null && p == null) {
    score.tn++;
    return;
  }
  if (g == null) {
    score.fp++;
    score.mismatches.add('$id: altın null ama çıkarılan $p');
    return;
  }
  if (p == null) {
    score.fn++;
    score.mismatches.add('$id: altın $g ama çıkarılmadı');
    return;
  }
  if (g == p) {
    score.tp++;
    return;
  }
  score.fp++;
  score.fn++;
  score.mismatches.add('$id: altın $g != çıkarılan $p');
}

Object? _goldValue(Object? cell) {
  if (cell == null) return null;
  final map = cell as Map<String, dynamic>;
  return map['value'];
}

void _checkQuote(
  EvalReport report,
  String id,
  String field,
  String? quote,
  String text,
) {
  if (quote == null) return;
  if (!text.contains(quote)) {
    report.quoteIssues.add('$id/$field: alıntı metinde yok: $quote');
  }
}

/// Kariyer korpusu ölçümü: metin → extractConditions → altın karşılaştırma.
EvalReport evaluateKariyerCorpus({
  required List<Map<String, dynamic>> records,
  required Map<String, dynamic> gold,
}) {
  final report = EvalReport('kariyer', [
    for (final name in kariyerFieldNames) FieldEval(name),
  ]);
  for (final record in records) {
    final id = record['id'] as String;
    final text = record['text'] as String;
    final cell = gold[id] as Map<String, dynamic>?;
    if (cell == null) {
      report.quoteIssues.add('$id: altın etikette yok');
      continue;
    }
    final fields = extractConditions(text);
    final predicted = <String, Object?>{
      'kpssType': fields.kpssType?.value,
      'kpssScore': fields.kpssScore?.value,
      'maxAge': fields.maxAge?.value,
      'education': fields.education?.value,
      'quotaType': fields.quotaType?.value,
    };
    final quotes = <String, String?>{
      'kpssType': fields.kpssType?.quote,
      'kpssScore': fields.kpssScore?.quote,
      'maxAge': fields.maxAge?.quote,
      'education': fields.education?.quote,
      'quotaType': fields.quotaType?.quote,
    };
    for (final name in kariyerFieldNames) {
      _score(report.field(name), _goldValue(cell[name]), predicted[name], id);
      _checkQuote(report, id, name, quotes[name], text);
      final goldQuote = (cell[name] as Map<String, dynamic>?)?['quote'];
      _checkQuote(report, id, name, goldQuote as String?, text);
    }
  }
  return report;
}

/// SBB korpusu ölçümü: satır HTML'i → parseSbbListings → altın karşılaştırma.
EvalReport evaluateSbbCorpus({
  required List<Map<String, dynamic>> records,
  required Map<String, dynamic> gold,
}) {
  final report = EvalReport('sbb', [
    for (final name in sbbFieldNames) FieldEval(name),
  ]);
  for (final record in records) {
    final id = record['id'] as String;
    final cell = gold[id] as Map<String, dynamic>?;
    if (cell == null) {
      report.quoteIssues.add('$id: altın etikette yok');
      continue;
    }
    final SbbListing listing;
    try {
      final parsed = parseSbbListings(
        record['raw'] as String,
        referenceYear: record['year'] as int?,
      );
      listing = parsed.firstWhere(
        (item) => item.url.queryParameters['kod'] == id,
        orElse: () => parsed.first,
      );
    } on FormatException catch (error) {
      report.quoteIssues.add('$id: SBB satırı ayrışmadı: ${error.message}');
      continue;
    }
    final predicted = <String, Object?>{
      'institution': listing.institution,
      'title': listing.title,
      'category': listing.category,
      'start': listing.start,
      'deadline': listing.deadline,
      'quota': listing.quota,
    };
    for (final name in sbbFieldNames) {
      _score(report.field(name), _goldValue(cell[name]), predicted[name], id);
    }
  }
  return report;
}
