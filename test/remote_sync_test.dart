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

  test(
    'live sbb source ID prevents fallback while fresh and healthy',
    () async {
      final store = await freshStore();
      addTearDown(store.close);
      final result = await refreshCatalogue(
        store,
        remote: client(metadataBody(sbbId: 'sbb')),
        at: now,
      );
      expect(result.sourceStatuses[1].id, 'sbb');
    },
  );

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
    await refreshCatalogue(store, remote: client(jsonEncode(body)), at: now);
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

  test(
    'uzun aradan sonra yüzlerce revizyon yerine güncel katalog bir kez indirilir',
    () async {
      final store = await freshStore();
      await syncRemoteV2Catalogue(
        store: store,
        client: client(metadataBody()),
        now: now,
      );
      final paths = <String>[];
      final remote = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://kamubul.example'),
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/v2/meta') {
            final meta = jsonDecode(metadataBody()) as Map;
            meta['latestSeq'] = 1001;
            return http.Response(
              jsonEncode(meta),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(request.url.path, '/api/v2/listings');
          expect(request.url.queryParameters['watermark'], '1001');
          return http.Response(
            jsonEncode({
              'watermark': 1001,
              'next': null,
              'items': [
                {
                  'id': 'stable',
                  'revision': 9,
                  'url': _url,
                  'sourceId': kKariyerSourceId,
                  'title': 'Güncel ilan',
                  'category': 'Personel',
                  'updatedAt': '2026-10-06T08:00:00Z',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await syncRemoteV2Catalogue(store: store, client: remote, now: now);
      expect(paths.where((p) => p == '/api/v2/changes'), isEmpty);
      expect(await store.remoteCursor(), 1001);
      expect((await store.allListings()).single.title, 'Güncel ilan');
    },
  );

  test('kalıcı metadata ETag ile 304 okur; değişiklik yoksa katalog tekrar indirilmez', () async {
    final store = await freshStore();
    final requests = <http.Request>[];
    final initial = client(metadataBody());
    await refreshCatalogue(store, remote: initial, at: now);
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
      at: now,
    );
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

  test('sunucu engelli kaynak durumunu iletir; cihaz kaynak okumaz', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(metadataBody(sbb: SourceState.blocked)),
      at: now,
    );
    expect((await store.allListings()).single.url, _url);
    final metadata = CatalogueMetadata.decode(
      jsonDecode((await store.remoteMetadata()).metadata!),
    );
    expect(metadata.sources[1].state, SourceState.blocked);
  });

  test(
    'sunucuya ulaşılamazsa yalnız önbellek korunur, kaynak fallback yok',
    () async {
      final store = await freshStore();
      await refreshCatalogue(store, remote: client(metadataBody()), at: now);
      final result = await refreshCatalogue(
        store,
        remote: client('hata', status: 503),
        at: now.add(const Duration(hours: 6)),
      );
      expect(result.failedSources, isEmpty);
      expect(result.remoteFailed, true);
      expect(result.remoteLastSuccess, now);
      expect(result.sourceStatuses, hasLength(3));
      final urls = (await store.allListings()).map((r) => r.url).toSet();
      expect(urls, {_url});
    },
  );

  test('kaynak bayat olsa da cihaz yalnız sunucu kataloğunu okur', () async {
    final store = await freshStore();
    await refreshCatalogue(
      store,
      remote: client(metadataBody(generatedAt: DateTime(2026, 9, 27, 8))),
      at: now,
    );
  });

  test(
    'uzak katalog yapılandırılmamışsa hata bildirilir ve kaynak okunmaz',
    () async {
      final store = await freshStore();
      final result = await refreshCatalogue(store, at: now);
      expect(result.failedSources, isEmpty);
      expect(result.remoteFailed, isTrue);
      expect(result.sourceStatuses, isEmpty);
    },
  );

  test('sunucudan gelen kayıt kaydedilmiş ilanı sıfırlamaz', () async {
    final store = await freshStore();
    await refreshCatalogue(store, remote: client(metadataBody()), at: now);
    await store.setSaved(_url, true);
    await refreshCatalogue(
      store,
      remote: client(metadataBody()),
      at: now.add(const Duration(hours: 6)),
    );
    final stored = (await store.allListings()).single;
    expect(stored.saved, isTrue);
  });

  test('kaynak ok, blocked veya failed olsa da yalnız API okunur', () async {
    for (final state in [
      SourceState.ok,
      SourceState.blocked,
      SourceState.failed,
    ]) {
      final store = await freshStore();
      final requests = <Uri>[];
      final remote = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://kamubul.example'),
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path == '/api/v2/meta') {
            return http.Response.bytes(
              utf8.encode(metadataBody(ilangov: state)),
              200,
            );
          }
          return http.Response(
            jsonEncode({'watermark': 1, 'items': [], 'next': null}),
            200,
          );
        }),
      );
      final result = await refreshCatalogue(store, remote: remote, at: now);
      expect(result.sourceStatuses.last.state, state);
      expect(requests.map((uri) => uri.host).toSet(), {'kamubul.example'});
      expect(requests.map((uri) => uri.path), [
        '/api/v2/meta',
        '/api/v2/listings',
      ]);
      expect(await store.allListings(), isEmpty);
      await store.close();
    }
  });
}
