import 'dart:io';
import 'dart:async';
import 'dart:convert';

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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_core/kamubul_core.dart';

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
    await store.mergeFeed([
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
    ], pruneBefore: DateTime(2000));
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    RemoteCatalogueClient? client,
  }) async {
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
          catalogueClient: client,
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

  testWidgets(
    'cache-empty stable tap reads only API and preserves sync cursor',
    (tester) async {
      final requests = <Uri>[];
      const id = 'kariyer:part/with?#ü';
      final client = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://api.example.com'),
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': id,
                'revision': 2,
                'active': false,
                'sourceId': 'kariyerkapisi',
                'title': 'SUNUCU İLANI',
                'category': 'Personel',
                'url': 'https://kariyerkapisi.gov.tr/new-url',
                'updatedAt': '2026-10-02T07:00:00.000Z',
                'summary': [
                  {'text': 'Kaynak özeti', 'scopeLabel': 'Genel'},
                ],
              }),
            ),
            200,
          );
        }),
      );
      await pumpHome(tester, client: client);
      final store = ListingStore();
      final before = (await tester.runAsync(store.allListings))!;
      openAlertUrl(
        alertTapPayload('https://kariyerkapisi.gov.tr/old-url', listingId: id),
      );
      await settleUntil(tester, find.byType(OfficialListingPage));
      expect(find.byType(OfficialListingPage), findsOneWidget);
      expect(find.byType(KariyerDetailPage), findsNothing);
      expect(find.text('SUNUCU İLANI'), findsOneWidget);
      expect(find.text('Genel: Kaynak özeti'), findsOneWidget);
      expect(find.textContaining('artık yayında değil'), findsOneWidget);
      expect(requests.single.host, 'api.example.com');
      expect(requests.single.pathSegments.last, id);
      await tester.runAsync(() async {
        expect(await store.remoteCursor(), 0);
        expect(
          (await store.allListings()).map((r) => r.url),
          before.map((r) => r.url),
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
  for (final status in [404, 503]) {
    testWidgets(
      'cold stable tap distinguishes HTTP $status without official fetch',
      (tester) async {
        var calls = 0;
        final client = RemoteCatalogueClient(
          baseUrl: Uri.parse('https://api.example.com'),
          client: MockClient((request) async {
            calls++;
            expect(request.url.host, 'api.example.com');
            return http.Response('', status);
          }),
        );
        alertTapUrl.value = alertTapPayload(
          'https://kariyerkapisi.gov.tr/missing',
          listingId: 'kariyer:missing',
        );
        await pumpHome(tester, client: client);
        final error = status == 404
            ? 'Bu ilan artık sunucuda bulunmuyor.'
            : 'İlan ayrıntısı alınamadı. Yeniden deneyin.';
        await settleUntil(tester, find.text(error));
        expect(calls, 1);
        expect(find.text(error), findsOneWidget);
        expect(find.byType(OfficialListingPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('old origin detail response cannot open after server switches', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var requested = false;
    final client = RemoteCatalogueClient(
      baseUrl: Uri.parse('https://api.example.com'),
      client: MockClient((request) {
        requested = true;
        return pending.future;
      }),
    );
    await pumpHome(tester, client: client);
    openAlertUrl(
      alertTapPayload(
        'https://kariyerkapisi.gov.tr/old-url',
        listingId: 'kariyer:old',
      ),
    );
    // SQLite completes on its real executor, outside the widget fake clock.
    for (var i = 0; i < 50 && !requested; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(requested, isTrue);
    await tester.runAsync(() async {
      await ListingStore().bindRemoteOrigin('https://another.example.com');
    });
    pending.complete(
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'id': 'kariyer:old',
            'revision': 1,
            'active': true,
            'sourceId': 'kariyerkapisi',
            'title': 'STALE RESPONSE',
            'category': 'Personel',
            'url': 'https://kariyerkapisi.gov.tr/old-url',
            'updatedAt': '2026-10-02T07:00:00Z',
          }),
        ),
        200,
      ),
    );
    await settleUntil(
      tester,
      find.text('İlan ayrıntısı alınamadı. Yeniden deneyin.'),
    );
    expect(find.byType(OfficialListingPage), findsNothing);
    expect(find.text('STALE RESPONSE'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
