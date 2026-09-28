import 'dart:io';

import 'package:kamubul/listings/rg_feed.dart';

/// Resmî Gazete canlı kontrolü: dünkü gazetede personel alımı duyuruları.
Future<void> main() async {
  final notices = await loadRgPersonnelNotices();
  for (final notice in notices.take(3)) {
    stdout.writeln('${notice.url}\n  ${notice.title}');
  }
  stdout.writeln('${notices.length} RG duyurusu canlı olarak okundu.');
}
