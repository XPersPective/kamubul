import 'dart:io';

import 'package:kamubul/listings/kariyer_feed.dart';

Future<void> main() async {
  final items = await loadKariyerFeed();
  if (items.isEmpty) throw StateError('Kariyer Kapısı akışı boş');
  stdout.writeln('${items.length} doğrulanmış Kariyer Kapısı ilanı okundu.');
}
