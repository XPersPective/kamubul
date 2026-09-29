import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_backend/src/file_storage.dart';
import 'package:kamubul_backend/src/firestore_storage.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Firestore REST davranışını taklit eden bellek içi sahte sunucu.
class FakeFirestore {
  final docs = <String, Map<String, Object?>>{};
  int requests = 0;

  static const _prefix = '/v1/projects/p/databases/(default)/documents/';

  Future<http.Response> handle(http.Request request) async {
    requests++;
    final path = request.url.path;
    final name = path.startsWith(_prefix)
        ? path.substring(_prefix.length)
        : path;
    switch (request.method) {
      case 'GET':
        if (name == 'devices') return _list(request);
        final doc = docs[name];
        return doc == null
            ? http.Response('{}', 404)
            : _ok({'name': name, 'fields': doc});
      case 'PATCH':
        docs[name] =
            (jsonDecode(request.body) as Map<String, Object?>)['fields']
                as Map<String, Object?>;
        return _ok({'name': name});
      case 'DELETE':
        docs.remove(name);
        return _ok({});
    }
    return http.Response('yok', 405);
  }

  http.Response _ok(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _list(http.Request request) {
    final ids = docs.keys.where((k) => k.startsWith('devices/')).toList()
      ..sort();
    final size = int.parse(request.url.queryParameters['pageSize'] ?? '300');
    final start =
        int.tryParse(request.url.queryParameters['pageToken'] ?? '') ?? 0;
    final page = ids.skip(start).take(size).toList();
    return _ok({
      'documents': [
        for (final id in page) {'name': id, 'fields': docs[id]},
      ],
      if (start + size < ids.length) 'nextPageToken': '${start + size}',
    });
  }
}

void main() {
  group('FileStorage', () {
    late Directory dir;
    late FileStorage storage;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('kamubul_fs_');
      storage = FileStorage(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('anlık görüntü ve durum gidiş-dönüş', () async {
      expect(await storage.readSnapshot(), isNull);
      expect(await storage.readState(), isNull);
      await storage.writeSnapshot('{"a":"İş"}');
      await storage.writeState({
        'detailed': ['u'],
      });
      expect(await storage.readSnapshot(), '{"a":"İş"}');
      expect((await storage.readState())!['detailed'], ['u']);
    });

    test('cihaz kaydı: yaz, oku, listele, sil', () async {
      await storage.putDevice(deviceRecord());
      final read = (await storage.getDevice(deviceId))!;
      expect(read.registration.searches.single.name, 'Ankara');
      expect(await storage.devices().length, 1);
      await storage.deleteDevice(deviceId);
      expect(await storage.getDevice(deviceId), isNull);
    });

    test(
      'geçersiz kimlik yol geçişini engeller; bozuk kayıt atlanır',
      () async {
        expect(
          () => storage.getDevice('../../etc/passwd'),
          throwsArgumentError,
        );
        await storage.putDevice(deviceRecord());
        File('${dir.path}/devices/${'f' * 32}.json')
            .writeAsStringSync('{bozuk');
        expect(await storage.devices().length, 1);
        expect(await storage.getDevice('f' * 32), isNull);
      },
    );
  });

  group('FirestoreStorage', () {
    late FakeFirestore fake;
    late FirestoreStorage storage;
    setUp(() {
      fake = FakeFirestore();
      storage = FirestoreStorage(
        client: MockClient(fake.handle),
        projectId: 'p',
      );
    });

    test('küçük anlık görüntü tek parça, işaretçi en sonda', () async {
      await storage.writeSnapshot('{"x":1}');
      expect(await storage.readSnapshot(), '{"x":1}');
      expect(
        fake.docs.keys.where((k) => k.startsWith('snapshotParts/')),
        hasLength(1),
      );
    });

    test('büyük Türkçe anlık görüntü parçalanır, bütün okunur, eski parçalar silinir', () async {
      final big = 'İşçi ğüşiöç ' * 120000; // ~2.4 MB UTF-8
      await storage.writeSnapshot(big);
      final parts = fake.docs.keys
          .where((k) => k.startsWith('snapshotParts/'))
          .toList();
      expect(parts.length, greaterThan(3));
      for (final key in parts) {
        final value = (fake.docs[key]!['json'] as Map)['stringValue'] as String;
        expect(
          utf8.encode(value).length,
          lessThanOrEqualTo(kFirestoreChunkBytes),
        );
      }
      expect(await storage.readSnapshot(), big);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await storage.writeSnapshot('{"yeni":true}');
      expect(await storage.readSnapshot(), '{"yeni":true}');
      expect(
        fake.docs.keys.where((k) => k.startsWith('snapshotParts/')),
        hasLength(1),
      );
    });

    test('cihaz kaydı gidiş-dönüş, sayfalı listeleme ve silme', () async {
      for (var i = 0; i < 5; i++) {
        final id = i.toRadixString(16).padLeft(32, '0');
        await storage.putDevice(deviceRecord(id: id));
      }
      final all = await storage.devices().toList();
      expect(all, hasLength(5));
      expect(
        (await storage.getDevice('0' * 32))!.registration.fcmToken,
        isNotEmpty,
      );
      await storage.deleteDevice('0' * 32);
      expect(await storage.getDevice('0' * 32), isNull);
      expect(() => storage.getDevice('kötü'), throwsArgumentError);
    });

    test('sunucu hatası FirestoreException olur', () async {
      final broken = FirestoreStorage(
        client: MockClient((_) async => http.Response('hata', 500)),
        projectId: 'p',
      );
      await expectLater(
        broken.readSnapshot(),
        throwsA(isA<FirestoreException>()),
      );
    });

    test('durum kaydı gidiş-dönüş', () async {
      expect(await storage.readState(), isNull);
      await storage.writeState({
        'pendingPush': ['u1'],
      });
      expect((await storage.readState())!['pendingPush'], ['u1']);
    });
  });
}
