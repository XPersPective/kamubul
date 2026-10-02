import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

String _body() => CatalogueSnapshot(
  generatedAt: DateTime(2026, 9, 29, 8),
  sources: const [],
  listings: [
    ListingRecord(
      url: 'https://x.gov.tr/1',
      sourceId: 'kariyerkapisi',
      title: 'KURUM - İlan',
      category: 'Personel',
      publishedAt: null,
      fetchedAt: DateTime(2026, 9, 29, 8),
    ),
  ],
).encode();

void main() {
  final base = Uri.parse('https://kamubul.example');

  Map<String, Object?> detail(String id) => {
    'id': id,
    'revision': 3,
    'active': true,
    'sourceId': 'kariyerkapisi',
    'url': 'https://kariyerkapisi.gov.tr/IlanDetay?i=real',
    'title': 'Kurum personel ilanı',
    'category': 'Personel',
    'updatedAt': '2026-10-02T08:00:00Z',
    'summary': [
      {'text': 'Başvuru yalnız resmî bağlantıdan yapılacaktır.'},
    ],
  };
  http.Response detailResponse(Map<String, Object?> data) =>
      http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

  test(
    'single detail preserves stable identity and safely encodes an opaque ID',
    () async {
      const id = 'source:part/with?#ü';
      for (final active in [true, false]) {
        final client = RemoteCatalogueClient(
          baseUrl: Uri.parse('https://kamubul.example/prefix'),
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.host, base.host);
            expect(request.url.pathSegments, [
              'prefix',
              'api',
              'v2',
              'listings',
              id,
            ]);
            expect(request.url.hasQuery, isFalse);
            expect(request.url.hasFragment, isFalse);
            expect(request.headers['Accept'], 'application/json');
            return detailResponse({...detail(id), 'active': active});
          }),
        );
        final result = await client.fetchListing(id);
        expect(result?['id'], id);
        expect(result?['revision'], 3);
        expect(result?['active'], active);
        expect((result?['summary'] as List).single['text'], contains('resmî'));
      }
    },
  );

  test(
    'single detail distinguishes not found from transport and invalid identity',
    () async {
      final missing = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      expect(await missing.fetchListing('id'), isNull);
      for (final response in [
        http.Response('{}', 503),
        http.Response('broken', 200),
        detailResponse(detail('other')),
        detailResponse({...detail('id'), 'active': 'false'}),
        detailResponse({...detail('id'), 'revision': 0}),
      ]) {
        final client = RemoteCatalogueClient(
          baseUrl: base,
          client: MockClient((_) async => response),
        );
        await expectLater(
          client.fetchListing('id'),
          throwsA(isA<RemoteCatalogueException>()),
        );
      }
      var requests = 0;
      final invalid = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(invalid.fetchListing(''), throwsArgumentError);
      await expectLater(invalid.fetchListing('x' * 201), throwsArgumentError);
      expect(requests, 0);
    },
  );

  test('single detail enforces streamed size and timeout', () async {
    final oversized = RemoteCatalogueClient(
      baseUrl: base,
      maxBytes: 32,
      client: MockClient((_) async => detailResponse(detail('id'))),
    );
    await expectLater(
      oversized.fetchListing('id'),
      throwsA(isA<RemoteCatalogueException>()),
    );
    final slow = RemoteCatalogueClient(
      baseUrl: base,
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return detailResponse(detail('id'));
      }),
    );
    await expectLater(
      slow.fetchListing('id'),
      throwsA(isA<RemoteCatalogueException>()),
    );
  });

  test(
    'only bounded endpoint-specific 409 errors request retention recovery',
    () async {
      for (final snapshot in [false, true]) {
        final code = snapshot ? 'snapshot_expired' : 'cursor_expired';
        for (final response in [
          http.Response(jsonEncode({'error': code}), 409),
          http.Response(jsonEncode({'error': code}), 503),
          http.Response(jsonEncode({'error': 'cursor_ahead'}), 409),
          http.Response(
            jsonEncode({
              'error': snapshot ? 'cursor_expired' : 'snapshot_expired',
            }),
            409,
          ),
          http.Response('bad json', 409),
          http.Response('x' * 1025, 409),
        ]) {
          final client = RemoteCatalogueClient(
            baseUrl: base,
            client: MockClient((_) async => response),
          );
          final expired =
              response.statusCode == 409 &&
              response.body == jsonEncode({'error': code});
          await expectLater(
            snapshot
                ? client.fetchCataloguePage(watermark: 1)
                : client.fetchChanges(after: 1),
            throwsA(
              expired
                  ? isA<RemoteCatalogueExpiredException>()
                  : isA<RemoteCatalogueException>().having(
                      (e) => e is RemoteCatalogueExpiredException,
                      'expired',
                      false,
                    ),
            ),
          );
        }
      }
    },
  );

  test(
    'frozen catalogue HTTP page validates watermark and bounds body',
    () async {
      for (final body in [
        jsonEncode({'watermark': 2, 'items': [], 'next': null}),
        'x' * (2 * 1024 * 1024 + 1),
      ]) {
        final client = RemoteCatalogueClient(
          baseUrl: base,
          client: MockClient((request) async {
            expect(request.url.path, '/api/v2/listings');
            expect(request.url.queryParameters, {
              'watermark': '1',
              'after': 'a',
              'limit': '30',
            });
            return http.Response(body, 200);
          }),
        );
        await expectLater(
          client.fetchCataloguePage(watermark: 1, after: 'a'),
          throwsA(isA<RemoteCatalogueException>()),
        );
      }
      final client = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'watermark': 1, 'items': [], 'next': null}),
            200,
          ),
        ),
      );
      expect((await client.fetchCataloguePage(watermark: 1)).items, isEmpty);
    },
  );

  test(
    'v2 metadata UTC source timestamps and conditional ETag are read',
    () async {
      final body = jsonEncode({
        'schemaVersion': 2,
        'taxonomyVersion': 1,
        'latestSeq': 40,
        'oldestRetainedSeq': 1,
        'sources': [
          {
            'id': 'kariyerkapisi',
            'name': 'Kariyer',
            'state': 'ok',
            'last_success': '2026-10-01T08:00:00Z',
          },
        ],
      });
      final client = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v2/meta');
          expect(request.headers['If-None-Match'], '"old"');
          return http.Response(body, 200, headers: {'etag': '"new"'});
        }),
      );
      final result = await client.fetchMetadata(etag: '"old"');
      expect(result.etag, '"new"');
      expect(result.metadata!.latestSeq, 40);
      expect(
        result.metadata!.sources.single.lastSuccessAt,
        DateTime.utc(2026, 10, 1, 8),
      );
      final unchanged = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient((_) async => http.Response('', 304)),
      );
      final cached = await unchanged.fetchMetadata(etag: '"new"');
      expect(cached.metadata, isNull);
      expect(cached.etag, '"new"');
    },
  );

  test('v2 metadata invalid schema/source/date and oversized response are rejected', () async {
    final good = {
      'schemaVersion': 2,
      'taxonomyVersion': 1,
      'latestSeq': 40,
      'oldestRetainedSeq': 1,
      'sources': [],
    };
    for (final body in [
      jsonEncode({...good, 'schemaVersion': 3}),
      jsonEncode({...good, 'oldestRetainedSeq': 41}),
      jsonEncode({
        ...good,
        'sources': [
          {'id': 'x', 'name': 'X', 'state': 'ok', 'last_success': 'bad date'},
        ],
      }),
      'x' * 65537,
    ]) {
      final client = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        client.fetchMetadata(),
        throwsA(isA<RemoteCatalogueException>()),
      );
    }
  });

  test('200 yanıt okunur ve ETag döner; If-None-Match gönderilir', () async {
    String? sentEtag;
    final client = RemoteCatalogueClient(
      baseUrl: base,
      client: MockClient((request) async {
        sentEtag = request.headers['If-None-Match'];
        expect(request.url.path, '/v1/listings.json');
        return http.Response.bytes(
          utf8.encode(_body()),
          200,
          headers: {'etag': '"abc"'},
        );
      }),
    );
    final result = await client.fetchListings(etag: '"old"');
    expect(sentEtag, '"old"');
    expect(result.etag, '"abc"');
    expect(result.snapshot!.listings, hasLength(1));
  });

  test('304 değişmedi döner', () async {
    final client = RemoteCatalogueClient(
      baseUrl: base,
      client: MockClient((_) async => http.Response('', 304)),
    );
    final result = await client.fetchListings(etag: '"abc"');
    expect(result.notModified, isTrue);
    expect(result.snapshot, isNull);
  });

  test('hata durumları RemoteCatalogueException olur', () async {
    Future<Object?> run(MockClientHandler handler) async {
      final client = RemoteCatalogueClient(
        baseUrl: base,
        client: MockClient(handler),
      );
      try {
        await client.fetchListings();
        return null;
      } on RemoteCatalogueException catch (error) {
        return error;
      }
    }

    expect(
      await run((_) async => http.Response('yok', 500)),
      isA<RemoteCatalogueException>(),
    );
    expect(
      await run((_) async => http.Response('{bozuk', 200)),
      isA<RemoteCatalogueException>(),
    );
    expect(
      await run((_) async => throw http.ClientException('ağ yok')),
      isA<RemoteCatalogueException>(),
    );
    expect(
      await run(
        (_) async => http.Response.bytes(List.filled(9 * 1024 * 1024, 97), 200),
      ),
      isA<RemoteCatalogueException>(),
    );
  });

  test('yalnızca https (yerel adres hariç) kabul edilir', () {
    expect(
      () => RemoteCatalogueClient(baseUrl: Uri.parse('http://kamubul.example')),
      throwsArgumentError,
    );
    expect(
      () => RemoteCatalogueClient(baseUrl: Uri.parse('http://localhost:8080')),
      returnsNormally,
    );
    expect(
      () =>
          RemoteCatalogueClient(baseUrl: Uri.parse('https://kamubul.example')),
      returnsNormally,
    );
  });
}
