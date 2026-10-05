import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/kariyer_detail.dart';
import 'package:kamubul/listings/kariyer_detail_page.dart';
import 'package:kamubul/listings/kariyer_feed.dart';

final _listing = PublicListing(
  title: 'TEST KURUMU - Memur Alımı',
  category: 'Personel',
  url: Uri.parse('https://kariyerkapisi.gov.tr/IlanDetay?i=1'),
  publishedAt: DateTime(2026, 9, 28),
);

final _detail = KariyerDetail(
  institution: 'TEST KURUMU',
  body: 'Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.',
  start: null,
  deadline: DateTime(2026, 10, 12, 23, 59),
  applyUrl: Uri.parse('https://turkiye.gov.tr/x'),
  positions: const [
    KariyerPosition(
      title: 'Memur',
      profession: 'Genel',
      conditions: 'Lisans mezunu olmak.',
      quota: 2,
      places: ['ANKARA'],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  List<String> summary = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: KariyerDetailPage(
        listing: _listing,
        summary: summary,
        loader: (_) async => _detail,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'eksik ayrıntıda karttaki kontenjan, yer ve son başvuru korunur',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: KariyerDetailPage(
            listing: PublicListing(
              title: _listing.title,
              category: _listing.category,
              url: _listing.url,
              publishedAt: _listing.publishedAt,
              deadline: DateTime(2026, 10, 20),
            ),
            cachedQuota: 12,
            cachedPlaces: const ['İzmir'],
            loader: (_) async => const KariyerDetail(
              institution: 'TEST KURUMU',
              body: 'Resmî metin',
              start: null,
              deadline: null,
              applyUrl: null,
              positions: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 kişi'), findsOneWidget);
      expect(find.text('İzmir'), findsOneWidget);
      expect(find.text('20.10.2026'), findsOneWidget);
    },
  );
  testWidgets(
    'özet varsa "Yapay zekâ özeti" etiketiyle ve dayanak uyarısıyla gösterilir',
    (tester) async {
      await _pump(
        tester,
        summary: const ['Yaş sınırı 35', 'Lisans mezunu olmak gerekir'],
      );
      await tester.scrollUntilVisible(
        find.text('Yapay zekâ özeti'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Yapay zekâ özeti'), findsOneWidget);
      expect(find.text('Yaş sınırı 35'), findsOneWidget);
      expect(
        find.textContaining('her madde ilan metnindeki bir cümleye dayanır'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('özet yoksa bölüm hiç çizilmez', (tester) async {
    await _pump(tester);
    expect(find.text('Yapay zekâ özeti'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
