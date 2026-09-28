import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/kariyer_detail.dart';
import 'package:kamubul/listings/kariyer_detail_page.dart';
import 'package:kamubul/listings/kariyer_feed.dart';

/// PB-008 altın görüntüler: telefon, 1.3x metin ölçeği ve tablet düzenleri.
///
/// Varsayılan test fontu (kutu glifler) kullanılır: metin çizimi platformdan
/// bağımsız kalır, görüntüler düzen/taşma regresyonlarını yakalar. Çizim
/// farkında `flutter test --update-goldens` ile yenileyin.
void main() {
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: KariyerDetailPage(
          listing: listing,
          loader: (_) async => detail,
        ),
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
}
