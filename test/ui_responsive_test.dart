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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/notifications/firebase_push.dart';
import 'package:kamubul/notifications/push_registration.dart';
import 'package:kamubul/notifications/push_setup.dart';
import 'package:kamubul_core/kamubul_core.dart' show PendingNotification;

class _PushStore implements PushStateStore {
  final values = <String, String>{
    'kamubul.push.enabled': '1',
    'kamubul.push.id': 'a' * 32,
    'kamubul.push.secret': 'b' * 64,
  };
  @override
  String? read(String key) => values[key];
  @override
  Future<void> write(Map<String, String?> updates) async {
    for (final entry in updates.entries) {
      if (entry.value == null) {
        values.remove(entry.key);
      } else {
        values[entry.key] = entry.value!;
      }
    }
  }
}

/// PB-008: 1.3x metin ölçeği ve tablet genişliğinde taşma olmadan düzen;
/// büyük başlık çökmesi ve yapışkan CTA davranışı.
void main() {
  testWidgets('scoped summary opens its own bounded quote offline at 1.3x', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.reset);
    const text = 'Başvurular resmî başvuru sistemi üzerinden yapılır.';
    const quote = '$text Posta yoluyla başvuru kabul edilmez.';
    final listing = ListingRecord(
      url: 'https://kariyerkapisi.gov.tr/IlanDetay?i=test',
      sourceId: 'kariyerkapisi',
      title: 'Kurum personel alımı',
      category: 'Personel',
      publishedAt: null,
      fetchedAt: DateTime(2026, 10, 2),
      summary: const ['Mühendis: $text', 'Alıntısı olmayan özet'],
      criteriaListing: {
        'aiProvenance': {'provider': 'cloudflare'},
        'summary': [
          {'text': text, 'quote': quote, 'scopeLabel': 'Mühendis'},
          {'text': 'Alıntısı olmayan özet', 'quote': 'x' * 601},
          {'text': 'Alıntısı olmayan özet', 'quote': quote},
        ],
      },
    );
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: OfficialListingPage(listing: listing),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.text('Alıntısı olmayan özet'), findsOneWidget);
      expect(find.text('“$quote”'), findsNothing);
      await tester.tap(find.text('Kaynak alıntısını göster'));
      await tester.pumpAndSettle();
      expect(find.text('Mühendis: $text'), findsOneWidget);
      expect(find.text('“$quote”'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Kaynak alıntısını göster'));
      await tester.pumpAndSettle();
      expect(find.text('“$quote”'), findsNothing);
    }
  });

  testWidgets(
    'live and legacy SBB detail labels identify the official source',
    (tester) async {
      for (final source in ['sbb', 'kamuilan_sbb']) {
        await tester.pumpWidget(
          MaterialApp(
            home: OfficialListingPage(
              listing: ListingRecord(
                url: 'https://kamuilan.sbb.gov.tr/ilanDetay.aspx?kod=1',
                sourceId: source,
                title: 'Memur alımı',
                category: 'Personel',
                publishedAt: null,
                fetchedAt: DateTime(2026, 10, 2),
              ),
            ),
          ),
        );
        expect(find.text('Strateji ve Bütçe Başkanlığı'), findsOneWidget);
      }
    },
  );
  testWidgets('canonical guide reads cache and opens position detail offline', (
    tester,
  ) async {
    final listing = ListingRecord(
      url: 'https://kariyerkapisi.gov.tr/IlanDetay?i=one',
      sourceId: 'kariyerkapisi',
      title: 'CACHED GUIDE',
      category: 'Personel',
      publishedAt: null,
      fetchedAt: DateTime(2026, 10, 2),
      summary: ['Başvurular resmî başvuru sistemi üzerinden yapılır.'],
      criteriaListing: {
        'requirementGroups': [
          {
            'occupations': ['Mühendis'],
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [ListingGuideView(listing: listing)]),
        ),
      ),
    );
    expect(find.text('İlan rehberi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Sunucudan alınan'), findsOneWidget);
    await tester.tap(find.text('Kadro koşullarını incele'));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialListingPage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mühendis'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mühendis'), findsOneWidget);
    expect(find.textContaining('İlan ayrıntısı şu an okunamadı'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'canonical detail keeps separate positions and unknown conditions at 1.3x',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.reset);
      final listing = ListingRecord(
        url: 'https://kariyerkapisi.gov.tr/IlanDetay?i=one',
        sourceId: 'kariyerkapisi',
        title: 'Kurum personel alımı',
        category: 'Personel',
        publishedAt: null,
        fetchedAt: DateTime(2026, 10, 2),
        summary: ['Başvurular resmî başvuru sistemi üzerinden yapılır.'],
        criteriaListing: {
          'aiProvenance': {'provider': 'cloudflare'},
          'requirementGroups': [
            {
              'occupations': ['Mühendis'],
              'cities': ['city:ankara'],
              'education': ['bachelor'],
              'kpssStatus': 'required',
              'kpssType': 'P3',
              'kpssScore': 70,
              'ageStatus': 'known',
              'maxAge': 35,
              'ageReferenceDate': '2026-10-01',
            },
            {
              'occupations': ['Destek personeli'],
              'kpssStatus': 'unknown',
              'ageStatus': 'unknown',
            },
            {
              'kpssStatus': 'not_required',
              'kpssScore': 'broken',
              'ageStatus': 'no_restriction',
              'maxAge': 'broken',
            },
          ],
        },
      );
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: OfficialListingPage(listing: listing),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byType(Scrollable).first;
        // Scroll each card into view: lazy list rendering preserves group boundaries.
        await tester.scrollUntilVisible(
          find.text('Kadro 1'),
          180,
          scrollable: scroll,
        );
        expect(find.text('Mühendis'), findsOneWidget);
        expect(find.text('KPSS gerekli · P3 · en az 70 puan'), findsOneWidget);
        expect(
          find.text('En fazla 35 yaş · Yaş hesabı tarihi: 01.10.2026'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Kadro 2'),
          180,
          scrollable: scroll,
        );
        expect(find.text('Destek personeli'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Kadro 3'),
          180,
          scrollable: scroll,
        );
        expect(find.text('KPSS şartı yok'), findsNothing);
        expect(find.text('Yaş sınırı yok'), findsNothing);
        expect(find.text('Yaş şartı: henüz belirlenemedi'), findsWidgets);
        expect(find.text('Resmî belgeyi aç'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'sunucu geçmişi erişilemezken alınan kayıt ve uyarı 1.3x dar ekranda korunur',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registrar = PushRegistrar(
        baseUrl: Uri.parse('https://kamubul.example'),
        platform: FirebasePush(),
        store: _PushStore(),
        client: MockClient((_) async => http.Response('unavailable', 500)),
      );
      await registrar.recordForeground(
        PendingNotification(
          searchName: '',
          title: 'Memur ilanı',
          body: 'Yeni ilan',
          listingUrl: 'https://example.gov.tr',
          eventId: 'c' * 64,
        ),
      );
      pushRegistrar = registrar;
      addTearDown(() {
        pushRegistrar = null;
        registrar.close();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
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
      await tester.runAsync(() => registrar.syncHistory());
      await tester.pumpAndSettle();
      expect(find.text('Memur ilanı'), findsOneWidget);
      expect(find.text('Alındı'), findsOneWidget);
      expect(
        find.text('Sunucu geçmişi yenilenemedi. Yerel kayıtlar gösteriliyor.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => registrar.recordForeground(
          PendingNotification(
            searchName: '',
            title: 'Yeni alınan ilan',
            body: 'İlan',
            listingUrl: 'https://example.gov.tr/new',
            eventId: 'd' * 64,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Yeni alınan ilan'), findsOneWidget);
      expect(find.text('Alındı'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
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

  testWidgets('kompakt başlık sabit kalır, iki CTA kaydırmada yerinde', (
    tester,
  ) async {
    await pumpDetail(tester, logicalSize: const Size(390, 844));
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -600),
      2000,
    );
    await tester.pumpAndSettle();
    // Kompakt başlık sabittir; telefonda dev başlık yer kaplamaz.
    expect(find.text('İlan ayrıntısı'), findsOneWidget);
    // Hem resmî ilan hem başvuru sayfası her zaman erişilebilir.
    expect(find.text('İlanı aç'), findsOneWidget);
    expect(find.text('Başvuru sayfasını aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
