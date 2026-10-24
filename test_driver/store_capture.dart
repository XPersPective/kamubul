import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Ekran görüntülerini build/store_capture/ altına yazar.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/store_capture/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
