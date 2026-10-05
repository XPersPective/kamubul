// Yayındaki Worker şart ayıklamasını (/api/v2/extract) Kariyer altın kümesine
// karşı ölçer (PB-017 kalite kapısı: alan başına kesinlik >= 0,95, >= 50 örnek).
// Gerçek model çağrısı yapar; sunucu önbelleği aynı metni tekrar ücretlendirmez.
//
//   dart run tool/eval_worker_extract.dart [https://kamubul-api.devx8585.workers.dev]
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:kamubul_core/kamubul_core.dart';

Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'https://kamubul-api.devx8585.workers.dev' : args.first;
  final dir = 'test/fixtures/eval';
  final records = File('$dir/kariyer.jsonl').readAsLinesSync().where((l) => l.trim().isNotEmpty).map((l) => jsonDecode(l) as Map<String, dynamic>);
  final gold = {
    for (final cell in (jsonDecode(File('$dir/gold_kariyer.json').readAsStringSync()) as Map).values)
      (cell as Map)['id']: cell,
  };
  final random = Random.secure();
  String newId() => List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  final ids = List.generate(3, (_) => newId());
  final client = HttpClient();
  final tally = <String, Map<String, int>>{};
  void add(String field, String kind) => (tally.putIfAbsent(field, () => {'tp': 0, 'fp': 0, 'fn': 0, 'extra': 0}))[kind] = tally[field]![kind]! + 1;
  var n = 0, failed = 0;
  final mismatches = <String>[];
  for (final record in records) {
    final g = gold[record['id']];
    if (g == null) continue;
    final request = await client.postUrl(Uri.parse('$base/api/v2/extract'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'installationId': ids[n % ids.length], 'text': record['text']}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    n++;
    if (response.statusCode != 200) {
      failed++;
      stderr.writeln('${record['id']}: HTTP ${response.statusCode} $body');
      continue;
    }
    final groups = ((jsonDecode(body) as Map)['groups'] as List).cast<Map>();
    void check(String field, Object? expected, Iterable<Object?> actual) {
      final values = actual.where((v) => v != null).toSet();
      if (expected == null) {
        if (values.isNotEmpty) add(field, 'extra');
      } else if (values.contains(expected)) {
        add(field, 'tp');
      } else if (values.isEmpty) {
        add(field, 'fn');
      } else {
        add(field, 'fp');
        mismatches.add('${record['id']} $field beklenen=$expected bulunan=$values');
      }
    }
    Object? v(String f) => (g[f] as Map?)?['value'];
    check('education', v('education'), [for (final x in groups) ...?(x['education'] as List?)]);
    check('kpssType', v('kpssType'), [for (final x in groups) x['kpssType']]);
    check('kpssScore', v('kpssScore') is num ? (v('kpssScore') as num).toDouble() : null, [for (final x in groups) (x['kpssScore'] as num?)?.toDouble()]);
    final age = g['maxAge'] as Map?;
    check('maxAge', age == null ? null : inclusiveMaxAge(age['value'] as int, age['quote'] as String), [for (final x in groups) x['maxAge']]);
  }
  client.close();
  print('örnek=$n hata=$failed');
  print('alan\ttp\tfp\tfn\textra\tkesinlik\tkapsama');
  var pass = true;
  tally.forEach((field, t) {
    final precision = t['tp']! + t['fp']! == 0 ? 1.0 : t['tp']! / (t['tp']! + t['fp']!);
    final recall = t['tp']! + t['fn']! == 0 ? 1.0 : t['tp']! / (t['tp']! + t['fn']!);
    if (precision < 0.95) pass = false;
    print('$field\t${t['tp']}\t${t['fp']}\t${t['fn']}\t${t['extra']}\t${precision.toStringAsFixed(2)}\t${recall.toStringAsFixed(2)}');
  });
  for (final m in mismatches) {
    print('  çelişki: $m');
  }
  print(pass ? 'KAPI: GEÇTİ (kesinlik >= 0,95)' : 'KAPI: KALDI');
  exitCode = pass ? 0 : 1;
}
