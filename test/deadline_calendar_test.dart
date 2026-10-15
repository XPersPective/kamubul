import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/ui/premium.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  const channel = MethodChannel('kamubul/calendar');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 12, 30);
  final calls = <MethodCall>[];
  Object? response = true;
  bool fail = false;

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

  setUp(() {
    calls.clear();
    response = true;
    fail = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'calendar_unavailable');
      return response;
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  Future<void> open(
    WidgetTester tester, {
    DateTime? deadline,
    bool unavailable = false,
    bool canonical = true,
    bool estimated = false,
    Size size = const Size(390, 844),
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final record = ListingRecord(
      url: 'https://www.ilan.gov.tr/ilan/123',
      sourceId: 'ilangov',
      title: 'Belediye büro personeli alımı',
      category: 'Personel',
      publishedAt: now,
      fetchedAt: now,
      deadline: deadline,
      criteriaListing: canonical
          ? {
              'text': 'Başvurular resmî sayfadan yapılır.',
              if (estimated)
                'deadlineEstimate': now
                    .add(const Duration(days: 2))
                    .toIso8601String(),
            }
          : null,
    );
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
          listing: record,
          now: now,
          unavailable: unavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final action = find.widgetWithText(TextButton, 'Takvime ekle');
  testWidgets(
    'cached deadline uses Turkish date at year rollover; keyboard opens editor',
    (tester) async {
      await open(tester, deadline: DateTime.utc(2026, 12, 31, 22, 30));
      await tester.ensureVisible(action);
      final semantics = tester.ensureSemantics();
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(action).label, contains('Takvime ekle'));
      Focus.of(tester.element(find.text('Takvime ekle'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls.single.method, 'insert');
      expect(calls.single.arguments, {
        'year': 2027,
        'month': 1,
        'day': 1,
        'title': 'Son başvuru: Belediye büro personeli alımı',
        'description':
            'Son başvuru: 01.01.2027 • 01:30\n'
            'Başvurmadan önce resmî ilanı kontrol edin.\nhttps://www.ilan.gov.tr/ilan/123',
      });
      expect(find.byType(SnackBar), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('no date, expired or unavailable never offers a calendar date', (
    tester,
  ) async {
    for (final scenario in [
      (null, false),
      (now, false),
      (now.add(const Duration(days: 2)), true),
    ]) {
      await open(tester, deadline: scenario.$1, unavailable: scenario.$2);
      expect(action, findsNothing);
    }
    expect(calls, isEmpty);
    await open(tester, estimated: true);
    expect(action, findsNothing);
  });

  testWidgets(
    'legacy date keeps its civil day; missing calendar and platform error allow retry',
    (tester) async {
      await open(
        tester,
        deadline: DateTime(2026, 12, 31, 23, 59),
        canonical: false,
      );
      await tester.ensureVisible(action);
      response = false;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bir takvim uygulaması'), findsOneWidget);
      expect((calls.last.arguments as Map)['day'], 31);
      fail = true;
      await tester.tap(action);
      await tester.pumpAndSettle();
      fail = false;
      response = true;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(calls.length, 3);
      expect(find.text('İlan ayrıntısı'), findsOneWidget);
    },
  );

  for (final viewport in [
    ('phone', const Size(390, 844), false),
    ('tablet', const Size(1024, 768), true),
  ]) {
    testWidgets('calendar action ${viewport.$1} 1.3x render', (tester) async {
      await open(
        tester,
        deadline: now.add(const Duration(days: 2)),
        size: viewport.$2,
        dark: viewport.$3,
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/deadline_calendar_${viewport.$1}.png'),
      );
    });
  }
}
