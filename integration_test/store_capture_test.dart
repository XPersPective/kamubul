import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/main.dart' as app;

/// App Store ekran görüntüleri: gerçek uygulama, canlı katalog ve canlı
/// Asistan yanıtı, iOS simülatörü. Sahne sırası Play'deki araştırma setiyle
/// aynıdır (docs/growth/STORE_COPY.md, tool/brand/ios_store_frames.py).
/// `flutter test integration_test/store_capture_test.dart -d <simulator>`;
/// görüntüler STORE_CAPTURE_DIR klasörüne yazılır.
const _dir = String.fromEnvironment(
  'STORE_CAPTURE_DIR',
  defaultValue: '/tmp/kamubul_store_capture',
);

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Mağaza görüntüsünde DEBUG şeridi görünmesin.
  WidgetsApp.debugAllowBannerOverride = false;

  Future<void> settle(WidgetTester tester, [int seconds = 2]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int seconds = 180,
  }) async {
    for (var i = 0; i < seconds * 10 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await settle(tester, 2);
    final bytes = await binding.takeScreenshot(name);
    File('$_dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  Finder cards() => find.descendant(
    of: find.byType(Card),
    matching: find.byType(InkWell),
  );

  void back(WidgetTester tester) =>
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await settle(tester, 2);
  }

  Future<void> theme(WidgetTester tester, String label) async {
    await tab(tester, 'Ayarlar');
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await settle(tester);
    await tester.tap(find.text(label).last);
    await settle(tester, 2);
    await tab(tester, 'İlanlar');
  }

  testWidgets('mağaza görüntüleri', (tester) async {
    await app.main();
    await settle(tester, 3);
    final skip = find.text('Atla');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await settle(tester);
    }

    // Açık tema sabitlenir; sistem görünümüne bağlı kalmaz.
    await theme(tester, 'Açık');
    await waitFor(tester, cards());
    await settle(tester, 4);
    await capture(tester, 'home-light');

    // Play setindeki gibi birden çok kadrolu gerçek bir ilan seçilir.
    var multi = false;
    for (var attempt = 0; attempt < 15; attempt++) {
      await tester.tap(cards().hitTestable().first);
      await settle(tester, 4);
      multi = find.text('Pozisyonlar').evaluate().isNotEmpty;
      if (multi) break;
      back(tester);
      await settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
      await settle(tester);
    }
    await capture(tester, 'detail-summary');
    final heading = find.text(multi ? 'Pozisyonlar' : 'Başvuru koşulları').first;
    await tester.scrollUntilVisible(
      heading,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester);
    await Scrollable.ensureVisible(tester.element(heading), alignment: 0.02);
    await settle(tester);
    await capture(tester, 'detail-positions');

    // Aynı ilan için gerçek Asistan sorusu ve yanıtı.
    await tester.tap(find.text('Asistana sor').last);
    await settle(tester, 3);
    await tester.enterText(
      find.byType(TextField).last,
      '28 yaşındayım, lisans mezunuyum, KPSS P3 puanım 78. '
      'Bu ilan bana uygun mu?',
    );
    await settle(tester);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await settle(tester, 2);
    // Yanıt gelene kadar gönder düğmesi devre dışıdır.
    for (var i = 0; i < 900; i++) {
      final send = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.send_rounded),
          matching: find.byType(IconButton),
        ),
      );
      if (send.onPressed != null) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, 3);
    await capture(tester, 'assistant');

    // Süzgeç uygulanmış liste (Play setindeki 5. sahne).
    await tab(tester, 'İlanlar');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await settle(tester);
    await tester.tap(find.text('Belediye').first);
    await settle(tester, 4);
    await capture(tester, 'searches');
    await tester.tap(find.text('Tümü').first);
    await settle(tester, 2);

    // Koyu tema sahneleri.
    await theme(tester, 'Koyu');
    await settle(tester, 2);
    await capture(tester, 'home-dark');
    await tester.tap(cards().hitTestable().first);
    await settle(tester, 4);
    await capture(tester, 'detail-dark');

    // App Store inceleme görüntüsü: Pro sayfası (yalnız IOS_PRO derlemesinde).
    if (const bool.fromEnvironment('IOS_PRO')) {
      back(tester);
      await settle(tester);
      await theme(tester, 'Açık');
      await tab(tester, 'Ayarlar');
      await tester.tap(find.text('KamuBul Pro').first);
      await settle(tester, 6);
      await capture(tester, 'pro-paywall');
    }
  });
}
