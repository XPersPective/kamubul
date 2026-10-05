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
    await tester.scrollUntilVisible(
      find.byType(SelectableText),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining(text), findsOneWidget);
    expect(find.textContaining(tail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
