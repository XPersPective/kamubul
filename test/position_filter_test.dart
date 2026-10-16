import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/ui/premium.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 15);
  setUpAll(() async {
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
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
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

  final groups = <Map<String, Object?>>[
    {
      'label': 'Birlikte eşleşen kadro',
      'cities': ['Ankara'],
      'education': ['lisans'],
      'kpssStatus': 'required',
      'kpssTypes': ['P3', 'P93'],
      'kpssScore': 70,
    },
    {
      'label': 'Eğitimi uymayan kadro',
      'cities': ['Ankara'],
      'education': ['lise'],
      'kpssStatus': 'required',
      'kpssType': 'P3',
      'kpssScore': 70,
    },
    {
      'label': 'Şehri eksik kadro',
      'education': ['lisans'],
      'kpssStatus': 'required',
      'kpssType': 'P3',
      'kpssScore': 70,
    },
    {
      'label': 'Puanı yüksek kadro',
      'cities': ['Ankara'],
      'education': ['lisans'],
      'kpssStatus': 'required',
      'kpssType': 'P3',
      'kpssScore': 90,
    },
  ];
  final criteria = SearchCriteria.parse({
    'cities': ['Ankara'],
    'education': ['lisans'],
    'kpssType': 'P3',
    'kpssScore': 75,
  });
  Future<void> open(
    WidgetTester tester, {
    bool withCriteria = true,
    List<Map<String, Object?>>? positions,
    Size size = const Size(390, 844),
    bool dark = false,
    VoidCallback? onEdit,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: premiumTheme(
          dark
              ? AppTheme.dark(brandColor: const Color(0xFF17659C))
              : AppTheme.light(brandColor: const Color(0xFF17659C)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: OfficialListingPage(
          now: now,
          criteria: withCriteria ? criteria : null,
          onEditCriteria: onEdit,
          listing: ListingRecord(
            url: 'https://www.ilan.gov.tr/ilan/123',
            sourceId: 'ilangov',
            title: 'Belediye personeli alımı',
            category: 'Personel',
            publishedAt: now,
            fetchedAt: now,
            criteriaListing: {
              'title': 'Belediye personeli alımı',
              'places': ['Ankara'],
              'requirementGroups': positions ?? groups,
              'text': 'Resmî koşulları ve başvuru belgelerini kaynaktan kontrol edin.',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
  Future<void> choose(WidgetTester tester, String label) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(chip(label), 300);
    await tester.pumpAndSettle();
    await tester.tap(chip(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'same-position AND, alternate score OR, unknown and city isolation offline',
    (tester) async {
      await open(tester);
      await choose(tester, 'Eşleşenler');
      expect(find.text('1 / 4 kadro'), findsOneWidget);
      await tester.ensureVisible(find.text('Birlikte eşleşen kadro'));
      expect(find.text('Birlikte eşleşen kadro'), findsOneWidget);
      expect(find.text('Eğitimi uymayan kadro'), findsNothing);
      expect(find.text('Puanı yüksek kadro'), findsNothing);
      expect(find.text('Şehri eksik kadro'), findsNothing);
      await choose(tester, 'Bilinmeyenler');
      expect(find.text('1 / 4 kadro'), findsOneWidget);
      await tester.ensureVisible(find.text('Şehri eksik kadro'));
      expect(find.text('Şehri eksik kadro'), findsOneWidget);
      expect(find.text('Birlikte eşleşen kadro'), findsNothing);
      await choose(tester, 'Tümü');
      expect(find.text('4 / 4 kadro'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('no criteria explains recovery; no false matches', (
    tester,
  ) async {
    var edit = false;
    await open(tester, withCriteria: false, onEdit: () => edit = true);
    expect(chip('Eşleşenler'), findsNothing);
    final action = find.widgetWithText(TextButton, 'Kriterleri düzenle');
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(edit, isTrue);
    expect(find.textContaining('kriterlerinizi belirleyin'), findsOneWidget);
  });
  testWidgets('empty filtered state and pagination reset', (tester) async {
    await open(
      tester,
      positions: List.generate(
        13,
        (i) => {...groups.first, 'label': 'Kadro özel $i'},
      ),
    );
    final expand = find.text('Tüm pozisyonları göster (13)');
    await tester.scrollUntilVisible(expand, 500);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Kadro özel 12'), 500);
    expect(find.text('Kadro özel 12'), findsOneWidget);
    await choose(tester, 'Bilinmeyenler');
    expect(find.text('0 / 13 kadro'), findsOneWidget);
    expect(find.textContaining('Bu grupta kadro yok'), findsOneWidget);
    await choose(tester, 'Tümü');
    expect(find.text('Kadro özel 12'), findsNothing);
    await tester.scrollUntilVisible(expand, 500);
    await tester.pumpAndSettle();
    expect(expand, findsOneWidget);
  });
  for (final viewport in [
    ('phone_light', const Size(390, 844), false),
    ('phone_dark', const Size(390, 844), true),
    ('tablet_light', const Size(1024, 768), false),
    ('tablet_dark', const Size(1024, 768), true),
  ]) {
    testWidgets('position filters ${viewport.$1} 1.3x keyboard and semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester, size: viewport.$2, dark: viewport.$3);
      await tester.ensureVisible(chip('Eşleşenler'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(chip('Eşleşenler')).height,
        greaterThanOrEqualTo(48),
      );
      final node = tester.getSemantics(chip('Eşleşenler'));
      expect(node.label, contains('Eşleşenler'));
      semantics.dispose();
      Focus.of(tester.element(find.text('Eşleşenler'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(chip('Eşleşenler')).selected, isTrue);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/position_filter_${viewport.$1}.png'),
      );
    });
  }
}
