import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/kariyer_detail.dart';
import 'package:kamubul/listings/kariyer_detail_page.dart';
import 'package:kamubul/listings/kariyer_feed.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/listings/listing_guide.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/notifications/alert_history.dart';
import 'package:kamubul/notifications/notification_center_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PB-008: 1.3x metin ölçeği ve tablet genişliğinde taşma olmadan düzen;
/// büyük başlık çökmesi ve yapışkan CTA davranışı.
void main() {
  testWidgets('SBB ilanı uygulama içinde özetlenir', (tester) async {
    final record = ListingRecord(
      url: 'https://kamuilan.sbb.gov.tr/ilanDetay.aspx?kod=1',
      sourceId: 'kamuilan_sbb',
      title: 'Örnek Kurum 12 İşçi Alacak',
      category: 'İşçi',
      publishedAt: DateTime(2026, 9, 28),
      fetchedAt: DateTime(2026, 9, 28),
      deadline: DateTime(2026, 10, 10),
      quota: 12,
    );
    await tester.pumpWidget(
      MaterialApp(home: OfficialListingPage(listing: record)),
    );
    expect(find.text('Örnek Kurum 12 İşçi Alacak'), findsOneWidget);
    expect(find.text('12 kişi'), findsOneWidget);
    expect(find.text('10.10.2026'), findsOneWidget);
    expect(find.text('Resmî belgeyi aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rehber SBB için bilinen alanları ve belirsiz şartları gösterir',
    (tester) async {
      final record = ListingRecord(
        url: 'https://kamuilan.sbb.gov.tr/ilanDetay.aspx?kod=1',
        sourceId: 'kamuilan_sbb',
        title: 'Örnek Kurum 12 İşçi Alacak',
        category: 'İşçi',
        publishedAt: DateTime(2026, 9, 28),
        fetchedAt: DateTime(2026, 9, 28),
        quota: 12,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [ListingGuideView(listing: record)]),
          ),
        ),
      );
      expect(find.text('Kontenjan: 12 kişi'), findsOneWidget);
      expect(find.text('Yaş sınırı: belirtilmemiş'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
        'sözleşmeli personel alınacaktır. Başvurular 12 Ekim 2026 tarihine '
        'kadar sürecektir. Adayların 2026/1 sözlü sınavına katılmaları '
        'gerekmektedir. İletişim bilgileri kurum internet sayfasındadır.',
    start: DateTime(2026, 9, 1),
    deadline: DateTime(2026, 10, 12),
    applyUrl: Uri.parse('https://kariyerkapisi.gov.tr/basvuru'),
    positions: [
      KariyerPosition(
        title: 'Memur alımı',
        profession: 'Büro personeli',
        conditions:
            'KPSS P3 taban puan 60 ve üzeri puan almış olmak.\n'
            'Lisans mezunu olmak.\n'
            '35 yaşını doldurmamış olmak.',
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
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
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

  testWidgets('ayrıntı telefon genişliğinde taşmasız yerleşir', (tester) async {
    await pumpDetail(tester);
    expect(find.text('Başvuru sayfasını aç'), findsOneWidget);
    expect(find.text('TEST KURUMU REKTÖRLÜĞÜ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.3x metin ölçeğinde taşma oluşmaz', (tester) async {
    await pumpDetail(tester, textScale: 1.3);
    // Uzun başlık ve kanıt alanları 1.3x'te de görünür ve taşmasızdır.
    // (Büyük başlık, genişleyen ve çöken iki katmanda başlığı çizer.)
    expect(find.text('Başvuru sayfasını aç'), findsOneWidget);
    expect(
      find.textContaining('TEST KURUMU - Sözleşmeli'),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet genişliğinde taşma oluşmaz', (tester) async {
    await pumpDetail(tester, logicalSize: const Size(1024, 1366));
    expect(find.text('Başvuru sayfasını aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('büyük başlık kaydırmada çöker, CTA yerinde kalır', (
    tester,
  ) async {
    await pumpDetail(tester, logicalSize: const Size(390, 844));
    // SliverAppBar bir RenderSliver'dır; yükseklik geometriden okunur.
    double barExtent() => tester
        .renderObject<RenderSliver>(find.byType(SliverAppBar))
        .geometry!
        .paintExtent;
    final expandedHeight = barExtent();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -600),
      2000,
    );
    await tester.pumpAndSettle();
    expect(barExtent(), lessThan(expandedHeight));
    // Yapışkan başvuru düğmesi kaydırma sonrası da ekrandadır.
    expect(find.text('Başvuru sayfasını aç'), findsOneWidget);
  });

  testWidgets('bildirim geçmişi 1.3x metinde rozetleriyle yerleşir', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'kamubul.alerts.history': encodeAlerts([
        AlertRecord.create(
          kind: AlertKind.instant,
          searchName: 'Sizin için',
          title: 'Sizin için',
          body: 'TEST KURUMU - Sözleşmeli Personel Alım İlanı (2026/1)',
          listingUrl: 'https://kariyerkapisi.gov.tr/IlanDetay?i=test',
          createdAt: DateTime(2026, 9, 28, 3, 35),
        ),
        AlertRecord.create(
          kind: AlertKind.reminder,
          searchName: 'Son başvuru',
          title: 'Son 2 gün',
          body: 'KAYITLI İLAN - Personel Alımı',
          listingUrl: 'https://kariyerkapisi.gov.tr/IlanDetay?i=kayitli',
          createdAt: DateTime(2026, 9, 28, 9),
          delivery: AlertDelivery.delivered,
          deliveredAt: DateTime(2026, 9, 28, 9),
        ),
      ]),
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const NotificationCenterPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beklemede'), findsOneWidget);
    expect(find.text('Gönderildi'), findsOneWidget);
    expect(find.text('Son 2 gün'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
