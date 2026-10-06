import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const text = 'Genel başvuru metni ve tablo: Unvan | Eğitim | Yaş';
  const tail = 'Son kadro: mühendis, lisans mezunu olmak ve 35 yaş.';
  final item = <String, Object?>{
    'id': 'ilangov:1',
    'revision': 1,
    'active': true,
    'url': 'https://www.ilan.gov.tr/ilan/1',
    'sourceId': 'ilangov',
    'title': 'Belediye memur alımı',
    'category': 'Personel',
    'updatedAt': '2026-10-05T00:00:00Z',
    'text': text,
    'detailState': 'complete',
    'positions': [
      {
        'title': 'Mühendis',
        'profession': 'Mühendis',
        'text': tail,
        'places': ['Ankara'],
        'quota': 2,
      },
    ],
    'requirementGroups': [],
  };

  test(
    'kartın kısmi çıkarım etiketi hazır AI özetine göre tamamlandı sayılmaz',
    () {
      for (final (status, caption) in [
        ('partial', 'Koşullar kısmen ayrıştırıldı'),
        ('complete', 'Koşullar ayıklandı'),
      ]) {
        final record = ListingStore.projectRemoteListing({
          ...item,
          'aiStatus': 'summary_validated',
          'extraction': {'status': status, 'method': 'hybrid', 'missing': []},
        })!;
        expect(record.conditionsCaption, caption);
      }
      final old = ListingStore.projectRemoteListing({
        ...item,
        'aiStatus': 'summary_validated',
      })!;
      expect(old.conditionsCaption, 'İlan özeti hazır');
    },
  );

  test('eski conditions alanı da yeni wire text alanı önceliğiyle korunur', () {
    final data = {
      ...item,
      'positions': [
        {'title': 'Eski kadro', 'conditions': 'Eski şart metni'},
        {
          'title': 'Yeni kadro',
          'text': 'Yeni şart metni',
          'conditions': 'Eski gölgelenen metin',
        },
      ],
    };
    final record = ListingStore.projectRemoteListing(data)!;
    expect(record.noticeText, contains('Eski şart metni'));
    expect(record.noticeText, contains('Yeni şart metni'));
    expect(record.noticeText, isNot(contains('Eski gölgelenen metin')));
  });

  test('tam kaynak metni uygulama yeniden açılınca ve favori tombstone sonrası korunur', () async {
    final folder = await Directory.systemTemp.createTemp('kamubul-text-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/catalogue.db';
    Future<ListingStore> open() async => ListingStore(
      database: await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 11,
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    var store = await open();
    await store.applyDeltaPage(
      CatalogueDeltaPage(1, 1, false, [
        CatalogueChange(1, 'ilangov:1', 1, false, item),
      ]),
      after: 0,
    );
    await store.setSaved(item['url'] as String, true);
    await store.close();
    store = await open();
    var cached = (await store.allListings()).single;
    expect(cached.noticeText, contains(text));
    expect(cached.noticeText, contains(tail));
    expect(cached.criteriaListing?['detailState'], 'complete');
    expect(cached.criteriaListing?['id'], 'ilangov:1');
    expect(cached.criteriaListing?['revision'], 1);
    // AI grupları boş olsa da metnin mevcudiyeti değişmez.
    expect(cached.criteriaListing?['requirementGroups'], isEmpty);
    await store.applyDeltaPage(
      CatalogueDeltaPage(2, 2, false, [
        CatalogueChange(2, 'ilangov:1', 2, true, {
          'id': 'ilangov:1',
          'revision': 2,
        }),
      ]),
      after: 1,
    );
    await store.close();
    store = await open();
    addTearDown(store.close);
    cached = (await store.allListings()).single;
    expect(cached.saved, true);
    expect(cached.criteriaListing?['active'], false);
    expect(cached.noticeText, contains(tail));
    expect(await store.remoteCursor(), 2);
  });

  testWidgets('sunucunun ayıklanmamış tam metni ayrıntıda çevrimdışı okunur', (
    tester,
  ) async {
    final record = ListingStore.projectRemoteListing(item)!;
    await tester.pumpWidget(
      MaterialApp(home: OfficialListingPage(listing: record)),
    );
    // Tablo satırı hücrelere ayrılarak gösterilir; özgün metnin her parçası okunur.
    await tester.scrollUntilVisible(
      find.textContaining(tail),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Genel başvuru metni ve tablo'), findsOneWidget);
    expect(find.text('Eğitim'), findsOneWidget);
    expect(find.textContaining(tail), findsOneWidget);
    expect(find.textContaining('|'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('kanonik delta kontenjan, tarih ve kadro kontenjanını kart/ayrıntı için kayıpsız günceller', () async {
    final folder = await Directory.systemTemp.createTemp('kamubul-quota-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/catalogue.db';
    Future<ListingStore> open() async => ListingStore(
      database: await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 11,
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    var store = await open();
    final first = {
      ...item,
      'quota': 12,
      'deadline': '2026-10-12T20:59:00Z',
      'requirementGroups': [
        {'label': 'Mühendis', 'quota': 12},
      ],
      'extraction': {
        'method': 'mechanical',
        'status': 'complete',
        'missing': [],
        'version': 'facts-v1',
      },
    };
    await store.applyDeltaPage(
      CatalogueDeltaPage(1, 1, false, [
        CatalogueChange(1, 'ilangov:1', 1, false, first),
      ]),
      after: 0,
    );
    expect((await store.allListings()).single.quota, 12);
    final second = {
      ...first,
      'revision': 2,
      'quota': 20,
      'deadline': '2026-10-15T20:59:00Z',
      'requirementGroups': [
        {'label': 'Mühendis', 'quota': 12},
        {'label': 'Tekniker', 'quota': 8},
      ],
      'extraction': {
        'method': 'hybrid',
        'status': 'partial',
        'missing': ['kpssYear'],
        'version': 'facts-v1',
      },
    };
    await store.applyDeltaPage(
      CatalogueDeltaPage(2, 2, false, [
        CatalogueChange(2, 'ilangov:1', 2, false, second),
      ]),
      after: 1,
    );
    await store.close();
    store = await open();
    addTearDown(store.close);
    final cached = (await store.allListings()).single;
    final detail = ListingStore.projectRemoteListing(second)!;
    expect(cached.quota, 20);
    expect(cached.quota, detail.quota);
    expect(cached.deadline!.toUtc(), detail.deadline!.toUtc());
    expect(cached.deadline!.toUtc(), DateTime.utc(2026, 10, 15, 20, 59));
    expect(
      cached.criteriaListing?['requirementGroups'],
      second['requirementGroups'],
    );
    expect(cached.criteriaListing?['extraction'], second['extraction']);
    expect(cached.conditionsCaption, 'Koşullar kısmen ayrıştırıldı');
    expect(cached.noticeText, contains(tail));
  });

  testWidgets(
    'grup sayısı kontenjan değildir; alıntı açılır, AI uyarısı yalnız AI/hybrid kökeninde görünür',
    (tester) async {
      const quote = 'Adaylar lisans mezunu olmalıdır.';
      for (final method in ['mechanical', 'ai', 'hybrid']) {
        final record = ListingStore.projectRemoteListing({
          ...item,
          'quota': null,
          'extraction': {
            'method': method,
            'status': method == 'mechanical' ? 'partial' : 'complete',
            'missing': [],
            'version': 'facts-v1',
          },
          'requirementGroups': [
            {
              'label': 'Kadro 1',
              'education': ['Lisans'],
              'quotes': {'education': quote},
            },
          ],
        })!;
        await tester.pumpWidget(
          MaterialApp(home: OfficialListingPage(listing: record)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Kadro 1'), findsNothing);
        expect(find.text('1 kişi'), findsNothing);
        // Yapay zekâ katkısı özet kartında, eğitim pozisyon çipinde görünür;
        // teknik "kısmen ayrıştırıldı" yazısı ve kanıt alıntısı gösterilmez.
        expect(
          find.text('Yapay zekâ ile ayıklandı; hata olabilir.'),
          method == 'mechanical' ? findsNothing : findsOneWidget,
        );
        expect(find.textContaining('ayrıştırılamadı'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Lisans'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Başvuru koşulları'), findsWidgets);
        expect(find.text('Lisans'), findsOneWidget);
        expect(find.textContaining(quote), findsNothing);
        await tester.scrollUntilVisible(
          find.textContaining(tail),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining(tail), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('ayrıntı gerçek toplamı ve kadro kontenjanını ayrı gösterir', (
    tester,
  ) async {
    final record = ListingStore.projectRemoteListing({
      ...item,
      'quota': 20,
      'deadline': '2026-10-15T20:59:00Z',
      'requirementGroups': [
        {
          'label': 'Mühendis',
          'quota': 12,
          'occupations': ['Mühendis'],
        },
      ],
    })!;
    await tester.pumpWidget(
      MaterialApp(home: OfficialListingPage(listing: record)),
    );
    expect(find.text('20 kişi'), findsOneWidget);
    expect(find.text('15.10.2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('12 kişi'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('12 kişi'), findsOneWidget);
    expect(find.text('Mühendis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resmî 13:00 son saat gösterilir ve pozisyonun özgün koşulları açılır',
    (tester) async {
      const position =
          'Tekniker | 8 kişi | Önlisans | Belge teslimi saat 13:00';
      final record = ListingStore.projectRemoteListing({
        ...item,
        'quota': 8,
        'deadline': '2026-10-15T10:00:00Z',
        'requirementGroups': [
          {'label': 'Tekniker', 'quota': 8, 'text': position},
        ],
      })!;
      await tester.pumpWidget(
        MaterialApp(home: OfficialListingPage(listing: record)),
      );
      expect(find.text('15.10.2026 • 13:00'), findsOneWidget);
      // Pozisyonun özgün satırı açılır pencere olmadan, hücrelerine ayrılmış görünür.
      await tester.scrollUntilVisible(
        find.text('Belge teslimi saat 13:00'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Aranan nitelikler'), findsOneWidget);
      expect(find.text('Önlisans'), findsOneWidget);
      expect(find.text(position), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('kompakt ayrıntı büyük yazıda ve yatay ekranda taşmaz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final record = ListingStore.projectRemoteListing({
      ...item,
      'quota': 20,
      'deadline': '2026-10-15T10:00:00Z',
      'requirementGroups': [
        {
          'label': 'Tekniker ve teknik destek personeli',
          'quota': 12,
          'education': ['Önlisans'],
          'text': tail,
          'quotes': {'education': tail},
        },
      ],
    })!;
    for (final (size, scale, brightness) in [
      (const Size(320, 700), 2.0, Brightness.light),
      (const Size(844, 390), 1.3, Brightness.dark),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: OfficialListingPage(listing: record),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('20 kişi'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('15.10.2026 • 13:00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('12 kişi'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Genel başvuru metni'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Genel başvuru metni'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'pozisyona göre değişen takvim tek bir genel son tarih olarak gösterilmez',
    (tester) async {
      const doctor =
          'Doktor Öğretim Üyesi başvuruları ilan tarihinden itibaren 75 gün alınır.';
      const instructor =
          'Öğretim Görevlisi başvuruları 12 Ekim 2026 saat 13:00 tarihinde biter.';
      final periods = [
        {'deadline': null, 'text': doctor},
        {'deadline': '2026-10-12T10:00:00Z', 'text': instructor},
      ];
      final record = ListingStore.projectRemoteListing({
        ...item,
        'deadline': null,
        'applicationPeriods': periods,
        'extraction': {
          'method': 'mechanical',
          'status': 'partial',
          'missing': ['deadline_scope'],
          'version': 'facts-v1',
        },
      })!;
      expect(record.deadline, isNull);
      expect(record.criteriaListing?['applicationPeriods'], periods);
      await tester.pumpWidget(
        MaterialApp(home: OfficialListingPage(listing: record)),
      );
      // Tek bir genel son tarih yerine takvim doğrudan listelenir.
      expect(find.text('Takvime bakın'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(doctor),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Başvuru takvimi'), findsOneWidget);
      expect(find.text(doctor), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(instructor),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(instructor), findsOneWidget);
      expect(find.text('12.10.2026 • 13:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
