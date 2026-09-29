/// Firestore (REST) depolaması: Google öncelikli yol. Yalnızca dize alanları
/// kullanılır (`json`), böylece değer kodlaması küçük ve sınırlar öngörülebilir
/// kalır. Kimlik doğrulamalı bir `http.Client` enjekte edilir (Cloud Run'da
/// metadata sunucusu, başka yerde servis hesabı anahtarı); testte sahte
/// istemci kullanılır. Firestore güvenlik kuralları istemci erişimini kapatır
/// (`firestore.rules`); yalnızca bu sunucu hesabı okur/yazar.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kamubul_core/kamubul_core.dart';

import 'storage.dart';

/// Bir belge alanı 1 MiB sınırının altında kalsın diye parça başına bayt.
const int kFirestoreChunkBytes = 600 * 1024;

class FirestoreException implements Exception {
  const FirestoreException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'FirestoreException($status): $message';
}

class FirestoreStorage implements Storage {
  FirestoreStorage({
    required this._client,
    required String projectId,
    String host = 'https://firestore.googleapis.com',
  }) : _base = '$host/v1/projects/$projectId/databases/(default)/documents';

  final http.Client _client;
  final String _base;

  Uri _uri(String path, [Map<String, Object>? query]) =>
      Uri.parse('$_base/$path')
          .replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));

  Future<String?> _get(String path) async {
    final response = await _client.get(_uri(path));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw FirestoreException(response.statusCode, 'GET $path');
    }
    return _stringField(response.body);
  }

  String? _stringField(String body) {
    final json = jsonDecode(body);
    final fields = json is Map ? json['fields'] : null;
    final value = fields is Map ? fields['json'] : null;
    return value is Map && value['stringValue'] is String
        ? value['stringValue'] as String
        : null;
  }

  Future<void> _set(String path, String value, {DateTime? updatedAt}) async {
    final response = await _client.patch(
      Uri.parse('$_base/$path').replace(
        queryParameters: {
          'updateMask.fieldPaths': ['json', 'updatedAt'],
        },
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'json': {'stringValue': value},
          'updatedAt': {
            'integerValue':
                '${(updatedAt ?? DateTime.now()).millisecondsSinceEpoch}',
          },
        },
      }),
    );
    if (response.statusCode != 200) {
      throw FirestoreException(response.statusCode, 'PATCH $path');
    }
  }

  Future<void> _delete(String path) async {
    final response = await _client.delete(_uri(path));
    if (response.statusCode != 200 && response.statusCode != 404) {
      throw FirestoreException(response.statusCode, 'DELETE $path');
    }
  }

  // ------------------------------------------------------------- anlık görüntü

  @override
  Future<String?> readSnapshot() async {
    final metaRaw = await _get('meta/snapshot');
    if (metaRaw == null) return null;
    final meta = jsonDecode(metaRaw);
    if (meta is! Map) return null;
    final version = meta['version'];
    final parts = meta['parts'];
    if (version is! String || parts is! int || parts < 1 || parts > 100) {
      return null;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < parts; i++) {
      final part = await _get('snapshotParts/${version}_$i');
      if (part == null) return null;
      buffer.write(part);
    }
    return buffer.toString();
  }

  @override
  Future<void> writeSnapshot(String body) async {
    final previous = await _get('meta/snapshot');
    final version = '${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final chunks = _chunk(body);
    // Önce parçalar, en son işaretçi: okuyucu hiçbir zaman yarım görüntü görmez.
    for (var i = 0; i < chunks.length; i++) {
      await _set('snapshotParts/${version}_$i', chunks[i]);
    }
    await _set(
      'meta/snapshot',
      jsonEncode({'version': version, 'parts': chunks.length}),
    );
    if (previous != null) {
      try {
        final old = jsonDecode(previous);
        if (old is Map && old['version'] is String && old['parts'] is int) {
          for (var i = 0; i < (old['parts'] as int); i++) {
            await _delete('snapshotParts/${old['version']}_$i');
          }
        }
      } on FormatException {
        // Eski parça temizliği en iyi çabadır.
      }
    }
  }

  List<String> _chunk(String body) {
    final chunks = <String>[];
    final current = StringBuffer();
    var bytes = 0;
    for (final rune in body.runes) {
      final char = String.fromCharCode(rune);
      final size = utf8.encode(char).length;
      if (bytes + size > kFirestoreChunkBytes) {
        chunks.add(current.toString());
        current.clear();
        bytes = 0;
      }
      current.write(char);
      bytes += size;
    }
    chunks.add(current.toString());
    return chunks;
  }

  // -------------------------------------------------------------------- durum

  @override
  Future<Map<String, Object?>?> readState() async {
    final raw = await _get('meta/state');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeState(Map<String, Object?> state) =>
      _set('meta/state', jsonEncode(state));

  // ------------------------------------------------------------------ cihazlar

  @override
  Future<DeviceRecord?> getDevice(String id) async {
    if (!isValidDeviceId(id)) throw ArgumentError.value(id, 'id');
    final raw = await _get('devices/$id');
    if (raw == null) return null;
    try {
      return DeviceRecord.decode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> putDevice(DeviceRecord device) {
    if (!isValidDeviceId(device.id)) throw ArgumentError.value(device.id, 'id');
    return _set(
      'devices/${device.id}',
      device.encode(),
      updatedAt: device.updatedAt,
    );
  }

  @override
  Future<void> deleteDevice(String id) {
    if (!isValidDeviceId(id)) throw ArgumentError.value(id, 'id');
    return _delete('devices/$id');
  }

  @override
  Stream<DeviceRecord> devices() async* {
    String? token;
    do {
      final response = await _client.get(
        _uri('devices', {'pageSize': 300, 'pageToken': ?token}),
      );
      if (response.statusCode != 200) {
        throw FirestoreException(response.statusCode, 'LIST devices');
      }
      final json = jsonDecode(response.body);
      final docs = json is Map ? json['documents'] : null;
      if (docs is List) {
        for (final doc in docs) {
          final raw = doc is Map ? _stringField(jsonEncode(doc)) : null;
          if (raw == null) continue;
          try {
            yield DeviceRecord.decode(raw);
          } on FormatException {
            continue;
          }
        }
      }
      token = json is Map && json['nextPageToken'] is String
          ? json['nextPageToken'] as String
          : null;
    } while (token != null);
  }

  @override
  Future<void> close() async => _client.close();
}
