import 'dart:io';

import 'package:kamubul/listings/kariyer_feed.dart';

Future<void> main() async {
  final items = await loadKariyerListings();
  if (items.isEmpty) throw StateError('Kariyer Kapısı akışı boş');
  final dated = items.where((item) => item.deadline != null).length;
  stdout.writeln(
    '${items.length} doğrulanmış Kariyer Kapısı ilanı okundu; '
    '$dated ilanda son başvuru tarihi var.',
  );
}
