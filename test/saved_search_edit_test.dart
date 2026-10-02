import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/home_page.dart';
import 'package:kamubul_core/remote/catalogue_delta.dart';
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
    await store.applyDeltaPage(
      CatalogueDeltaPage(1, 1, false, [
        CatalogueChange(1, 'notice', 1, false, {
          'id': 'notice',
          'revision': 1,
          'url': 'https://kariyerkapisi.gov.tr/ilan/1',
          'title': 'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
          'sourceId': 'kariyerkapisi',
          'category': 'Sözleşmeli Personel',
          'updatedAt': now.toUtc().toIso8601String(),
          'deadline': now
              .add(const Duration(days: 3))
              .toUtc()
              .toIso8601String(),
          'institution': 'TEST KURUMU',
          'requirementGroups': [
            {
              'cities': ['Ankara'],
              'occupations': ['Mühendis'],
              'education': ['Lisans'],
              'kpssStatus': 'unknown',
            },
          ],
        }),
      ]),
      after: 0,
    );
    await store.addSavedSearch(
      SavedSearch(
        id: null,
        name: searchName,
        filters: const {'sehir': 'ANKARA', 'yas': '30', 'kpss': 'P93'},
        createdAt: now,
      ),
    );
    await store.saveRemoteMetadata(
      '{"schemaVersion":2,"taxonomyVersion":1,"latestSeq":0,"oldestRetainedSeq":0,"sources":[]}',
      '"offline"',
      DateTime(2026, 9, 30, 12),
    );
  });

  Future<void> editSearch(WidgetTester tester, {required bool compact}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    if (compact) {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }
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

    // Offline refresh must keep the durable last-success label across startup.
    expect(find.textContaining('Son eşitleme 30.9.2026 12:00'), findsOneWidget);
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
    final cities = find.byKey(const ValueKey('criteria-cities'));
    await tester.ensureVisible(cities);
    await tester.enterText(cities, 'Listede olmayan');
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Kaydet')),
    );
    await tester.pump();
    expect(find.textContaining('Listeden bir seçenek seçin'), findsOneWidget);
    await tester.enterText(cities, 'Istan');
    await tester.pump();
    await tester.tap(find.text('İstanbul').last);
    await pumpRoute(tester);
    expect(find.widgetWithText(InputChip, 'İstanbul'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'ANKARA'), findsOneWidget);
    await tester.ensureVisible(
      find.byTooltip('Şehirler: İstanbul seçimini kaldır'),
    );
    await pumpRoute(tester);
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(InputChip, 'İstanbul'),
            matching: find.byType(Icon),
          )
          .last,
    );
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'İstanbul'), findsNothing);
    await tester.ensureVisible(cities);
    await tester.enterText(cities, 'Istan');
    await tester.pump();
    await tester.tap(find.text('İstanbul').last);
    await tester.pump();
    final keyword = find.byKey(const ValueKey('criteria-keyword'));
    await tester.ensureVisible(keyword);
    await tester.enterText(keyword, 'Sözleşmeli');
    for (final choice in [
      ('education', 'lisan', 'Lisans'),
      ('education', 'lisan', 'Yüksek lisans'),
      ('categories', 'pers', 'personel'),
      ('occupations', 'muh', 'Mühendis'),
      ('institutions', 'TEST', 'TEST KURUMU'),
    ]) {
      final field = find.byKey(ValueKey('criteria-${choice.$1}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, choice.$2);
      await tester.pump();
      await tester.tap(find.text(choice.$3).last);
      await pumpRoute(tester);
    }
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Kaydet')),
    );
    // SQLite yazısı paralel suite yükünde daha geç dönebilir; route'u bekle.
    for (var i = 0; i < 50 && dialog.evaluate().isNotEmpty; i++) {
      await pumpRoute(tester);
    }
    expect(dialog, findsNothing);
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
    expect(
      find.descendant(
        of: sheet,
        matching: find.textContaining('ANKARA, İstanbul'),
      ),
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
      expect(search.effectiveCriteria.values['cities'], ['ANKARA', 'İstanbul']);
      expect(search.effectiveCriteria.values['keyword'], 'Sözleşmeli');
      expect(search.effectiveCriteria.values['categories'], ['personel']);
      expect(search.effectiveCriteria.values['occupations'], ['Mühendis']);
      expect(search.effectiveCriteria.values['institutions'], ['TEST KURUMU']);
      expect(search.effectiveCriteria.values['education'], [
        'Lisans',
        'Yüksek lisans',
      ]);
      expect(search.filters['egitim'], isNull);
      expect(
        search.filters['sehir'],
        isNull,
        reason: 'Çoklu şehir tek legacy filtreye indirgenmez',
      );
    });
    // Yaş/KPSS koşulları bilinmeyen kayıt kesin eşleşme sayılmaz.
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
    // Elle kelime değişince kayıtlı arama ayrılır; diğer typed kriterler kalır.
    final quickSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Kurum veya meslek ara',
    );
    await tester.ensureVisible(quickSearch);
    await tester.enterText(quickSearch, 'Personel');
    await pumpRoute(tester);
    expect(
      find.text('TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)'),
      findsNothing,
    );
    expect(find.textContaining('ANKARA, İstanbul'), findsWidgets);
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
    await tester.tap(find.byTooltip('Bu aramayı kaydet'));
    await pumpRoute(tester);
    for (final value in [
      'ANKARA',
      'İstanbul',
      'Lisans',
      'Yüksek lisans',
      'Mühendis',
      'TEST KURUMU',
    ]) {
      expect(find.widgetWithText(InputChip, value), findsOneWidget);
    }
    final scoreField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'KPSS puanınız (0–100)',
    );
    expect(tester.widget<TextField>(scoreField).controller!.text, '78.25');
    final ageDateField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Yaş bilgisi tarihi (YYYY-AA-GG)',
    );
    expect(
      tester.widget<TextField>(ageDateField).controller!.text,
      '1970-01-01',
    );
    await tester.tap(find.text('Vazgeç'));
    await pumpRoute(tester);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'profil ve seçimler yönet listesinden düzenlenebilir',
    (tester) => editSearch(tester, compact: false),
  );
  testWidgets(
    'seçimler 320px ve 1.3x metinde taşmadan çalışır',
    (tester) => editSearch(tester, compact: true),
  );
}
