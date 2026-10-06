import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/listings/listing_guide.dart';
import 'package:kamubul/ui/premium.dart';
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
  testWidgets('okuma kaydırıcısı etiketini ve yüzde değerini bir kez okur', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final previousScale = ReadingScale.notifier.value;
    try {
      ReadingScale.set(1.0);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(appBar: null, body: ReadingScaleButton()),
        ),
      );
      await tester.tap(find.byTooltip('Yazı boyutu'));
      await tester.pumpAndSettle();
      final slider = find.bySemanticsLabel('İlan yazı boyutu');
      expect(slider, findsOneWidget);
      expect(tester.getSemantics(slider).getSemanticsData().value, '%100');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(slider).getSemanticsData().value,
        '%${(ReadingScale.notifier.value * 100).round()}',
      );
      expect(ReadingScale.notifier.value, greaterThan(1.0));
    } finally {
      ReadingScale.set(previousScale);
      semantics.dispose();
    }
  });

  testWidgets('scoped summary stays readable without quote panels at 1.3x', (
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
      // Okuma ölçeği metni büyüttüğü için özet aşağıda olabilir.
      await tester.scrollUntilVisible(
        find.text('Alıntısı olmayan özet'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Kullanıcı kararı (PB-024): açılır panel yok; özet doğrudan okunur.
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('Alıntısı olmayan özet'), findsOneWidget);
      expect(find.text('Mühendis: $text'), findsOneWidget);
      expect(find.textContaining(quote), findsNothing);
      expect(tester.takeException(), isNull);
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
              'label': 'Mühendis',
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
              'label': 'Destek personeli',
              'occupations': ['Destek personeli'],
              'kpssStatus': 'unknown',
              'ageStatus': 'unknown',
            },
            {
              'label': 'Genel başvuru koşulları',
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
          find.text('Mühendis'),
          180,
          scrollable: scroll,
        );
        expect(find.text('Mühendis'), findsOneWidget);
        expect(find.text('KPSS P3 en az 70'), findsOneWidget);
        expect(
          find.text('En fazla 35 yaş (01.10.2026 itibarıyla)'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Destek personeli'),
          180,
          scrollable: scroll,
        );
        expect(find.text('Destek personeli'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Genel başvuru koşulları'),
          180,
          scrollable: scroll,
        );
        // Çelişkili kayıtta yokluk iddia edilmez; bilinmeyen alan satır olarak basılmaz.
        expect(find.text('KPSS şartı yok'), findsNothing);
        expect(find.text('Yaş sınırı yok'), findsNothing);
        expect(find.textContaining('henüz belirlenemedi'), findsNothing);
        expect(find.text('Kariyer Kapısı’nda aç'), findsOneWidget);
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
    expect(find.text('Resmî ilanı aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rehber SBB için yalnız bilinen alanları gösterir', (
    tester,
  ) async {
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
    // Bilinmeyen şart satırı gösterilmez; Asistan'a sorma önerilir.
    expect(find.text('Yaş sınırı: belirtilmemiş'), findsNothing);
    expect(find.textContaining('Asistan’a sorabilirsiniz'), findsOneWidget);
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
