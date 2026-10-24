import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/main.dart' as app;

/// App Store ekran görüntüleri: gerçek uygulama, canlı katalog, iOS simülatörü.
/// `flutter test integration_test/store_capture_test.dart -d <simulator>`;
/// iş akışı STORE_CAPTURE satırlarında `simctl io screenshot` alır.
Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Mağaza görüntüsünde DEBUG şeridi görünmesin.
  WidgetsApp.debugAllowBannerOverride = false;

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

  Future<void> capture(WidgetTester tester, String name) async {
    // ignore: avoid_print
    print('STORE_CAPTURE $name');
    await settle(tester, 4);
  }

  Finder cards() => find.descendant(
    of: find.byType(Card),
    matching: find.byType(InkWell),
  );

  testWidgets('mağaza görüntüleri', (tester) async {
    // ignore: avoid_print
    print('STORE_STEP main');
    await app.main();
    // ignore: avoid_print
    print('STORE_STEP started');
    await settle(tester, 3);
    final skip = find.text('Atla');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await settle(tester);
    }
    await waitFor(tester, cards());
    await settle(tester, 4);
    await capture(tester, '02-ilanlar');

    await tester.tap(cards().first);
    await settle(tester, 4);
    await capture(tester, '03-ilan-sartlari');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
    await settle(tester);
    await capture(tester, '04-kadrolar');
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await settle(tester);

    for (final (tab, name) in [
      ('Asistan', '01-asistan'),
      ('Kaydedilen', '05-kaydedilen'),
      ('Ayarlar', '06-ayarlar'),
    ]) {
      await tester.tap(find.text(tab).last);
      await settle(tester, 3);
      await capture(tester, name);
    }
  });
}
