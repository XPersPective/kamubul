import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/kariyer_detail.dart';
import 'package:kamubul/listings/kariyer_detail_page.dart';
import 'package:kamubul/listings/kariyer_feed.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:napp_core/napp_core.dart';
import 'package:kamubul/ui/premium.dart';

/// PB-008 altın görüntüler: telefon, 1.3x metin ölçeği ve tablet düzenleri.
///
/// Flutter SDK'nın Roboto fontları Türkçe glif ve gerçek metin genişliklerini
/// denetler. SDK/font güncellemesinde referansları görsel olarak inceleyerek
/// `flutter test --update-goldens` ile yenileyin; fiziksel cihaz kabulü ayrıdır.
void main() {
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json');
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = config.absolute.uri.resolve(
      '${packages.singleWhere((p) => p['name'] == 'flutter')['rootUri']}/',
    );
    final loader = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File.fromUri(
        flutter.resolve(
          '../../bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
        ),
      );
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
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
  // Test-only cache record: no network, inference or production writes.
  final canonical = ListingRecord(
    url: 'https://kariyerkapisi.gov.tr/IlanDetay?i=test',
    sourceId: 'kariyerkapisi',
    title: 'TEST KURUMU — Sözleşmeli personel alımı',
    category: 'Sözleşmeli Personel',
    publishedAt: DateTime(2026, 9, 20),
    fetchedAt: DateTime(2026, 10, 2),
    deadline: DateTime(2026, 10, 12),
    quota: 5,
    places: const ['Ankara', 'İzmir'],
    summary: const ['Başvurular resmî başvuru sistemi üzerinden yapılır.'],
    criteriaListing: {
      'text':
          'Unvan | Kontenjan | Eğitim | KPSS\n'
          'Mühendis | 3 | Lisans | P3 en az 70 puan\n'
          'Destek personeli | 2 | Koşulları resmî belgede belirtilir.\n'
          'Başvurular 12 Ekim 2026 tarihine kadar Kariyer Kapısı üzerinden yapılır.',
      'extraction': {
        'method': 'hybrid',
        'status': 'complete',
        'missing': [],
        'version': 'facts-v1',
      },
      'requirementGroups': [
        {
          'label': 'Mühendis',
          'quota': 3,
          'occupations': ['Mühendis'],
          'cities': ['city:ankara'],
          'education': ['education:bachelor'],
          'kpssStatus': 'required',
          'kpssType': 'P3',
          'kpssScore': 70,
          'ageStatus': 'known',
          'maxAge': 35,
          'ageReferenceDate': '2026-10-01',
          'quotes': {'education': 'Mühendis | 3 | Lisans | P3 en az 70 puan'},
        },
        {
          'label': 'Destek personeli',
          'quota': 2,
          'occupations': ['Destek personeli'],
          'kpssStatus': 'unknown',
          'ageStatus': 'unknown',
        },
      ],
    },
  );
  for (final (name, size, scale, dark) in [
    ('phone_light', const Size(390, 844), 1.0, false),
    ('phone_dark_1_3x', const Size(320, 844), 1.3, true),
    ('tablet_light_1_3x', const Size(1024, 1366), 1.3, false),
    ('tablet_dark', const Size(1024, 1366), 1.0, true),
  ]) {
    testWidgets('canonical detail golden: $name', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      const brand = Color(0xFF17659C);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: premiumTheme(AppTheme.light(brandColor: brand)),
          darkTheme: premiumTheme(AppTheme.dark(brandColor: brand)),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: OfficialListingPage(listing: canonical),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('İlan özeti'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/canonical_${name}_top.png'),
      );
      await tester.scrollUntilVisible(
        find.text('Eğitim: Lisans'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Eğitim: Lisans'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Yaş şartı: henüz belirlenemedi'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      // Lazy cards settle their extent after the first scroll.
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yaş şartı: henüz belirlenemedi'));
      await tester.pumpAndSettle();
      expect(
        find.text('KPSS şartı: henüz belirlenemedi').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text('Yaş şartı: henüz belirlenemedi').hitTestable(),
        findsOneWidget,
      );
      final cta = find.widgetWithText(FilledButton, 'Resmî belgeyi aç');
      expect(cta.hitTestable(), findsOneWidget);
      expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/canonical_${name}_conditions.png'),
      );
    });
  }
  final listing = PublicListing(
    title: 'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
    category: 'Sözleşmeli Personel',
    url: Uri.parse('https://kariyerkapisi.gov.tr/IlanDetay?i=test'),
    publishedAt: DateTime(2026, 9, 20),
  );
  final detail = KariyerDetail(
    institution: 'TEST KURUMU REKTÖRLÜĞÜ',
    body:
        'Kurumumuza KPSS P3 puan türüyle 65 yaşını doldurmamış lisans mezunu '
        'sözleşmeli personel alınacaktır.',
    start: DateTime(2026, 9, 1),
    deadline: DateTime(2026, 10, 12),
    applyUrl: Uri.parse('https://kariyerkapisi.gov.tr/basvuru'),
    positions: [
      KariyerPosition(
        title: 'Memur alımı',
        profession: 'Büro personeli',
        conditions:
            'KPSS P3 taban puan 60 ve üzeri puan almış olmak.\n'
            'Lisans mezunu olmak.',
        quota: 5,
        places: const ['ANKARA', 'İZMİR'],
      ),
    ],
  );

  Future<void> pumpDetail(
    WidgetTester tester, {
    Size logicalSize = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = logicalSize * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: premiumTheme(
          AppTheme.light(brandColor: const Color(0xFF17659C)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: KariyerDetailPage(listing: listing, loader: (_) async => detail),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('altın görüntü: telefon', (tester) async {
    await pumpDetail(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/detail_phone.png'),
    );
  });

  testWidgets('altın görüntü: telefon 1.3x metin', (tester) async {
    await pumpDetail(tester, textScale: 1.3);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/detail_phone_1_3x.png'),
    );
  });

  testWidgets('altın görüntü: tablet', (tester) async {
    await pumpDetail(tester, logicalSize: const Size(1024, 1366));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/detail_tablet.png'),
    );
  });

  testWidgets('şart alanları alıntılı satırlarla gösterilir', (tester) async {
    await pumpDetail(tester, logicalSize: const Size(1024, 1366));
    for (final row in const [
      'KPSS puan türü: P3',
      'KPSS taban puan: 60',
      'Yaş sınırı: 65 yaş',
      'Eğitim: Lisans',
      'Kadro/kota tipi: Sözleşmeli',
    ]) {
      expect(find.text(row), findsOneWidget, reason: '$row satırı yok');
    }
  });
}
