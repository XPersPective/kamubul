import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/home_page.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolate_db.dart';

/// PB-005 profil düzenleme: kayıtlı aramanın adı ve profil alanları
/// (yaş/eğitim/KPSS) yönet listesinden düzenlenebilir.
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

/// Animasyonlu açılış ve gerçek veritabanı girişi için: sahte zaman
/// akışında yalnızca pump() ile izole yanıtları hiç işlemez; kısa gerçek
/// gecikme turları ikisini de ilerletir.
Future<void> pumpRoute(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  HttpOverrides.global = _NoNetwork();

  late String dbPath;
  late String searchName;
  late String updatedName;
  late String age;
  late String kpss;

  setUpAll(() async {
    dbPath = await isolateListingsDb('saved_search_edit');
  });

  setUp(() async {
    // Windows kilitleri dosya silmeyi engelleyebilir; bu yüzden artan
    // kayıtlar ayrıca temizlenir ve adlar benzersiz tutulur.
    await databaseFactory.deleteDatabase(dbPath);
    final store = ListingStore();
    for (final search in await store.savedSearches()) {
      final id = search.id;
      if (id != null) await store.deleteSavedSearch(id);
    }
    final now = DateTime.now();
    // Ad ve profil değerleri her koşulda benzersiz: kalan eski satırlarla
    // eşleşmez. Tohumlama setUp'tadır; test gövdesindeki gerçek veritabanı
    // işlemi sahte zaman akışında asla tamamlanmaz.
    final stamp = now.microsecondsSinceEpoch;
    searchName = 'DÜZENLE $stamp';
    updatedName = 'GÜNCEL $stamp';
    age = '42';
    kpss = 'P3';
    await store.mergeFeed([
      ListingRecord(
        url: 'https://kariyerkapisi.gov.tr/ilan/1',
        sourceId: 'kariyerkapisi',
        title: 'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
        category: 'Sözleşmeli Personel',
        publishedAt: now.subtract(const Duration(days: 1)),
        fetchedAt: now,
        deadline: now.add(const Duration(days: 3)),
      ),
    ], pruneBefore: DateTime(2000));
    await store.addSavedSearch(
      SavedSearch(
        id: null,
        name: searchName,
        filters: const {'sehir': 'ANKARA', 'yas': '30', 'kpss': 'P93'},
        createdAt: now,
      ),
    );
  });

  testWidgets('profil alanları yönet listesinden düzenlenebilir', (
    tester,
  ) async {
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

    await tester.tap(find.byTooltip('Kayıtlı aramaları yönet'));
    await pumpRoute(tester);
    var sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text(searchName)),
      findsOneWidget,
    );

    final menu = find.descendant(
      of: sheet,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menu);
    await pumpRoute(tester);
    await tester.tap(find.text('Düzenle'));
    await pumpRoute(tester);

    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Aramayı düzenle')),
      findsOneWidget,
    );
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), updatedName);
    await tester.enterText(fields.at(1), '999');
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Kaydet')),
    );
    await tester.pump();
    expect(find.textContaining('Kriterleri kontrol edin'), findsOneWidget);
    await tester.enterText(fields.at(1), age);
    await tester.enterText(fields.at(3), kpss);
    await tester.enterText(fields.at(4), '78,25');
    await tester.enterText(fields.at(5), '2024');
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Kaydet')),
    );
    await pumpRoute(tester);
    await pumpRoute(tester);

    // Düzenleme sonrası liste kapanır; yeniden açıldığında yeni değer görünür.
    await tester.tap(find.byTooltip('Kayıtlı aramaları yönet'));
    await pumpRoute(tester);
    sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text(updatedName)),
      findsOneWidget,
    );
    expect(find.text(searchName), findsNothing);
    expect(
      find.descendant(of: sheet, matching: find.textContaining('KPSS $kpss')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('yaş $age')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final search = (await ListingStore().savedSearches()).single;
      expect(search.effectiveCriteria.values['kpssScore'], 78.25);
      expect(search.effectiveCriteria.values['kpssYear'], 2024);
      expect(
        search.effectiveCriteria.values['ageAsOf'],
        '1970-01-01',
        reason: 'Eski yaş otomatik güncel varsayılmaz',
      );
      expect(search.filters['sehir'], 'ANKARA');
    });
    // Canonical koşul bulunmayan eski kayıt kesin eşleşme sayılmaz.
    await tester.tap(
      find.descendant(of: sheet, matching: find.text(updatedName)),
    );
    await pumpRoute(tester);
    expect(
      find.text('TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)'),
      findsNothing,
    );
    final uncertain = find.widgetWithText(FilterChip, 'Şartları kontrol et');
    await tester.ensureVisible(uncertain);
    await tester.tap(uncertain);
    await pumpRoute(tester);
    expect(
      find.text('TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)'),
      findsOneWidget,
    );
    expect(
      find.text('Şartları kontrol et • bazı kriterler doğrulanamadı.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
