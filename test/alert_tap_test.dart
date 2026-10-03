import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/data/remote_sync.dart';
import 'package:kamubul/home_page.dart';
import 'package:kamubul/listings/kariyer_detail_page.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/notifications/alert_service.dart';
import 'package:kamubul/notifications/notification_center_page.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _Routes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final widgetHttpOverride = HttpOverrides.current;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  HttpOverrides.global = _NoNetwork();

  late String dbPath;

  setUpAll(() async {
    dbPath = await isolateListingsDb('alert_tap');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
    NavigatorObserver? observer,
    OtherAppsRepository? otherApps,
    String? otherAppsUrl,
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
        localizationsDelegates: [
          NappLocalizationsDelegate(await NappTranslations.loadCore()),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        navigatorObservers: [?observer],
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
            otherAppsUrl: otherAppsUrl,
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
          otherAppsRepository: otherApps,
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

  for (final active in [true, false]) {
    testWidgets(
      '${active ? 'normal' : 'saved unavailable'} canonical cards open cached detail without source HTTP',
      (tester) async {
        final requests = <Uri>[];
        final now = DateTime.now().toUtc().toIso8601String();
        final client = RemoteCatalogueClient(
          baseUrl: Uri.parse('https://api.example.com'),
          client: MockClient((request) async {
            requests.add(request.url);
            if (request.url.path == '/api/v2/meta') {
              return http.Response(
                jsonEncode({
                  'schemaVersion': 2,
                  'taxonomyVersion': 1,
                  'latestSeq': 1,
                  'oldestRetainedSeq': 1,
                  'sources': [
                    for (final id in [kKariyerSourceId, kSbbSourceId])
                      {
                        'id': id,
                        'name': id,
                        'state': 'ok',
                        'last_success': now,
                      },
                  ],
                }),
                200,
              );
            }
            expect(request.url.path, '/api/v2/listings');
            return http.Response(
              jsonEncode({
                'watermark': 1,
                'next': null,
                'items': [
                  {
                    'id': 'cached-card',
                    'revision': 1,
                    'active': active,
                    'title': 'CANONICAL CARD',
                    'category': 'Personel',
                    'url': 'https://kariyerkapisi.gov.tr/card',
                    'sourceId': kKariyerSourceId,
                    'updatedAt': now,
                    'publishedAt': now,
                    'summary': [
                      {
                        'text': 'Başvurular resmî başvuru sistemi üzerinden yapılır.',
                      },
                    ],
                    'aiProvenance': {'provider': 'cloudflare'},
                    'requirementGroups': [
                      {
                        'occupations': ['Mühendis'],
                        'kpssStatus': 'unknown',
                        'ageStatus': 'unknown',
                      },
                    ],
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        final store = ListingStore();
        await tester.runAsync(() async {
          await syncRemoteV2Catalogue(
            store: store,
            client: client,
            now: DateTime.now(),
          );
          await store.setSaved('https://kariyerkapisi.gov.tr/card', true);
        });
        await pumpHome(tester, client: client);
        if (!active) {
          await tester.tap(find.text('Kaydedilen'));
          await tester.pumpAndSettle();
        }
        await settleUntil(tester, find.text('CANONICAL CARD'));
        await tester.tap(find.text('CANONICAL CARD'));
        await tester.pumpAndSettle();
        expect(find.byType(OfficialListingPage), findsOneWidget);
        expect(find.byType(KariyerDetailPage), findsNothing);
        expect(find.text('Yapay zekâ özeti'), findsOneWidget);
        expect(
          find.textContaining('artık yayında değil'),
          active ? findsNothing : findsOneWidget,
        );
        expect(requests.every((uri) => uri.host == 'api.example.com'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Keşfet and settings share cached catalogue and exclude own app',
    (tester) async {
      var requests = 0;
      final repository = OtherAppsRepository(
        appsUrl: 'https://catalogue.example/apps.json',
        cacheStore: SettingsStore(),
        client: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'schema': 1,
              'apps': [
                for (final package in [
                  'com.crazypenguin.kamubul',
                  'com.crazypenguin.doctorfilter',
                ])
                  {
                    'id': package,
                    'androidPackage': package,
                    'name': {'tr': package},
                    'description': {'tr': 'Uygulama'},
                  },
              ],
            }),
            200,
          );
        }),
      );
      await pumpHome(tester, otherApps: repository);
      tester.view.physicalSize = const Size(320, 844) * 2;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await tester.tap(find.text('Keşfet'));
      await settleUntil(tester, find.text('com.crazypenguin.doctorfilter'));
      await tester.pumpAndSettle();
      expect(find.byType(OtherAppsPage), findsOneWidget);
      expect(find.text('Diğer Uygulamalarımızı Keşfedin'), findsOneWidget);
      expect(find.text('otherApps.title'), findsNothing);
      expect(find.text('com.crazypenguin.kamubul'), findsNothing);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(OtherAppsPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diğer uygulamalarımız'));
      await settleUntil(tester, find.text('com.crazypenguin.doctorfilter'));
      await tester.pumpAndSettle();
      expect(find.byType(OtherAppsPage), findsOneWidget);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first offline discovery uses real bundled catalogue', (
    tester,
  ) async {
    // Flutter's HTTP override returns 400, allowing client construction but
    // denying requests (the source override throws at construction instead).
    HttpOverrides.global = widgetHttpOverride;
    addTearDown(() => HttpOverrides.global = _NoNetwork());
    await pumpHome(
      tester,
      otherAppsUrl: 'https://raw.githubusercontent.com/XPersPective/napp_apps/HEAD/apps.json',
    );
    await tester.tap(find.text('Keşfet'));
    await settleUntil(tester, find.text('DoctorFilter: Mavi Işık Filtre'));
    await tester.pumpAndSettle();
    expect(find.text('DoctorFilter: Mavi Işık Filtre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  http.Response detailResponse(String id, {int revision = 1}) =>
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'id': id,
            'revision': revision,
            'active': true,
            'sourceId': 'kariyerkapisi',
            'title': 'DETAIL $id',
            'category': 'Personel',
            'url': 'https://kariyerkapisi.gov.tr/$id',
            'updatedAt': '2026-10-02T07:00:00Z',
          }),
        ),
        200,
      );

  Future<void> waitForRequest(
    WidgetTester tester,
    bool Function() requested,
  ) async {
    for (var i = 0; i < 50 && !requested(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(requested(), isTrue);
  }

  testWidgets(
    'repeated pending/open tap makes one request and one route; back allows reopen',
    (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final routes = _Routes();
      final client = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://api.example.com'),
        client: MockClient((request) {
          calls++;
          return calls == 1
              ? pending.future
              : Future.value(detailResponse('repeat', revision: 2));
        }),
      );
      await pumpHome(tester, client: client, observer: routes);
      final payload = alertTapPayload(
        'https://kariyerkapisi.gov.tr/repeat',
        listingId: 'repeat',
        revision: 1,
      );
      openAlertUrl(payload);
      await waitForRequest(tester, () => calls == 1);
      openAlertUrl(payload);
      pending.complete(detailResponse('repeat'));
      await settleUntil(tester, find.byType(OfficialListingPage));
      openAlertUrl(payload);
      await tester.pump();
      expect(calls, 1);
      expect(routes.routes, hasLength(2));
      openAlertUrl(
        alertTapPayload(
          'https://kariyerkapisi.gov.tr/alias',
          listingId: 'repeat',
          revision: 2,
        ),
      );
      await settleUntil(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is OfficialListingPage &&
              widget.listing.criteriaListing?['revision'] == 2,
        ),
      );
      expect(calls, 2);
      expect(routes.routes, hasLength(2));
      Navigator.of(tester.element(find.byType(OfficialListingPage))).pop();
      await tester.pumpAndSettle();
      openAlertUrl(payload);
      await settleUntil(tester, find.byType(OfficialListingPage));
      expect(routes.routes, hasLength(2));
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'newer tap wins a late HTTP response and replaces an open notification route',
    (tester) async {
      final old = Completer<http.Response>();
      final paused = Completer<http.Response>();
      final requests = <String>[];
      final routes = _Routes();
      final client = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://api.example.com'),
        client: MockClient((request) {
          final id = request.url.pathSegments.last;
          requests.add(id);
          if (id == 'paused') return paused.future;
          return id == 'old' ? old.future : Future.value(detailResponse(id));
        }),
      );
      await pumpHome(tester, client: client, observer: routes);
      openAlertUrl(
        alertTapPayload('https://kariyerkapisi.gov.tr/old', listingId: 'old'),
      );
      await waitForRequest(tester, () => requests.contains('old'));
      openAlertUrl(
        alertTapPayload('https://kariyerkapisi.gov.tr/new', listingId: 'new'),
      );
      await settleUntil(tester, find.text('DETAIL new'));
      old.complete(detailResponse('old'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('DETAIL old'), findsNothing);
      expect(routes.routes, hasLength(2));
      openAlertUrl(
        alertTapPayload(
          'https://kariyerkapisi.gov.tr/third',
          listingId: 'third',
        ),
      );
      await settleUntil(tester, find.text('DETAIL third'));
      expect(routes.routes, hasLength(2));
      expect(find.text('DETAIL new', skipOffstage: false), findsNothing);
      openAlertUrl(
        alertTapPayload(
          'https://kariyerkapisi.gov.tr/paused',
          listingId: 'paused',
        ),
      );
      await waitForRequest(tester, () => requests.contains('paused'));
      openAlertUrl(
        alertTapPayload(
          'https://kariyerkapisi.gov.tr/third',
          listingId: 'third',
        ),
      );
      paused.complete(detailResponse('paused'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('DETAIL third'), findsOneWidget);
      expect(find.text('DETAIL paused'), findsNothing);
      expect(routes.routes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history tile closes center and opens canonical API detail', (
    tester,
  ) async {
    final routes = _Routes();
    final requests = <Uri>[];
    final client = RemoteCatalogueClient(
      baseUrl: Uri.parse('https://api.example.com'),
      client: MockClient((request) async {
        requests.add(request.url);
        return detailResponse('history');
      }),
    );
    SharedPreferences.setMockInitialValues({
      'kamubul.alerts.history': encodeAlerts([
        AlertRecord.create(
          kind: AlertKind.instant,
          searchName: '',
          title: 'HISTORY TILE',
          body: '',
          listingUrl: 'https://kariyerkapisi.gov.tr/old-alias',
          listingId: 'history',
          listingRevision: 1,
        ),
      ]),
    });
    await pumpHome(tester, client: client, observer: routes);
    unawaited(
      Navigator.of(tester.element(find.byType(KamuHomePage))).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationCenterPage()),
      ),
    );
    await settleUntil(tester, find.text('HISTORY TILE'));
    await tester.tap(find.text('HISTORY TILE'));
    await settleUntil(tester, find.text('DETAIL history'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL history'), findsOneWidget);
    expect(requests.single.pathSegments.last, 'history');
    expect(
      find.byType(NotificationCenterPage, skipOffstage: false),
      findsNothing,
    );
    expect(routes.routes, hasLength(2));
    expect(tester.takeException(), isNull);
  });

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
  for (final requiredRevision in [1, 2]) {
    testWidgets(
      'cold cached detail revision $requiredRevision supports offline API without source fetch',
      (tester) async {
        var calls = 0;
        final client = RemoteCatalogueClient(
          baseUrl: Uri.parse('https://api.example.com'),
          client: MockClient((request) async {
            calls++;
            expect(request.url.host, 'api.example.com');
            return http.Response('', 503);
          }),
        );
        await tester.runAsync(() async {
          final store = ListingStore();
          final generation = await store.bindRemoteOrigin(
            'https://api.example.com',
          );
          final epoch = await store.remoteDetailEpoch(
            expectedGeneration: generation,
          );
          await store.cacheRemoteDetail(
            'kariyer:cached',
            {
              'id': 'kariyer:cached',
              'revision': 1,
              'active': true,
              'sourceId': 'kariyerkapisi',
              'title': 'OFFLINE AYRINTI',
              'category': 'Personel',
              'url': 'https://kariyerkapisi.gov.tr/current-alias',
              'updatedAt': '2026-10-02T07:00:00Z',
            },
            expectedGeneration: generation,
            expectedEpoch: epoch,
          );
        });
        alertTapUrl.value = alertTapPayload(
          'https://kariyerkapisi.gov.tr/old-alias',
          listingId: 'kariyer:cached',
          revision: requiredRevision,
        );
        await pumpHome(tester, client: client);
        await settleUntil(tester, find.byType(OfficialListingPage));
        expect(find.text('OFFLINE AYRINTI'), findsOneWidget);
        expect(calls, requiredRevision == 1 ? 0 : 1);
        expect(
          find.text(
            requiredRevision == 1
                ? 'Önbellekteki ilan bilgileri gösteriliyor.'
                : 'Güncel ayrıntı alınamadı. Önbellekteki eski bilgiler gösteriliyor.',
          ),
          findsOneWidget,
        );
        expect(find.byType(KariyerDetailPage), findsNothing);
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
