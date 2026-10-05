import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/dedupe.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('listingFingerprint', () {
    test('kariyer başlığında kurum öneki, kurum adı kısaltmaları ve Türkçe '
        'harfler normalize edilir', () {
      final a = listingFingerprint(
        title: 'Devlet Hava Meydanları İşletmesi Genel Müdürlüğü - Memur Alımı',
        sourceId: 'kariyerkapisi',
        deadline: DateTime(2026, 10, 12),
      );
      final b = listingFingerprint(
        title: 'DEVLET HAVA MEYDANLARI İŞLETMESİ',
        sourceId: 'kamuilan_sbb',
        deadline: DateTime(2026, 10, 12),
      );
      expect(a, b);
      expect(a, endsWith('|2026-10-12'));
    });

    test('son başvuru günü farklıysa parmak izi eşleşmez', () {
      final a = listingFingerprint(
        title: 'TEST KURUMU',
        sourceId: 'kamuilan_sbb',
        deadline: DateTime(2026, 10, 12),
      );
      final b = listingFingerprint(
        title: 'TEST KURUMU',
        sourceId: 'resmigazete',
        deadline: DateTime(2026, 10, 13),
      );
      expect(a, isNot(b));
    });

    test('kurum farklıysa parmak izi eşleşmez', () {
      final a = listingFingerprint(
        title: 'A KURUMU - Memur Alımı',
        sourceId: 'kariyerkapisi',
        deadline: DateTime(2026, 10, 12),
      );
      final b = listingFingerprint(
        title: 'B KURUMU - Memur Alımı',
        sourceId: 'kariyerkapisi',
        deadline: DateTime(2026, 10, 12),
      );
      expect(a, isNot(b));
    });

    test('tarih yoksa gün yongası "-" olur', () {
      final fp = listingFingerprint(
        title: 'TEST KURUMU',
        sourceId: 'resmigazete',
      );
      expect(fp, endsWith('|-'));
    });
  });

  group('ListingStore tekilleştirme', () {
    Future<ListingStore> freshStore() async {
      return ListingStore(
        database: await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            singleInstance: false,
            onCreate: ListingStore.createSchema,
          ),
        ),
      );
    }

    ListingRecord record({
      required String url,
      required String sourceId,
      required String title,
      DateTime? deadline,
    }) => ListingRecord(
      url: url,
      sourceId: sourceId,
      title: title,
      category: 'Personel',
      publishedAt: DateTime(2026, 9, 20),
      fetchedAt: DateTime(2026, 9, 27),
      deadline: deadline,
    );

    test('aynı kurum+son başvuru farklı native ilanları silmez', () async {
      final store = await freshStore();
      await store.mergeFeed([
        record(
          url: 'kariyer://1',
          sourceId: 'kariyerkapisi',
          title: 'TEST KURUMU - Memur Alımı',
          deadline: DateTime(2026, 10, 12),
        ),
      ]);
      await store.mergeFeed([
        record(
          url: 'sbb://2',
          sourceId: 'kamuilan_sbb',
          title: 'TEST KURUMU',
          deadline: DateTime(2026, 10, 12),
        ),
        record(
          url: 'sbb://3',
          sourceId: 'kamuilan_sbb',
          title: 'DİĞER KURUM',
          deadline: DateTime(2026, 10, 12),
        ),
      ]);
      final items = await store.allListings();
      expect(items.map((item) => item.url).toSet(), {
        'kariyer://1',
        'sbb://2',
        'sbb://3',
      });
      await store.close();
    });

    test('son başvuru günü farklıysa her iki kayıt da kalır', () async {
      final store = await freshStore();
      await store.mergeFeed([
        record(
          url: 'a',
          sourceId: 'kariyerkapisi',
          title: 'TEST KURUMU - Memur Alımı',
          deadline: DateTime(2026, 10, 12),
        ),
        record(
          url: 'b',
          sourceId: 'kamuilan_sbb',
          title: 'TEST KURUMU',
          deadline: DateTime(2026, 10, 13),
        ),
      ]);
      final items = await store.allListings();
      expect(items, hasLength(2));
      await store.close();
    });

    test('aynı URL yenilemede parmak izi kaybolsa da güncellenir', () async {
      final store = await freshStore();
      await store.mergeFeed([
        record(
          url: 'a',
          sourceId: 'kariyerkapisi',
          title: 'TEST KURUMU - Memur Alımı',
          deadline: DateTime(2026, 10, 12),
        ),
      ]);
      final db = await store.database;
      // Göç öncesi benzeri: parmak izi boş satır yenilemede dolar.
      await db.update(
        'listings',
        {'fingerprint': null},
        where: 'url = ?',
        whereArgs: ['a'],
      );
      await store.mergeFeed([
        record(
          url: 'a',
          sourceId: 'kariyerkapisi',
          title: 'TEST KURUMU - Memur Alımı',
          deadline: DateTime(2026, 10, 12),
        ),
      ]);
      final row = (await db.query(
        'listings',
        where: 'url = ?',
        whereArgs: ['a'],
      )).single;
      expect(row['fingerprint'], isNotNull);
      await store.close();
    });
  });
}
