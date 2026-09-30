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
