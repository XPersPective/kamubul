import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/main.dart';
import 'package:kamubul/ui/pro_page.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

class _Store implements StoreAdapter {
  bool available = false;
  bool restoreFails = false;
  int buys = 0;
  final updatesController =
      StreamController<List<StorePurchaseUpdate>>.broadcast();

  @override
  Stream<List<StorePurchaseUpdate>> get updates => updatesController.stream;

  @override
  Future<void> restore() async {
    if (restoreFails) throw StateError('store unavailable');
  }

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async =>
      available ? const [StoreProduct(id: 'p', price: '₺58,99')] : const [];

  @override
  Future<void> buy(StoreProduct product) async {
    buys++;
  }
}

void main() {
  testWidgets(
    'purchase is deduplicated, cancel recovers, restore errors are visible at two sizes',
    (tester) async {
      final translations = await tester.runAsync(loadAppTranslations);
      if (const bool.fromEnvironment('KAMUBUL_CAPTURE')) {
        await tester.runAsync(() async {
          final root = Platform.environment['FLUTTER_ROOT']!;
          for (final font in {
            'Roboto': 'roboto-regular.ttf',
            'MaterialIcons': 'materialicons-regular.otf',
          }.entries) {
            await (FontLoader(font.key)..addFont(
                  File('$root/bin/cache/artifacts/material_fonts/${font.value}')
                      .readAsBytes()
                      .then(ByteData.sublistView),
                ))
                .load();
          }
        });
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [390.0, 900.0]) {
        tester.view.physicalSize = Size(width, 1100);
        final adapter = _Store()..available = true;
        final repository = PurchaseRepository(adapter: adapter, productId: 'p');
        final pro = ProController(
          store: SettingsStore(),
          repository: repository,
        )..startListening();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto'),
              locale: const Locale('tr'),
              supportedLocales: const [Locale('tr')],
              localizationsDelegates: [
                NappLocalizationsDelegate(translations!),
                ...GlobalMaterialLocalizations.delegates,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(width == 900 ? 2 : 1)),
                child: child!,
              ),
              home: ProPage(
                identity: AppIdentity(
                  appName: 'KamuBul',
                  packageName: 'com.crazypenguin.kamubul',
                  sourceUrl: 'https://github.com/XPersPective/kamubul',
                  privacyPolicyUrl: 'https://example.org/privacy',
                  contactEmail: 'test@example.org',
                ),
                controller: pro,
                repository: repository,
                trialDays: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buy = find.widgetWithText(FilledButton, 'Aylık aboneliği başlat');
        await tester.scrollUntilVisible(
          buy,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('₺58,99 / ay'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('KAMUBUL_CAPTURE')) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('.project-brain/.cache/paywall-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(buy);
        await tester.pump();
        expect(tester.widget<FilledButton>(buy).onPressed, isNull);
        expect(adapter.buys, 1);
        adapter.updatesController.add([
          StorePurchaseUpdate(
            purchase: const StorePurchase(
              productId: 'p',
              status: StorePurchaseStatus.canceled,
            ),
            complete: () async {},
          ),
        ]);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(buy).onPressed, isNotNull);
        adapter.restoreFails = true;
        final restore = find.text('Satın alımı geri yükle');
        await tester.scrollUntilVisible(
          restore,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(restore);
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(pro.isPro, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await repository.dispose();
          await adapter.updatesController.close();
        });
        pro.dispose();
      }
    },
  );
  testWidgets('"Ödeme beklemede" yalnız mağaza beklemede bildirince görünür', (
    tester,
  ) async {
    final translations = await tester.runAsync(loadAppTranslations);
    // Satın alma alanı sayfanın altında: tembel liste onu kurabilsin.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final adapter = _Store();
    final repository = PurchaseRepository(adapter: adapter, productId: 'p');
    // Ödüllü reklam ya da abonelik denetimi geçici Pro süresi bırakabilir;
    // bu bir ödeme değildir.
    final pro = ProController(store: SettingsStore(), repository: repository)
      ..grantTemporaryPro(Duration.zero);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        localizationsDelegates: [
          NappLocalizationsDelegate(translations!),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: ProPage(
          identity: AppIdentity(
            appName: 'KamuBul',
            packageName: 'com.crazypenguin.kamubul',
            sourceUrl: 'https://github.com/XPersPective/kamubul',
            privacyPolicyUrl: 'https://example.org/privacy',
            contactEmail: 'destek@kamubul.app',
          ),
          controller: pro,
          repository: repository,
          trialDays: 6,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Satın alımı geri yükle'), findsOneWidget);
    expect(find.textContaining('beklemede'), findsNothing);

    adapter.updatesController.add([
      StorePurchaseUpdate(
        purchase: const StorePurchase(
          productId: 'p',
          status: StorePurchaseStatus.pending,
        ),
        complete: () async {},
      ),
    ]);
    // Yayın akışı olayı bir mikro görevde gelir; ikinci kare setState'i çizer.
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('beklemede'), findsOneWidget);
  });
}
