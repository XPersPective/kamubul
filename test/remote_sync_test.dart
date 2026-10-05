import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/catalogue_refresh.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/data/remote_sync.dart';
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

  String metadataBody({
    DateTime? generatedAt,
    SourceState kariyer = SourceState.ok,
    SourceState sbb = SourceState.ok,
    String sbbId = kSbbSourceId,
    SourceState? ilangov,
  }) => jsonEncode({
    'schemaVersion': 2,
    'taxonomyVersion': 1,
    'latestSeq': 1,
    'oldestRetainedSeq': 1,
    'sources': [
      for (final entry in [
        (kKariyerSourceId, 'Kariyer Kapısı', kariyer),
        (sbbId, 'Kamu İlanları (SBB)', sbb),
        ('iskur', 'İŞKUR', SourceState.blocked),
        if (ilangov != null) (kIlanGovSourceId, 'ilan.gov.tr', ilangov),
      ])
        {
          'id': entry.$1,
          'name': entry.$2,
          'state': entry.$3.name,
          'last_success': (generatedAt ?? DateTime(2026, 9, 29, 8))
              .toUtc()
              .toIso8601String(),
        },
    ],
  });

  RemoteCatalogueClient client(
    String body, {
    int status = 200,
  }) => RemoteCatalogueClient(
    baseUrl: Uri.parse('https://kamubul.example'),
    client: MockClient((request) async {
      if (request.url.path == '/api/v2/meta') {
        return http.Response.bytes(
          utf8.encode(body),
          status,
          headers: {'etag': '"meta1"'},
        );
      }
      expect(request.url.path, '/api/v2/listings');
      expect(request.url.queryParameters['watermark'], '1');
      return http.Response(
        jsonEncode({
          'watermark': 1,
          'next': null,
          'items': [
            {
              'id': 'stable',
              'revision': 1,
              'url': _url,
              'sourceId': kKariyerSourceId,
              'title': 'TEST KURUMU - Memur Alımı',
              'category': 'Personel',
              'publishedAt': '2026-09-28T08:00:00Z',
              'updatedAt': '2026-09-29T08:00:00Z',
              'deadline': '2026-10-12T20:59:00Z',
              'places': ['ANKARA'],
              'maxAge': 35,
              'maxAgeQuote': '35 yaşını doldurmamış olmak',
              'summary': [
                'Yaş sınırı 35',
                {
                  'text': '2024 KPSS (P94) puanı en az 60 puan ve üzeri olmak.',
                  'scopeLabel': 'Destek personeli',
                },
                {
                  'text':
                      'Başvurular yalnız Kariyer Kapısı üzerinden alınacaktır.',
                },
                {'text': null, 'scopeLabel': 'Geçersiz'},
              ],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  var kariyerCalls = 0;
  var sbbCalls = 0;
  // Sunucu sağlıklıyken de telefon Kariyer dizinini okur; bu yükleyici
  // çağrıyı sayar ama katalogu değiştirmez.
  Future<List<PublicListing>> emptyKariyer() async {
    kariyerCalls++;
    return const [];
  }

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

  test('live sbb source ID prevents fallback while fresh and healthy', () async {
    final store = await freshStore();
    addTearDown(store.close);
    final result = await refreshCatalogue(
      store,
      remote: client(metadataBody(sbbId: 'sbb')),
      kariyer: kariyerLoader,
      ilanGov: () async => [],
      iskur: () async => [],
      sbb: sbbLoader,
      at: now,
    );
    // Kariyer Kapısı ayrıntısı sunucuya kapalı: telefon dizini her zaman okur.
    expect(kariyerCalls, 1);
    expect(sbbCalls, 0);
    expect(result.sourceStatuses[1].id, 'sbb');
  });

  test('current wire SBB status wins conflicting legacy alias', () async {
    final body =
        jsonDecode(metadataBody(sbbId: 'sbb', sbb: SourceState.blocked)) as Map;
    (body['sources'] as List).insert(0, {
      'id': kSbbSourceId,
      'name': 'Eski SBB',
      'state': 'ok',
      'last_success': DateTime(2026, 9, 29, 8).toUtc().toIso8601String(),
    });
    final store = await freshStore();
    addTearDown(store.close);
    await refreshCatalogue(
      store,
      remote: client(jsonEncode(body)),
      kariyer: kariyerLoader,
      ilanGov: () async => [],
      iskur: () async => [],
      sbb: sbbLoader,
      at: now,
    );
    // Kariyer Kapısı ayrıntısı sunucuya kapalı: telefon dizini her zaman okur.
    expect(kariyerCalls, 1);
    expect(sbbCalls, 1);
  });

  test('expired delta or staged snapshot retries once with fresh metadata and keeps favorites', () async {
    for (final snapshot in [false, true]) {
      for (final failsAgain in [false, true]) {
        final store = await freshStore();
        addTearDown(store.close);
        await syncRemoteV2Catalogue(
          store: store,
          client: client(metadataBody()),
          now: now,
        );
        await store.setSaved(_url, true);
        final generation = await store.bindRemoteOrigin(
          'https://kamubul.example',
        );
        if (snapshot) {
          await store.beginBootstrap(
            latest: 2,
            oldest: 1,
            expectedGeneration: generation,
          );
          await store.stageCataloguePage(
            CataloguePage(2, [
              {
                'id': 'staged',
                'revision': 1,
                'url': 'https://example.gov.tr/staged',
                'title': 'Staged',
                'sourceId': kKariyerSourceId,
                'category': 'Personel',
                'updatedAt': '2026-09-29T08:00:00Z',
              },
            ], 'staged'),
            after: '',
            expectedGeneration: generation,
          );
        }
        var metas = 0, pages = 0;
        final remote = RemoteCatalogueClient(
          baseUrl: Uri.parse('https://kamubul.example'),
          client: MockClient((request) async {
            if (request.url.path == '/api/v2/meta') {
              metas++;
              final meta = jsonDecode(metadataBody()) as Map;
              meta['latestSeq'] = metas == 1 ? 2 : 4;
              meta['oldestRetainedSeq'] = metas == 1 ? 1 : 4;
              if (metas == 2) {
                expect(request.headers['If-None-Match'], isNull);
                expect(request.headers['Cache-Control'], 'no-cache');
              }
              return http.Response(
                jsonEncode(meta),
                200,
                headers: {
                  'etag': '"new"',
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            pages++;
            if (pages == 1 && snapshot) {
              expect(request.url.queryParameters['after'], 'staged');
            }
            if (pages == 1 || failsAgain) {
              return http.Response(
                jsonEncode({
                  'error': request.url.path.endsWith('changes')
                      ? 'cursor_expired'
                      : 'snapshot_expired',
                }),
                409,
              );
            }
            expect(request.url.path, '/api/v2/listings');
            expect(request.url.queryParameters['watermark'], '4');
            expect(request.url.queryParameters['after'], '');
            return http.Response(
              jsonEncode({'watermark': 4, 'items': [], 'next': null}),
              200,
            );
          }),
        );
        final sync = syncRemoteV2Catalogue(
          store: store,
          client: remote,
          now: now.add(const Duration(hours: 1)),
        );
        if (failsAgain) {
          await expectLater(
            sync,
            throwsA(isA<RemoteCatalogueExpiredException>()),
          );
          expect(await store.remoteCursor(), 1);
          expect((await store.remoteMetadata()).lastSuccess, now);
        } else {
          await sync;
          expect(await store.remoteCursor(), 4);
          expect((await store.remoteMetadata()).etag, '"new"');
        }
        expect(metas, 2);
        expect(pages, 2);
        expect((await store.allListings()).single.saved, true);
      }
    }
  });

  test(
    'tutulmayan eski cursor katalog silinmeden bootstrap gerektirir',
    () async {
      final store = await freshStore();
      await syncRemoteV2Catalogue(
        store: store,
        client: client(metadataBody()),
        now: now,
      );
      final metadata = jsonDecode(metadataBody()) as Map;
      metadata['latestSeq'] = 3;
      metadata['oldestRetainedSeq'] = 3;
      final requests = <http.Request>[];
      final retained = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://kamubul.example'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(metadata),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await expectLater(
        syncRemoteV2Catalogue(store: store, client: retained, now: now),
        throwsA(isA<RemoteCatalogueException>()),
      );
      expect(requests.map((r) => r.url.path), [
        '/api/v2/meta',
        '/api/v2/listings',
      ]);
      expect(await store.remoteCursor(), 1);
      expect((await store.allListings()).single.url, _url);
      expect((await store.remoteMetadata()).etag, '"meta1"');
    },
  );

  test('kalıcı metadata ETag ile 304 okur; değişiklik yoksa katalog tekrar indirilmez', () async {
    final store = await freshStore();
    final requests = <http.Request>[];
    final initial = client(metadataBody());
    await refreshCatalogue(
      store,
      remote: initial,
      kariyer: emptyKariyer,
      ilanGov: () async => [],
      iskur: () async => [],
      at: now,
    );
    final previous = await store.remoteMetadata();
    expect(previous.etag, '"meta1"');
    expect(previous.lastSuccess, now);
    final unchanged = RemoteCatalogueClient(
      baseUrl: Uri.parse('https://kamubul.example'),
      client: MockClient((request) async {
        requests.add(request);
        expect(request.url.path, '/api/v2/meta');
        expect(request.headers['If-None-Match'], '"meta1"');
        return http.Response('', 304);
      }),
    );
    await refreshCatalogue(
      store,
      remote: unchanged,
      kariyer: emptyKariyer,
      ilanGov: () async => [],
      iskur: () async => [],
      at: now.add(const Duration(hours: 1)),
    );
    expect(requests, hasLength(1));
    expect(await store.remoteCursor(), 1);
    expect(
      (await store.allListings()).single.deadline!.toUtc(),
      DateTime.utc(2026, 10, 12, 20, 59),
    );
    expect(
      (await store.remoteMetadata()).lastSuccess,
      now.add(const Duration(hours: 1)),
    );
  });

  test(
    'yarım delta son başarılı noktadan sürer; tam başarı zamanı erken yazılmaz',
    () async {
      final store = await freshStore();
      await syncRemoteV2Catalogue(
        store: store,
        client: client(metadataBody()),
        now: now,
      );
      final later = now.add(const Duration(hours: 1));
      var fail = true;
      final cursors = <String>[];
      final remote = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://kamubul.example'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v2/meta') {
            final meta = jsonDecode(metadataBody()) as Map;
            meta['latestSeq'] = 3;
            return http.Response(
              jsonEncode(meta),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final after = request.url.queryParameters['after']!;
          cursors.add(after);
          expect(request.url.queryParameters['watermark'], '3');
          if (after == '2' && fail) return http.Response('', 503);
          final seq = int.parse(after) + 1;
          return http.Response(
            jsonEncode({
              'watermark': 3,
              'appliedThrough': seq,
              'hasMore': seq < 3,
              'changes': [
                {
                  'seq': seq,
                  'id': 'stable',
                  'revision': seq,
                  'operation': 'upsert',
                  'item': {
                    'id': 'stable',
                    'revision': seq,
                    'url': _url,
                    'sourceId': kKariyerSourceId,
                    'title': 'Memur $seq',
                    'category': 'Personel',
                    'updatedAt': '2026-09-29T08:00:00Z',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      await expectLater(
        syncRemoteV2Catalogue(store: store, client: remote, now: later),
        throwsA(isA<RemoteCatalogueException>()),
      );
      expect(await store.remoteCursor(), 2);
      expect((await store.remoteMetadata()).lastSuccess, now);
      fail = false;
      await syncRemoteV2Catalogue(store: store, client: remote, now: later);
      expect(cursors.last, '2');
      expect(await store.remoteCursor(), 3);
      expect((await store.allListings()).single.title, 'Memur 3');
      expect((await store.remoteMetadata()).lastSuccess, later);
    },
  );

  test('sunucu kaynakları sağlıklıysa gömülü çekim çalışmaz; alanlar ve özet yerele işlenir', () async {
    final store = await freshStore();
    final result = await refreshCatalogue(
      store,
      remote: client(metadataBody()),
      kariyer: emptyKariyer,
      ilanGov: () async => [],
      iskur: () async => [],
      sbb: sbbLoader,
      at: now,
    );
    // Kariyer Kapısı ayrıntısı sunucuya kapalı: telefon dizini her zaman okur.
    expect(kariyerCalls, 1);
    expect(sbbCalls, 0);
    expect(result.failedSources, isEmpty);
    expect(result.remoteFailed, false);
    expect(result.remoteLastSuccess, now);
    expect(result.sourceStatuses.map((s) => s.state), [
      SourceState.ok,
      SourceState.ok,
      SourceState.blocked,
    ]);
    final stored = (await store.allListings()).single;
    expect(stored.places, ['ANKARA']);
    expect(stored.maxAge, 35);
    expect(stored.maxAgeQuote, '35 yaşını doldurmamış olmak');
    expect(stored.summary, [
      'Yaş sınırı 35',
      'Destek personeli: 2024 KPSS (P94) puanı en az 60 puan ve üzeri olmak.',
      'Başvurular yalnız Kariyer Kapısı üzerinden alınacaktır.',
    ]);
  });

  test('sunucu SBB\'yi sağlayamıyorsa yalnızca SBB cihazdan çekilir', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(metadataBody(sbb: SourceState.blocked)),
      kariyer: kariyerLoader,
      ilanGov: () async => [],
      iskur: () async => [],
      sbb: sbbLoader,
      at: now,
    );
    // Kariyer Kapısı ayrıntısı sunucuya kapalı: telefon dizini her zaman okur.
    expect(kariyerCalls, 1);
    expect(sbbCalls, 1);
  });

  test(
    'sunucuya ulaşılamazsa tüm kaynaklar cihazdan çekilir, yerel kayıt korunur',
    () async {
      final store = await freshStore();
      await refreshCatalogue(
        store,
        remote: client(metadataBody()),
        kariyer: kariyerLoader,
        ilanGov: () async => [],
        iskur: () async => [],
        sbb: sbbLoader,
        at: now,
      );
      final result = await refreshCatalogue(
        store,
        remote: client('hata', status: 503),
        kariyer: kariyerLoader,
        ilanGov: () async => [],
        iskur: () async => [],
        sbb: sbbLoader,
        at: now.add(const Duration(hours: 6)),
      );
      expect(kariyerCalls, 2);
      expect(sbbCalls, 1);
      expect(result.failedSources, isEmpty);
      expect(result.remoteFailed, true);
      expect(result.remoteLastSuccess, now);
      expect(result.sourceStatuses, hasLength(3));
      final urls = (await store.allListings()).map((r) => r.url).toSet();
      expect(urls, {_url, 'https://kariyerkapisi.gov.tr/IlanDetay?i=99'});
    },
  );

  test(
    'kaynağın son başarısı 36 saatten eskiyse geçişteki yedek yol çalışır',
    () async {
      final store = await freshStore();
      await refreshCatalogue(
        store,
        remote: client(metadataBody(generatedAt: DateTime(2026, 9, 27, 8))),
        kariyer: kariyerLoader,
        ilanGov: () async => [],
        iskur: () async => [],
        sbb: sbbLoader,
        at: now,
      );
      expect(kariyerCalls, 1);
      expect(sbbCalls, 1);
    },
  );

  test('uzak katalog yapılandırılmamışsa davranış eskisi gibidir', () async {
    final store = await freshStore();
    final result = await refreshCatalogue(
      store,
      kariyer: kariyerLoader,
      ilanGov: () async => [],
      iskur: () async => [],
      sbb: () async => throw const FormatException('kapalı'),
      at: now,
    );
    expect(kariyerCalls, 1);
    expect(result.failedSources, ['Kamu İlanları (SBB)']);
    expect(result.sourceStatuses, isEmpty);
  });

  test('sunucudan gelen kayıt kaydedilmiş ilanı sıfırlamaz', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(metadataBody()),
      kariyer: emptyKariyer,
      ilanGov: () async => [],
      iskur: () async => [],
      at: now,
    );
    await store.setSaved(_url, true);
    await refreshCatalogue(
      store,
      remote: client(metadataBody()),
      kariyer: emptyKariyer,
      ilanGov: () async => [],
      iskur: () async => [],
      at: now.add(const Duration(hours: 6)),
    );
    final stored = (await store.allListings()).single;
    expect(stored.saved, isTrue);
  });

  test('sunucu ilan.gov.tr sağlıklıysa telefon okumaz; engelliyse okur', () async {
    for (final (state, expected) in [
      (SourceState.ok, 0),
      (SourceState.blocked, 1),
    ]) {
      final store = await freshStore();
      var calls = 0;
      await refreshCatalogue(
        store,
        remote: client(metadataBody(ilangov: state)),
        kariyer: emptyKariyer,
        ilanGov: () async {
          calls++;
          return [];
        },
        iskur: () async => [],
        at: now,
      );
      expect(calls, expected, reason: state.name);
      await store.close();
    }
  });
}
