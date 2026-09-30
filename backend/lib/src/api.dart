/// Arayüzsüz salt okunur API + anonim cihaz kaydı.
///
///   GET    /v1/listings.json   katalog anlık görüntüsü (ETag, önbelleğe alınabilir)
///   GET    /v1/sources.json    kaynak durumları
///   GET    /v1/health          canlılık + anlık görüntü yaşı
///   PUT    /v1/devices/{id}    bildirim aboneliğini kaydet/güncelle
///   DELETE /v1/devices/{id}    aboneliği sil
///
/// Cihaz kimliği (32 hex) ve gizli anahtar (64 hex, `Authorization: Bearer`)
/// cihazda rastgele üretilir; sunucu yalnızca gizli anahtarın SHA-256
/// özetini saklar. Hesap yoktur. Yazma uçları istemci başına hız sınırlıdır.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:shelf/shelf.dart';

import 'rate_limit.dart';
import 'storage.dart';

const int kMaxBodyBytes = 32 * 1024;

class ApiHandler {
  ApiHandler({
    required this.storage,
    required this.writeLimiter,
    DateTime Function()? clock,
    this.snapshotCacheTtl = const Duration(seconds: 60),
  }) : _clock = clock ?? DateTime.now;

  final Storage storage;
  final RateLimiter writeLimiter;
  final Duration snapshotCacheTtl;
  final DateTime Function() _clock;

  String? _cachedBody;
  String? _cachedEtag;
  DateTime? _cachedAt;

  Future<Response> call(Request request) async {
    try {
      final segments = request.url.pathSegments;
      if (segments.length == 2 && segments[0] == 'v1') {
        switch (segments[1]) {
          case 'listings.json':
            return _method(request, 'GET') ?? await _listings(request);
          case 'sources.json':
            return _method(request, 'GET') ?? await _sources();
          case 'health':
            return _method(request, 'GET') ?? await _health();
        }
      }
      if (segments.length == 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'devices') {
        final id = segments[2];
        if (request.method == 'PUT') {
          return await _putDevice(request, id);
        }
        if (request.method == 'DELETE') {
          return await _deleteDevice(request, id);
        }
        return _json(405, {'error': 'yöntem desteklenmiyor'});
      }
      return _json(404, {'error': 'bulunamadı'});
    } on Exception {
      // Ayrıntı sızdırılmaz; günlük çağıran tarafta tutulur.
      return _json(500, {'error': 'sunucu hatası'});
    }
  }

  Response? _method(Request request, String expected) =>
      request.method == expected ||
          (expected == 'GET' && request.method == 'HEAD')
      ? null
      : _json(405, {'error': 'yöntem desteklenmiyor'});

  Response _json(int status, Object body, {Map<String, String>? headers}) =>
      Response(
        status,
        body: jsonEncode(body),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-store',
          ...?headers,
        },
      );

  Future<String?> _snapshot() async {
    final now = _clock();
    if (_cachedBody != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < snapshotCacheTtl) {
      return _cachedBody;
    }
    final body = await storage.readSnapshot();
    if (body == null) return null;
    _cachedBody = body;
    _cachedEtag =
        '"${sha256.convert(utf8.encode(body)).toString().substring(0, 32)}"';
    _cachedAt = now;
    return body;
  }

  Future<Response> _listings(Request request) async {
    final body = await _snapshot();
    if (body == null) {
      return _json(503, {'error': 'katalog henüz yayınlanmadı'});
    }
    final etag = _cachedEtag!;
    final headers = {
      'ETag': etag,
      'Cache-Control': 'public, max-age=60, s-maxage=300',
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (request.headers['if-none-match'] == etag) {
      return Response(304, headers: headers);
    }
    return Response.ok(body, headers: headers);
  }

  Future<Response> _sources() async {
    final body = await _snapshot();
    if (body == null) {
      return _json(503, {'error': 'katalog henüz yayınlanmadı'});
    }
    final snapshot = CatalogueSnapshot.decode(body);
    return Response.ok(
      jsonEncode({
        'schema': kSnapshotSchema,
        'generatedAt': wallIso(snapshot.generatedAt),
        'sources': [for (final s in snapshot.sources) s.toJson()],
      }),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=60, s-maxage=300',
      },
    );
  }

  Future<Response> _health() async {
    final body = await _snapshot();
    if (body == null) return _json(200, {'ok': true, 'snapshot': false});
    final snapshot = CatalogueSnapshot.decode(body);
    final age = wallClock(_clock()).difference(snapshot.generatedAt);
    return _json(200, {
      'ok': true,
      'snapshot': true,
      'ageSeconds': age.inSeconds,
      'listings': snapshot.listings.length,
    });
  }

  // ----------------------------------------------------------------- cihazlar

  String? _bearer(Request request) {
    final header = request.headers['authorization'] ?? '';
    return header.startsWith('Bearer ') ? header.substring(7).trim() : null;
  }

  String _clientKey(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connection_info'];
    return info == null ? 'yerel' : '$info';
  }

  bool _matches(String secret, String expectedHash) {
    final actual = sha256.convert(utf8.encode(secret)).toString();
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<Response> _putDevice(Request request, String id) async {
    if (!writeLimiter.allow(_clientKey(request))) {
      return _json(429, {'error': 'çok fazla istek'});
    }
    final secret = _bearer(request);
    if (!isValidDeviceId(id) ||
        secret == null ||
        !isValidDeviceSecret(secret)) {
      return _json(400, {'error': 'kimlik veya anahtar biçimi geçersiz'});
    }
    final declared = int.tryParse(request.headers['content-length'] ?? '');
    if (declared != null && declared > kMaxBodyBytes) {
      return _json(413, {'error': 'gövde çok büyük'});
    }
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > kMaxBodyBytes) {
        return _json(413, {'error': 'gövde çok büyük'});
      }
    }
    final DeviceRegistration registration;
    try {
      registration = DeviceRegistration.parse(jsonDecode(utf8.decode(bytes)));
    } on RegistrationFormatException catch (error) {
      return _json(400, {'error': error.message});
    } on FormatException {
      return _json(400, {'error': 'JSON okunamadı'});
    }
    final now = _clock().toUtc();
    final existing = await storage.getDevice(id);
    if (existing != null) {
      if (!_matches(secret, existing.secretHash)) {
        return _json(403, {'error': 'yetkisiz'});
      }
      await storage.putDevice(
        existing.copyWith(registration: registration, updatedAt: now),
      );
      return _json(200, {'ok': true});
    }
    await storage.putDevice(
      DeviceRecord(
        id: id,
        secretHash: sha256.convert(utf8.encode(secret)).toString(),
        registration: registration,
        state: const DevicePushState(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return _json(201, {'ok': true});
  }

  Future<Response> _deleteDevice(Request request, String id) async {
    if (!writeLimiter.allow(_clientKey(request))) {
      return _json(429, {'error': 'çok fazla istek'});
    }
    final secret = _bearer(request);
    if (!isValidDeviceId(id) ||
        secret == null ||
        !isValidDeviceSecret(secret)) {
      return _json(400, {'error': 'kimlik veya anahtar biçimi geçersiz'});
    }
    final existing = await storage.getDevice(id);
    if (existing == null) return _json(200, {'ok': true});
    if (!_matches(secret, existing.secretHash)) {
      return _json(403, {'error': 'yetkisiz'});
    }
    await storage.deleteDevice(id);
    return _json(200, {'ok': true});
  }
}
