import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/home_page.dart';
import 'package:kamubul/listings/kariyer_detail_page.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/notifications/alert_service.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolate_db.dart';

/// PB-004 bildirim dokunuşu yönlendirmesi: yerel kayıt uygulama içi ayrıntıda,
/// budanmış kayıt resmî sayfada açılır.
///
/// Ağ kapalı tutulur; mağaza arayüzü sahte adaptörle beslenir.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('test: ağ kapalı');
}

class _FakeStore implements StoreAdapter {
  @override
  Future<List<StoreProduct>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<void> buy(StoreProduct product) async {}

  @override
  Future<void> restore() async {}

  @override
  Stream<List<StorePurchaseUpdate>> get updates => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  HttpOverrides.global = _NoNetwork();

  late String dbPath;

  setUpAll(() async {
    dbPath = await isolateListingsDb('alert_tap');
  });

  setUp(() async {
    alertTapUrl.value = null;
    await databaseFactory.deleteDatabase(dbPath);
    final store = ListingStore();
    final now = DateTime.now();
    await store.mergeFeed(
      [
        ListingRecord(
          url: 'https://kariyerkapisi.gov.tr/ilan/1',
          sourceId: 'kariyerkapisi',
          title: 'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
          category: 'Sözleşmeli Personel',
          publishedAt: now.subtract(const Duration(days: 1)),
          fetchedAt: now,
          deadline: now.add(const Duration(days: 3)),
          saved: true,
          savedAt: now,
        ),
        ListingRecord(
          url: 'https://ilan.gov.tr/ilan/2',
          sourceId: 'kamuilan_sbb',
          title: 'BELEDİYE BAŞKANLIĞI - Memur Alımı',
          category: 'Personel',
          publishedAt: now.subtract(const Duration(days: 2)),
          fetchedAt: now,
          deadline: now.add(const Duration(days: 10)),
        ),
      ],
      pruneBefore: DateTime(2000),
    );
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    final settings = SettingsStore();
    final theme = ThemeModeController(store: settings)..load();
    final policy = AdPolicy();
    final purchase = PurchaseRepository(
      adapter: _FakeStore(),
      productId: 'kamubul_pro_lifetime',
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: KamuHomePage(
          identity: AppIdentity(
            appName: 'KamuBul',
            packageName: 'com.crazypenguin.kamubul',
            sourceUrl: 'https://kariyerkapisi.gov.tr',
            privacyPolicyUrl: 'https://kariyerkapisi.gov.tr/gizlilik',
            contactEmail: 'test@example.com',
            iconAsset: 'assets/brand/kamubul_icon.png',
            brandColor: Color(0xFF17659C),
          ),
          store: settings,
          theme: theme,
          pro: ProController(store: settings, repository: purchase),
          purchase: purchase,
          policy: policy,
          banner: BannerAdController(policy: policy),
          rewarded: RewardedAdManager(policy: policy),
          saveAdState: () {},
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .text('TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
  }

  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('Kariyer bildirimi yerel ayrıntıyı açar', (tester) async {
    await pumpHome(tester);
    alertTapUrl.value = 'https://kariyerkapisi.gov.tr/ilan/1';
    await settleUntil(tester, find.byType(KariyerDetailPage));
    expect(find.byType(KariyerDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SBB bildirimi yerel özet sayfasını açar', (tester) async {
    await pumpHome(tester);
    alertTapUrl.value = 'https://ilan.gov.tr/ilan/2';
    await settleUntil(tester, find.byType(OfficialListingPage));
    expect(find.byType(OfficialListingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('budanmış kayıt sessiz kalır ve ayrıntı açmaz', (tester) async {
    await pumpHome(tester);
    alertTapUrl.value = 'https://kariyerkapisi.gov.tr/ilan/silinmis';
    // Dış açılış platform kanalı testte yok; yutulur ve çökme olmaz.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(KariyerDetailPage), findsNothing);
    expect(find.byType(OfficialListingPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
