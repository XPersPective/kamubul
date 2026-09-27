import 'dart:io';

import 'package:kamubul/listings/sbb_feed.dart';

/// kamuilan.sbb.gov.tr canlı kontrolü: yıl listesi POST edilir, ilanların
/// kurum/kontenjan/tarih alanlarının okunduğu doğrulanır.
Future<void> main() async {
  final items = await loadSbbListings();
  if (items.isEmpty) throw StateError('SBB listesi boş');
  for (final item in items.take(3)) {
    stdout.writeln(
      '${item.url}\n  ${item.institution} • ${item.quota ?? "?"} kişi • '
      '${item.category} • ${item.start ?? "?"} - ${item.deadline ?? "?"}',
    );
  }
  stdout.writeln('${items.length} SBB ilanı canlı olarak okundu.');
}
