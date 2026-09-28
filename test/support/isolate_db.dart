import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Paralel test koşuları aynı sqlite dosyasını paylaşırsa birbirinin
/// kayıtlarını görür; her test dosyası kendi klasörüne açılır.
///
/// Dönen değer, ListingStore'un açtığı kalıcı dosyanın yoludur.
Future<String> isolateListingsDb(String label) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = p.join(await databaseFactory.getDatabasesPath(), 'iso_$label');
  await Directory(dir).create(recursive: true);
  await databaseFactory.setDatabasesPath(dir);
  return p.join(dir, 'kamubul_listings.db');
}
