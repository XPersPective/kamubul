import 'dart:io';

import 'package:kamubul_core/listings/extract_conditions.dart';
import 'package:kamubul_core/listings/kariyer_detail.dart';
import 'package:kamubul_core/listings/kariyer_feed.dart';

/// PB-007 kanıt aracı: canlı ilanlarda deterministik çıkarımın alan
/// kapsamını ölçer (kesinlik etiketi değil; alan bulunma oranı).
Future<void> main() async {
  final items = await loadKariyerFeed();
  var checked = 0;
  var kpssType = 0, kpssScore = 0, maxAge = 0, education = 0;
  for (final item in items.take(12)) {
    try {
      final detail = await loadKariyerDetail(item.url);
      final text = [
        detail.body,
        for (final position in detail.positions) position.conditions,
      ].join('\n');
      final fields = extractConditions(text);
      checked++;
      if (fields.kpssType != null) kpssType++;
      if (fields.kpssScore != null) kpssScore++;
      if (fields.maxAge != null) maxAge++;
      if (fields.education != null) education++;
      stdout.writeln(
        '${detail.institution.substring(0, detail.institution.length.clamp(0, 40))}: '
        'KPSS=${fields.kpssType?.value ?? '-'} puan=${fields.kpssScore?.value ?? '-'} '
        'yaş=${fields.maxAge?.value ?? '-'} eğitim=${fields.education?.value ?? '-'}',
      );
    } on Exception {
      // Okunamayan ilan kapsam dışı.
    }
  }
  stdout.writeln(
    '$checked ilan: KPSS türü %${(kpssType * 100 / (checked == 0 ? 1 : checked)).round()}, '
    'taban puan %${(kpssScore * 100 / (checked == 0 ? 1 : checked)).round()}, '
    'yaş %${(maxAge * 100 / (checked == 0 ? 1 : checked)).round()}, '
    'eğitim %${(education * 100 / (checked == 0 ? 1 : checked)).round()}',
  );
}
