import 'dart:io';

import 'package:kamubul/listings/kariyer_detail.dart';
import 'package:kamubul/listings/kariyer_feed.dart';

/// Kariyer Kapısı ayrıntı okumalarının canlı kontrolü: ilk ilanın kurum,
/// kontenjan, son başvuru ve resmî başvuru bağlantısının okunduğunu doğrular.
Future<void> main() async {
  final items = await loadKariyerFeed();
  if (items.isEmpty) throw StateError('Kariyer Kapısı akışı boş');
  var ok = 0;
  for (final item in items.take(3)) {
    final detail = await loadKariyerDetail(item.url);
    if (detail.institution.isEmpty || detail.quota <= 0) {
      throw StateError('Ayrıntı eksik okundu: ${item.url}');
    }
    ok++;
    stdout.writeln(
      '${item.url}\n  kurum=${detail.institution} kontenjan=${detail.quota} '
      'yer=${detail.places.join('/')} son=${detail.deadline} '
      'basvuru=${detail.applyUrl ?? '-'}',
    );
  }
  stdout.writeln('$ok ilanın ayrıntısı canlı olarak doğrulandı.');
}
