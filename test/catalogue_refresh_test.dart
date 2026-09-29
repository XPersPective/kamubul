import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/catalogue_refresh.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/listings/kariyer_feed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('arka planla paylaşılan yenileme son tarihi işler ve hata halinde önbelleği korur', () async {
    final store = ListingStore(
      database: await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onCreate: ListingStore.createSchema,
        ),
      ),
    );
    final url = Uri.parse(
      'https://kariyerkapisi.gov.tr/IlanDetay?i=27cf966f-b2b9-4671-a21a-731cb060436a',
    );
    final at = DateTime(2026, 9, 28);
    final first = await refreshCatalogue(
      store,
      at: at,
      kariyer: () async => [
        PublicListing(
          title: '29 kişi alımı',
          category: 'Personel',
          url: url,
          publishedAt: DateTime(2026, 9, 14),
          deadline: DateTime(2026, 9, 29, 13),
        ),
      ],
      sbb: () async => [],
    );
    expect(first.failedSources, isEmpty);
    expect(
      (await store.allListings()).single.deadline,
      DateTime(2026, 9, 29, 13),
    );
    await store.setSaved(url.toString(), true);

    final failed = await refreshCatalogue(
      store,
      at: at.add(const Duration(days: 90)),
      kariyer: () async => throw const FormatException('kaynak kapalı'),
      sbb: () async => throw const FormatException('kaynak kapalı'),
    );
    expect(failed.failedSources, hasLength(2));
    final cached = (await store.allListings()).single;
    expect(cached.saved, isTrue);
    expect(cached.deadline, DateTime(2026, 9, 29, 13));
    await store.close();
  });
}
