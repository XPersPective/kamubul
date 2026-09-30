/// Uygulamanın sunucu kataloğunu okuyan istemcisi.
///
/// ETag ile koşullu okur (304 → veri değişmedi), boyut ve süre sınırlıdır,
/// yalnızca https (test için yalnızca yerel adres) kabul eder. Başarısızlık
/// istisna fırlatır; çağıran yerel önbelleği korur ve gömülü yedek yola düşer.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'snapshot.dart';

class RemoteCatalogueException implements Exception {
  const RemoteCatalogueException(this.message);
  final String message;
  @override
  String toString() => 'RemoteCatalogueException: $message';
}

class RemoteFetchResult {
  const RemoteFetchResult({this.snapshot, this.etag}) : notModified = false;
  const RemoteFetchResult.notModified(this.etag)
    : snapshot = null,
      notModified = true;

  final CatalogueSnapshot? snapshot;
  final String? etag;
  final bool notModified;
}

class RemoteCatalogueClient {
  RemoteCatalogueClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 8 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    final scheme = baseUrl.scheme;
    final loopback =
        baseUrl.host == 'localhost' ||
        baseUrl.host == '127.0.0.1' ||
        baseUrl.host == '10.0.2.2';
    if (baseUrl.host.isEmpty ||
        !(scheme == 'https' || (scheme == 'http' && loopback))) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'https gerekir');
    }
  }

  final Uri baseUrl;
  final Duration timeout;
  final int maxBytes;
  final http.Client _client;
  final bool _ownsClient;

  Uri _uri(String path) => baseUrl.replace(
    path:
        '${baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path}$path',
  );

  Future<RemoteFetchResult> fetchListings({String? etag}) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            _uri('/v1/listings.json'),
            headers: {
              'Accept': 'application/json',
              if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
            },
          )
          .timeout(timeout);
    } on Exception catch (error) {
      throw RemoteCatalogueException('bağlantı kurulamadı: $error');
    }
    if (response.statusCode == 304) {
      return RemoteFetchResult.notModified(etag);
    }
    if (response.statusCode != 200) {
      throw RemoteCatalogueException('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > maxBytes) {
      throw const RemoteCatalogueException('yanıt çok büyük');
    }
    try {
      return RemoteFetchResult(
        snapshot: CatalogueSnapshot.decode(utf8.decode(response.bodyBytes)),
        etag: response.headers['etag'],
      );
    } on SnapshotFormatException catch (error) {
      throw RemoteCatalogueException(error.message);
    } on FormatException {
      throw const RemoteCatalogueException('UTF-8 okunamadı');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
