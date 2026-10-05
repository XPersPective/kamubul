import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/catalogue_refresh.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'sunucu hatası önbelleği ve favoriyi korur; resmî kaynak çağrısı yok',
    () async {
      final store = ListingStore(
        database: await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            onCreate: ListingStore.createSchema,
            version: 11,
          ),
        ),
      );
      addTearDown(store.close);
      final at = DateTime(2026, 10, 5);
      final requests = <Uri>[];
      var unavailable = false;
      final remote = RemoteCatalogueClient(
        baseUrl: Uri.parse('https://api.example.com'),
        client: MockClient((request) async {
          requests.add(request.url);
          if (unavailable) return http.Response('', 503);
          if (request.url.path == '/api/v2/meta') {
            return http.Response(
              jsonEncode({
                'schemaVersion': 2,
                'taxonomyVersion': 1,
                'latestSeq': 1,
                'oldestRetainedSeq': 1,
                'sources': [],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'watermark': 1,
              'next': null,
              'items': [
                {
                  'id': 'kariyer:1',
                  'revision': 1,
                  'url': 'https://kariyerkapisi.gov.tr/IlanDetay?i=1',
                  'sourceId': 'kariyerkapisi',
                  'title': 'Memur alımı',
                  'category': 'Personel',
                  'updatedAt': '2026-10-05T00:00:00Z',
                  'text': 'Başvuru şartları ve özgün metin.',
                  'requirementGroups': [],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final first = await refreshCatalogue(store, remote: remote, at: at);
      expect(first.remoteFailed, false);
      final cached = (await store.allListings()).single;
      await store.setSaved(cached.url, true);
      unavailable = true;
      final failed = await refreshCatalogue(
        store,
        remote: remote,
        at: at.add(const Duration(days: 1)),
      );
      expect(failed.remoteFailed, true);
      expect(failed.remoteLastSuccess, at);
      expect((await store.allListings()).single.saved, true);
      expect(
        (await store.allListings()).single.noticeText,
        'Başvuru şartları ve özgün metin.',
      );
      expect(requests.map((uri) => uri.host).toSet(), {'api.example.com'});
      expect(requests.map((uri) => uri.path), [
        '/api/v2/meta',
        '/api/v2/listings',
        '/api/v2/meta',
      ]);
    },
  );
}
