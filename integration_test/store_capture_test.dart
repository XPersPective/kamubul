import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/main.dart' as app;

/// App Store ekran görüntüleri: gerçek uygulama, canlı katalog, iOS simülatörü.
/// flutter drive --driver=test_driver/store_capture.dart
///   --target=integration_test/store_capture_test.dart
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int seconds = 2]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 600 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  Finder cards() => find.descendant(
    of: find.byType(Card),
    matching: find.byType(InkWell),
  );

  testWidgets('mağaza görüntüleri', (tester) async {
    await app.main();
    await settle(tester, 3);
    final skip = find.text('Atla');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await settle(tester);
    }
    await waitFor(tester, cards());
    await settle(tester, 4);
    await binding.takeScreenshot('02-ilanlar');

    await tester.tap(cards().first);
    await settle(tester, 4);
    await binding.takeScreenshot('03-ilan-sartlari');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
    await settle(tester);
    await binding.takeScreenshot('04-kadrolar');
    await tester.pageBack();
    await settle(tester);

    for (final (tab, name) in [
      ('Asistan', '01-asistan'),
      ('Kaydedilen', '05-kaydedilen'),
      ('Ayarlar', '06-ayarlar'),
    ]) {
      await tester.tap(find.text(tab).last);
      await settle(tester, 3);
      await binding.takeScreenshot(name);
    }
  });
}
