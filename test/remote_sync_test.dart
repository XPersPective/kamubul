import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/catalogue_refresh.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/listings/kariyer_feed.dart';
import 'package:kamubul/listings/sbb_feed.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _url = 'https://kariyerkapisi.gov.tr/IlanDetay?i=7';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<ListingStore> freshStore() async => ListingStore(
    database: await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: ListingStore.createSchema,
      ),
    ),
  );

  final now = DateTime(2026, 9, 29, 13);

  String snapshotBody({
    DateTime? generatedAt,
    SourceState kariyer = SourceState.ok,
    SourceState sbb = SourceState.ok,
  }) => CatalogueSnapshot(
    generatedAt: generatedAt ?? DateTime(2026, 9, 29, 8),
    sources: [
      SourceStatus(id: kKariyerSourceId, name: 'Kariyer Kapısı', state: kariyer),
      SourceStatus(id: kSbbSourceId, name: 'Kamu İlanları (SBB)', state: sbb),
      const SourceStatus(
        id: 'iskur',
        name: 'İŞKUR',
        state: SourceState.blocked,
        note: 'WAF',
      ),
    ],
    listings: [
      ListingRecord(
        url: _url,
        sourceId: kKariyerSourceId,
        title: 'TEST KURUMU - Memur Alımı',
        category: 'Personel',
        publishedAt: DateTime(2026, 9, 28),
        fetchedAt: DateTime(2026, 9, 29, 8),
        deadline: DateTime(2026, 10, 12, 23, 59),
        places: const ['ANKARA'],
        maxAge: 35,
        maxAgeQuote: '35 yaşını doldurmamış olmak',
        summary: const ['Yaş sınırı 35'],
      ),
    ],
  ).encode();

  RemoteCatalogueClient client(String body, {int status = 200}) =>
      RemoteCatalogueClient(
        baseUrl: Uri.parse('https://kamubul.example'),
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(body), status),
        ),
      );

  var kariyerCalls = 0;
  var sbbCalls = 0;
  Future<List<PublicListing>> kariyerLoader() async {
    kariyerCalls++;
    return [
      PublicListing(
        title: 'YEDEK KURUM - Alım',
        category: 'Personel',
        url: Uri.parse('https://kariyerkapisi.gov.tr/IlanDetay?i=99'),
        publishedAt: DateTime(2026, 9, 28),
      ),
    ];
  }

  Future<List<SbbListing>> sbbLoader() async {
    sbbCalls++;
    return const [];
  }

  setUp(() {
    kariyerCalls = 0;
    sbbCalls = 0;
  });

  test('sunucu kaynakları sağlıklıysa gömülü çekim çalışmaz; alanlar ve özet yerele işlenir', () async {
    final store = await freshStore();
    final result = await refreshCatalogue(
      store,
      remote: client(snapshotBody()),
      kariyer: kariyerLoader,
      sbb: sbbLoader,
      at: now,
    );
    expect(kariyerCalls, 0);
    expect(sbbCalls, 0);
    expect(result.failedSources, isEmpty);
    expect(
      result.sourceStatuses.map((s) => s.state),
      [SourceState.ok, SourceState.ok, SourceState.blocked],
    );
    final stored = (await store.allListings()).single;
    expect(stored.places, ['ANKARA']);
    expect(stored.maxAge, 35);
    expect(stored.maxAgeQuote, '35 yaşını doldurmamış olmak');
    expect(stored.summary, ['Yaş sınırı 35']);
  });

  test('sunucu SBB\'yi sağlayamıyorsa yalnızca SBB cihazdan çekilir', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(snapshotBody(sbb: SourceState.blocked)),
      kariyer: kariyerLoader,
      sbb: sbbLoader,
      at: now,
    );
    expect(kariyerCalls, 0);
    expect(sbbCalls, 1);
  });

  test('sunucuya ulaşılamazsa tüm kaynaklar cihazdan çekilir, yerel kayıt korunur', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(snapshotBody()),
      kariyer: kariyerLoader,
      sbb: sbbLoader,
      at: now,
    );
    final result = await refreshCatalogue(
      store,
      remote: client('hata', status: 503),
      kariyer: kariyerLoader,
      sbb: sbbLoader,
      at: now.add(const Duration(hours: 6)),
    );
    expect(kariyerCalls, 1);
    expect(sbbCalls, 1);
    expect(result.failedSources, isEmpty);
    expect(result.sourceStatuses, isEmpty);
    final urls = (await store.allListings()).map((r) => r.url).toSet();
    expect(urls, {_url, 'https://kariyerkapisi.gov.tr/IlanDetay?i=99'});
  });

  test('bayat sunucu anlık görüntüsü (36 saatten eski) yedek çekimi tetikler', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(snapshotBody(generatedAt: DateTime(2026, 9, 27, 8))),
      kariyer: kariyerLoader,
      sbb: sbbLoader,
      at: now,
    );
    expect(kariyerCalls, 1);
    expect(sbbCalls, 1);
  });

  test('uzak katalog yapılandırılmamışsa davranış eskisi gibidir', () async {
    final store = await freshStore();
    final result = await refreshCatalogue(
      store,
      kariyer: kariyerLoader,
      sbb: () async => throw const FormatException('kapalı'),
      at: now,
    );
    expect(kariyerCalls, 1);
    expect(result.failedSources, ['Kamu İlanları (SBB)']);
    expect(result.sourceStatuses, isEmpty);
  });

  test('sunucudan gelen kayıt kaydedilmiş ilanı sıfırlamaz', () async {
    final store = await freshStore();
    await refreshCatalogue(store, remote: client(snapshotBody()), at: now);
    await store.setSaved(_url, true);
    await refreshCatalogue(
      store,
      remote: client(snapshotBody()),
      at: now.add(const Duration(hours: 6)),
    );
    final stored = (await store.allListings()).single;
    expect(stored.saved, isTrue);
  });
}

