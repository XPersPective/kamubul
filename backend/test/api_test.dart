import 'dart:convert';
import 'dart:io';

import 'package:kamubul_backend/src/api.dart';
import 'package:kamubul_backend/src/file_storage.dart';
import 'package:kamubul_backend/src/rate_limit.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

String _snapshot() => CatalogueSnapshot(
  generatedAt: DateTime(2026, 9, 29, 8),
  sources: const [
    SourceStatus(
      id: 'kariyerkapisi',
      name: 'Kariyer Kapısı',
      state: SourceState.ok,
      listingCount: 1,
    ),
  ],
  listings: [
    listing(
      'https://kariyerkapisi.gov.tr/IlanDetay?i=1',
      places: const ['ANKARA'],
    ),
  ],
).encode();

Request _req(
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: headers,
  body: body is String ? body : (body == null ? null : jsonEncode(body)),
);

Map<String, String> _auth([String secret = deviceSecret]) => {
  'authorization': 'Bearer $secret',
};

Object _registration() => registration().toJson();

void main() {
  late Directory dir;
  late FileStorage storage;
  late ApiHandler api;
  var limit = 100;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kamubul_api_');
    storage = FileStorage(dir.path);
    api = ApiHandler(
      storage: storage,
      writeLimiter: RateLimiter(maxPerWindow: limit),
      snapshotCacheTtl: Duration.zero,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Response> call(Request r) => Future.value(api.call(r));

  test('katalog yayınlanmadıysa 503, health yine 200', () async {
    expect((await call(_req('GET', '/v1/listings.json'))).statusCode, 503);
    final health = await call(_req('GET', '/v1/health'));
    expect(health.statusCode, 200);
    expect(jsonDecode(await health.readAsString())['snapshot'], isFalse);
  });

  test('listings.json: ETag, önbellek başlığı ve 304', () async {
    await storage.writeSnapshot(_snapshot());
    final first = await call(_req('GET', '/v1/listings.json'));
    expect(first.statusCode, 200);
    final etag = first.headers['etag']!;
    expect(first.headers['cache-control'], contains('s-maxage=300'));
    final decoded = CatalogueSnapshot.decode(await first.readAsString());
    expect(decoded.listings.single.places, ['ANKARA']);

    final second = await call(
      _req('GET', '/v1/listings.json', headers: {'if-none-match': etag}),
    );
    expect(second.statusCode, 304);
    expect((await call(_req('POST', '/v1/listings.json'))).statusCode, 405);
  });

  test(
    'sources.json yalnızca kaynak durumlarını verir; health yaşı hesaplar',
    () async {
      await storage.writeSnapshot(_snapshot());
      final sources = jsonDecode(
        await (await call(_req('GET', '/v1/sources.json'))).readAsString(),
      );
      expect((sources['sources'] as List).single['state'], 'ok');
      expect(sources.containsKey('listings'), isFalse);
      final health = jsonDecode(
        await (await call(_req('GET', '/v1/health'))).readAsString(),
      );
      expect(health['listings'], 1);
      expect(health['snapshot'], isTrue);
    },
  );

  test('cihaz kaydı: oluştur 201, güncelle 200, gizli anahtar özet olarak saklanır', () async {
    final created = await call(
      _req(
        'PUT',
        '/v1/devices/$deviceId',
        headers: _auth(),
        body: _registration(),
      ),
    );
    expect(created.statusCode, 201);
    final stored = (await storage.getDevice(deviceId))!;
    expect(stored.secretHash, isNot(deviceSecret));
    expect(stored.secretHash, hasLength(64));
    expect(stored.registration.searches.single.name, 'Ankara');

    final updated = await call(
      _req(
        'PUT',
        '/v1/devices/$deviceId',
        headers: _auth(),
        body: _registration(),
      ),
    );
    expect(updated.statusCode, 200);
  });

  test('yanlış anahtar 403; başkasının kaydı ezilemez ve silinemez', () async {
    await call(
      _req(
        'PUT',
        '/v1/devices/$deviceId',
        headers: _auth(),
        body: _registration(),
      ),
    );
    final other = 'f' * 64;
    expect(
      (await call(
        _req(
          'PUT',
          '/v1/devices/$deviceId',
          headers: _auth(other),
          body: _registration(),
        ),
      )).statusCode,
      403,
    );
    expect(
      (await call(
        _req('DELETE', '/v1/devices/$deviceId', headers: _auth(other)),
      )).statusCode,
      403,
    );
    expect(await storage.getDevice(deviceId), isNotNull);
    expect(
      (await call(_req('DELETE', '/v1/devices/$deviceId', headers: _auth())))
          .statusCode,
      200,
    );
    expect(await storage.getDevice(deviceId), isNull);
    // Var olmayan kaydı silmek sızıntı yaratmaz.
    expect(
      (await call(_req('DELETE', '/v1/devices/$deviceId', headers: _auth())))
          .statusCode,
      200,
    );
  });

  test(
    'geçersiz kimlik, anahtar, JSON ve alanlar 400; büyük gövde 413',
    () async {
      expect(
        (await call(
          _req(
            'PUT',
            '/v1/devices/kötü',
            headers: _auth(),
            body: _registration(),
          ),
        )).statusCode,
        400,
      );
      expect(
        (await call(
          _req('PUT', '/v1/devices/$deviceId', body: _registration()),
        )).statusCode,
        400,
      );
      expect(
        (await call(
          _req(
            'PUT',
            '/v1/devices/$deviceId',
            headers: _auth('kısa'),
            body: _registration(),
          ),
        )).statusCode,
        400,
      );
      expect(
        (await call(
          _req(
            'PUT',
            '/v1/devices/$deviceId',
            headers: _auth(),
            body: '{bozuk',
          ),
        )).statusCode,
        400,
      );
      expect(
        (await call(
          _req(
            'PUT',
            '/v1/devices/$deviceId',
            headers: _auth(),
            body: {'fcmToken': 'x'},
          ),
        )).statusCode,
        400,
      );
      final huge = {
        ..._registration() as Map<String, Object?>,
        'pad': 'x' * (kMaxBodyBytes + 10),
      };
      expect(
        (await call(
          _req('PUT', '/v1/devices/$deviceId', headers: _auth(), body: huge),
        )).statusCode,
        413,
      );
      expect(await storage.getDevice(deviceId), isNull);
    },
  );

  test('yazma uçları istemci başına hız sınırlıdır', () async {
    final limited = ApiHandler(
      storage: storage,
      writeLimiter: RateLimiter(maxPerWindow: 2),
      snapshotCacheTtl: Duration.zero,
    );
    Future<int> put(String ip) async => (await limited.call(
      _req(
        'PUT',
        '/v1/devices/$deviceId',
        headers: {..._auth(), 'x-forwarded-for': ip},
        body: _registration(),
      ),
    )).statusCode;
    expect(await put('1.1.1.1'), 201);
    expect(await put('1.1.1.1'), 200);
    expect(await put('1.1.1.1'), 429);
    expect(await put('2.2.2.2'), 200); // başka istemci etkilenmez
  });

  test('bilinmeyen yol 404', () async {
    expect((await call(_req('GET', '/v1/yok'))).statusCode, 404);
    expect((await call(_req('GET', '/'))).statusCode, 404);
    expect((await call(_req('GET', '/v1/devices/$deviceId'))).statusCode, 405);
  });
}
