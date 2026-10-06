import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/main.dart';
import 'package:kamubul/ui/pro_page.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

class _Store implements StoreAdapter {
  final updatesController =
      StreamController<List<StorePurchaseUpdate>>.broadcast();

  @override
  Stream<List<StorePurchaseUpdate>> get updates => updatesController.stream;

  @override
  Future<void> restore() async {}

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => const [];

  @override
  Future<void> buy(StoreProduct product) async {}
}

void main() {
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
