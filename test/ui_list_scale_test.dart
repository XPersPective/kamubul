import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/home_page.dart';
import 'package:kamubul/ui/premium.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolate_db.dart';

/// PB-008 1.3x liste erişilebilirlik kontrolü: liste kartları ve ayarlar
/// yüzeyi büyük metin ölçeğinde taşmadan yerleşir.
///
/// Ağ kapalı tutulur (yenileme yerel katalogla çalışır gibi davranır);
/// mağaza arayüzü sahte adaptörle beslenir.
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
    dbPath = await isolateListingsDb('ui_list_scale');
    // Match the SDK font used by ui_golden_test; Ahem changes line widths.
    final config = File('.dart_tool/package_config.json');
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = config.absolute.uri.resolve(
      '${packages.singleWhere((p) => p['name'] == 'flutter')['rootUri']}/',
    );
    final fonts = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      fonts.addFont(
        File.fromUri(
          flutter.resolve(
            '../../bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
          ),
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File.fromUri(
          flutter.resolve(
            '../../bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ),
        ).readAsBytes().then(ByteData.sublistView),
      );
    await icons.load();
  });

  setUp(() async {
    await databaseFactory.deleteDatabase(dbPath);
    final store = ListingStore();
    // Fixed dates keep golden references stable across calendar days.
    final now = DateTime(2026, 1, 1);
    await store.mergeFeed(
      [
        ListingRecord(
          url: 'https://kariyerkapisi.gov.tr/ilan/1',
          sourceId: 'kariyerkapisi',
          title: 'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
          category: 'Sözleşmeli Personel',
          publishedAt: now.subtract(const Duration(days: 1)),
          fetchedAt: now,
          deadline: null,
          quota: 5,
          places: const ['ANKARA'],
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
          deadline: null,
          quota: 2,
          places: const ['İZMİR', 'KARŞIYAKA'],
          // Sunucu kaydı olmayan yerel satır yalnız kaydedilmişse listelenir.
          saved: true,
          savedAt: now,
        ),
      ],
      // İçe aktarma gibi: yerel önbudama yapılmaz.
      pruneBefore: DateTime(2000),
    );
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(390, 844),
    bool dark = false,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
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
        theme: premiumTheme(
          AppTheme.light(brandColor: const Color(0xFF17659C)),
        ),
        darkTheme: premiumTheme(
          AppTheme.dark(brandColor: const Color(0xFF17659C)),
        ),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
    // Yerel yükleme gerçek iş parçacığı sorgularıdır; sahte zaman
    // akışında görünmeleri için gerçek gecikme turu gerekir.
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

  testWidgets('kişiselleştirme ilk aramada doğrudan kriter editörünü açar', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Kriter ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Aramayı kaydet'), findsOneWidget);
    expect(find.text('Arama adı'), findsOneWidget);
    expect(find.text('KPSS puanınız (0–100)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Filtreler yatay kaymaz, alt satıra geçer (kullanıcı isteği); bu yüzden
  // ölçüt tipik telefon boyutu + büyük yazıdır.
  testWidgets('ilk ilan başlığı telefonda kaydırmadan okunur', (tester) async {
    await pumpHome(tester, size: const Size(390, 844), textScale: 1.3);
    final title = find.text(
      'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
    );
    expect(title, findsOneWidget);
    expect(
      tester.getBottomRight(title).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale, dark) in [
    (const Size(320, 700), 1.3, true),
    (const Size(844, 390), 1.3, false),
    (const Size(390, 844), 2.0, true),
  ]) {
    testWidgets('premium liste $size / $scale / dark=$dark taşmaz', (
      tester,
    ) async {
      await pumpHome(tester, size: size, textScale: scale, dark: dark);
      expect(find.text('Güncel kamu ilanları'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('azaltılmış hareket iskelet animasyonunu durdurur', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SkeletonBox(width: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('liste 1.3x metin ölçeğinde taşmasız yerleşir', (tester) async {
    await pumpHome(tester, textScale: 1.3);
    expect(
      find.text('TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)'),
      findsOneWidget,
    );
    expect(find.text('İlanı incele'), findsAtLeastNWidgets(1));
    expect(find.textContaining('5 kişi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Liste tembel kurar: ikinci kart görünür alana kaydırılır.
    for (var i = 0; i < 10; i++) {
      if (find
          .text('BELEDİYE BAŞKANLIĞI - Memur Alımı')
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('BELEDİYE BAŞKANLIĞI - Memur Alımı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ayarlar 1.3x metinde yedek satırlarıyla yerleşir', (
    tester,
  ) async {
    await pumpHome(tester, textScale: 1.3);
    await tester.tap(find.text('Ayarlar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Görünüm ve üyelik'), findsOneWidget);
    // ListView tembel kurar: her satır kendi kaydırma adımıyla doğrulanır.
    for (final row in [
      'Uygulamayı paylaş',
      'Puan ver',
      'Verileri dışa aktar',
      'Verileri içe aktar',
      'Hakkında ve lisanslar',
    ]) {
      await tester.scrollUntilVisible(
        find.text(row),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(row), findsOneWidget, reason: '"$row" satırı eksik');
    }
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('ana ekran ve ayarlar premium golden ($mode)', (tester) async {
      await pumpHome(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_phone_$mode.png'),
      );
      await tester.tap(find.text('Ayarlar'));
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_phone_$mode.png'),
      );
    });
  }
}
