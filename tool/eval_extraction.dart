import 'dart:convert';
import 'dart:io';

import 'package:kamubul/listings/extraction_eval.dart';
import 'package:kamubul/listings/extraction_policy.dart';

/// PB-007 ölçüm CLI'sı: çıkarıcıyı altın etiketlere karşı ölçer.
///
/// Kullanım: `dart run tool/eval_extraction.dart [--verbose]`
///
/// Çıkış kodu: politikası açık her alan precision >= kExtractionPrecisionBar
/// ve alıntı ihlali yoksa 0, aksi halde 1.
Future<void> main(List<String> args) async {
  final verbose = args.contains('--verbose');
  final evalDir = Directory('test/fixtures/eval');

  final kariyerRecords = _readJsonl('${evalDir.path}/kariyer.jsonl');
  final sbbRecords = _readJsonl('${evalDir.path}/sbb.jsonl');
  final goldKariyer = _goldById(
    _readJson('${evalDir.path}/gold_kariyer.json') as Map<String, dynamic>,
  );
  final goldSbb = _readJson('${evalDir.path}/gold_sbb.json')
      as Map<String, dynamic>;

  final reports = [
    evaluateKariyerCorpus(records: kariyerRecords, gold: goldKariyer),
    evaluateSbbCorpus(records: sbbRecords, gold: goldSbb),
  ];

  var failed = false;
  for (final report in reports) {
    stdout.writeln('== ${report.source.toUpperCase()} ==');
    stdout.writeln(
      '${'alan'.padRight(12)} TP   FP   FN   precision  recall  politika',
    );
    for (final field in report.fields) {
      final enabled = kExtractionPolicy[field.field] ?? false;
      final ok = !enabled || field.precision >= kExtractionPrecisionBar;
      if (!ok) failed = true;
      stdout.writeln(
        '${field.field.padRight(12)} '
        '${field.tp.toString().padRight(4)} '
        '${field.fp.toString().padRight(4)} '
        '${field.fn.toString().padRight(4)} '
        '${field.precision.toStringAsFixed(3).padRight(10)} '
        '${field.recall.toStringAsFixed(3).padRight(8)} '
        '${enabled ? (ok ? 'AÇIK' : 'AÇIK/DÜŞÜK') : 'kapalı'}',
      );
      if (verbose) {
        for (final note in field.mismatches) {
          stdout.writeln('    $note');
        }
      }
    }
    if (report.quoteIssues.isNotEmpty) {
      failed = true;
      for (final issue in report.quoteIssues) {
        stderr.writeln('ALINTI: $issue');
      }
    }
    stdout.writeln('');
  }

  if (failed) {
    stderr.writeln(
      'ÖLÇÜM BAŞARISIZ: politikası açık alanlar '
      'precision >= $kExtractionPrecisionBar altında ya da alıntı ihlali var. '
      'Çıkarıcıyı düzeltin ya da extraction_policy.dart içinde kapatın.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('ÖLÇÜM GEÇTİ: politikası açık tüm alanlar çubukta.');
}

List<Map<String, dynamic>> _readJsonl(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((line) => line.trim().isNotEmpty)
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();

dynamic _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync());

/// Kariyer altını sıra anahtarıyla gelir; kimliğe çevirir.
Map<String, dynamic> _goldById(Map<String, dynamic> byIndex) => {
      for (final cell in byIndex.values)
        (cell as Map<String, dynamic>)['id'] as String: cell,
    };
