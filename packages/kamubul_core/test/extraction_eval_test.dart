import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:kamubul_core/listings/extraction_eval.dart';
import 'package:kamubul_core/listings/extraction_policy.dart';

/// PB-007 CI kapısı: politikası AÇIK her alan precision çubuğunda olmalı.
///
/// Çıkarıcı bir alanın doğruluğunu düşürürse test kırılır; çözüm ya
/// çıkarıcıyı düzeltmek ya da `extraction_policy.dart` içinde o alanı
/// kapatıp arayüzü ham metne düşürmektir.
void main() {
  final evalDir = Directory('test/fixtures/eval');

  List<Map<String, dynamic>> readJsonl(String name) =>
      File('${evalDir.path}/$name')
          .readAsStringSync()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();

  Map<String, dynamic> readJson(String name) =>
      jsonDecode(File('${evalDir.path}/$name').readAsStringSync())
          as Map<String, dynamic>;

  late EvalReport kariyer;
  late EvalReport sbb;

  setUpAll(() {
    final goldKariyer = readJson('gold_kariyer.json');
    kariyer = evaluateKariyerCorpus(
      records: readJsonl('kariyer.jsonl'),
      gold: {
        for (final cell in goldKariyer.values)
          (cell as Map<String, dynamic>)['id'] as String: cell,
      },
    );
    sbb = evaluateSbbCorpus(
      records: readJsonl('sbb.jsonl'),
      gold: readJson('gold_sbb.json'),
    );
  });

  test('politika haritası bilinen her alanı kapsar', () {
    for (final name in [...kariyerFieldNames, ...sbbFieldNames]) {
      expect(
        kExtractionPolicy.containsKey(name),
        isTrue,
        reason: '$name politika haritasında yok; kapı sessizce atlanır',
      );
    }
  });

  for (final entry in {
    'kariyer': kariyerFieldNames,
    'sbb': sbbFieldNames,
  }.entries) {
    for (final name in entry.value) {
      test('${entry.key}/$name politika açık ve '
          'precision >= $kExtractionPrecisionBar', () {
        final report = entry.key == 'kariyer' ? kariyer : sbb;
        final field = report.field(name);
        expect(
          kExtractionPolicy[name],
          isTrue,
          reason:
              '$name politikası kapalıysa bu test bilerek ayarlanmalı; '
              'açık kalacaksa çıkarıcı düzeltilmeli',
        );
        expect(
          field.precision,
          greaterThanOrEqualTo(kExtractionPrecisionBar),
          reason:
              'FP=${field.fp} FN=${field.fn} TP=${field.tp} — '
              '${field.mismatches.take(5).join(' | ')}',
        );
      });
    }
  }

  test('tüm alıntılar kaynak metinde birebir alt dizedir', () {
    expect(kariyer.quoteIssues, isEmpty);
    expect(sbb.quoteIssues, isEmpty);
  });
}
