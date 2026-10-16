import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/home_page.dart';
import 'package:kamubul/ui/premium.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolate_db.dart';

/// SA-018: kaydedilen ilana yalnız cihazda tutulan başvuru durumu ve not.
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

  setUpAll(() async {
    // Same SDK fonts as ui_list_scale_test so goldens show real text widths.
    final config = File('.dart_tool/package_config.json');
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = config.absolute.uri.resolve(
      '${packages.singleWhere((p) => p['name'] == 'flutter')['rootUri']}/',
    );
    Future<ByteData> font(String name) => File.fromUri(
      flutter.resolve('../../bin/cache/artifacts/material_fonts/$name'),
    ).readAsBytes().then(ByteData.sublistView);
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      roboto.addFont(font('roboto-$weight.ttf'));
    }
    await roboto.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(font('materialicons-regular.otf'))).load();
  });

  const url = 'https://kariyerkapisi.gov.tr/IlanDetay?i=7';
  ListingRecord record(String url) => ListingRecord(
    url: url,
    sourceId: 'kariyerkapisi',
    title: 'NOT KURUMU - Memur Alımı',
    category: 'Personel',
    publishedAt: DateTime.now().subtract(const Duration(days: 1)),
    fetchedAt: DateTime.now(),
  );

  Future<ListingStore> memoryStore() async => ListingStore(
    database: await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 12,
        singleInstance: false,
        onCreate: ListingStore.createSchema,
      ),
    ),
  );

  CatalogueDeltaPage delta(int seq, String itemUrl) =>
      CatalogueDeltaPage.decode({
        'watermark': seq,
        'appliedThrough': seq,
        'hasMore': false,
        'changes': [
          {
            'seq': seq,
            'id': 'stable',
            'revision': seq,
            'operation': 'upsert',
            'item': {
              'id': 'stable',
              'revision': seq,
              'sourceId': 'kariyerkapisi',
              'url': itemUrl,
              'title': 'Memur',
              'category': 'Personel',
              'updatedAt': '2026-09-30T12:00:00Z',
            },
          },
        ],
      }, after: seq - 1);

  test('v11 to v12 keeps favorites and adds an empty note table', () async {
    final path = await isolateListingsDb('notes_migration');
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, version) async {
          await ListingStore.createSchema(db, version);
          await db.execute('DROP TABLE listing_notes');
        },
      ),
    );
    await ListingStore(database: old).mergeFeed([record(url)]);
    await ListingStore(database: old).setSaved(url, true);
    await old.close();

    final store = ListingStore();
    final db = await store.database;
    expect(await db.getVersion(), 12);
    expect((await store.allListings()).single.saved, isTrue);
    expect(await store.listingNotes(), isEmpty);
    await store.setListingNote(url, 'applied', 'Belgeler hazır');
    expect((await ListingStore().listingNotes())[url], (
      status: 'applied',
      note: 'Belgeler hazır',
    ));
    await db.close();
  });

  test('set, update, clear and reject invalid notes', () async {
    final store = await memoryStore();
    await store.setListingNote(url, 'review', '  ilk  ');
    expect((await store.listingNotes())[url], (status: 'review', note: 'ilk'));
    await store.setListingNote(url, null, 'yalnız not');
    expect((await store.listingNotes())[url], (
      status: null,
      note: 'yalnız not',
    ));
    await expectLater(
      store.setListingNote(url, 'hired', null),
      throwsFormatException,
    );
    await expectLater(
      store.setListingNote(url, null, 'x' * 501),
      throwsFormatException,
    );
    expect((await store.listingNotes())[url]!.note, 'yalnız not');
    await store.setListingNote(url, null, '   ');
    expect(await store.listingNotes(), isEmpty);
    await store.close();
  });

  test('unsave deletes the note; save keeps it', () async {
    final store = await memoryStore();
    await store.mergeFeed([record(url)]);
    await store.setSaved(url, true);
    await store.setListingNote(url, 'waiting', null);
    await store.setSaved(url, true);
    expect(await store.listingNotes(), hasLength(1));
    await store.setSaved(url, false);
    expect(await store.listingNotes(), isEmpty);
    await store.close();
  });

  test('remote replace keeps the note and URL change moves it', () async {
    final store = await memoryStore();
    await store.bindRemoteOrigin('https://api.example.com');
    await store.applyDeltaPage(delta(1, url), after: 0);
    await store.setSaved(url, true);
    await store.setListingNote(url, 'applied', 'not');
    await store.applyDeltaPage(delta(2, url), after: 1);
    expect((await store.listingNotes())[url]!.status, 'applied');
    const moved = '$url&v=2';
    await store.applyDeltaPage(delta(3, moved), after: 2);
    final notes = await store.listingNotes();
    expect(notes.keys, [moved]);
    expect((await store.allListings()).single.saved, isTrue);
    await store.close();
  });

  for (final v in [
    (name: 'phone_light', size: const Size(390, 844), dark: false),
    (name: 'phone_dark', size: const Size(390, 844), dark: true),
    (name: 'tablet_light', size: const Size(800, 1280), dark: false),
    (name: 'tablet_dark', size: const Size(800, 1280), dark: true),
  ]) {
    testWidgets(
      'saved card edits, shows and deletes a local note ${v.name} 1.3x',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final path = await tester.runAsync(() async {
          final path = await isolateListingsDb('notes_widget');
          await databaseFactory.deleteDatabase(path);
          final store = ListingStore();
          await store.mergeFeed([record(url)], pruneBefore: DateTime(2000));
          await store.setSaved(url, true);
          return path;
        });
        expect(path, isNotNull);
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = v.size * 2;
        addTearDown(tester.view.reset);
        final settings = SettingsStore();
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
            themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            localizationsDelegates: [
              NappLocalizationsDelegate(await NappTranslations.loadCore()),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: const Locale('tr'),
            supportedLocales: const [Locale('tr')],
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
              theme: ThemeModeController(store: settings)..load(),
              pro: ProController(store: settings, repository: purchase),
              purchase: purchase,
              policy: policy,
              banner: BannerAdController(policy: policy),
              rewarded: RewardedAdManager(policy: policy),
              saveAdState: () {},
            ),
          ),
        );

        Future<void> settle(Finder finder, {bool gone = false}) async {
          for (var i = 0; i < 100; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 50));
            if (finder.evaluate().isEmpty == gone) return;
          }
          fail('timed out waiting for $finder');
        }

        await settle(find.text('Kaydedilen'));
        await tester.tap(find.text('Kaydedilen'));
        await settle(find.text('Not ekle'));
        await tester.ensureVisible(find.text('Not ekle'));
        await tester.tap(find.text('Not ekle'));
        await tester.pumpAndSettle();
        expect(find.textContaining('kuruma başvuru'), findsOneWidget);
        expect(find.textContaining('göndermez'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Başvurdum'));
        await tester.enterText(find.byType(TextField), 'Belgeler hazır');
        await tester.pump();
        await tester.pumpAndSettle();
        final chip = tester.getSize(
          find.widgetWithText(ChoiceChip, 'Başvurdum'),
        );
        expect(chip.height, greaterThanOrEqualTo(48));
        expect(find.bySemanticsLabel(RegExp('Kişisel not')), findsWidgets);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/note_sheet_${v.name}.png'),
        );
        await tester.tap(find.text('Kaydet'));
        await settle(find.text('Notu düzenle'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Başvurdum'), findsOneWidget);
        expect(find.text('Belgeler hazır'), findsOneWidget);
        await tester.ensureVisible(find.text('Notu düzenle'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/note_card_${v.name}.png'),
        );

        await tester.tap(find.byTooltip('Kaydı kaldır'));
        await tester.pumpAndSettle();
        expect(find.textContaining('not da silinir'), findsOneWidget);
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();
        expect(find.text('Notu düzenle'), findsOneWidget);

        await tester.ensureVisible(find.text('Notu düzenle'));
        await tester.tap(find.text('Notu düzenle'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sil'));
        await settle(find.text('Not ekle'));
        await tester.pumpAndSettle();
        expect(find.text('Belgeler hazır'), findsNothing);
        expect(
          await tester.runAsync(() => ListingStore().listingNotes()),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
