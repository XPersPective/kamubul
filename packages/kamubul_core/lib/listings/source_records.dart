/// Kaynak satırlarını ortak [ListingRecord] biçimine çevirir; uygulama ve
/// sunucu aynı eşlemeyi kullanır.
library;

import '../data/listing_models.dart';
import 'ilangov_feed.dart';
import 'iskur_feed.dart';
import 'kariyer_feed.dart';
import 'sbb_feed.dart';

const String kKariyerSourceId = 'kariyerkapisi';
const String kSbbSourceId = 'kamuilan_sbb';
const String kIlanGovSourceId = 'ilangov';
const String kIskurSourceId = 'iskur';

ListingRecord kariyerRecord(PublicListing item, DateTime now) => ListingRecord(
  url: item.url.toString(),
  sourceId: kKariyerSourceId,
  title: item.title,
  category: item.category,
  publishedAt: item.publishedAt,
  deadline: item.deadline,
  fetchedAt: now,
);

ListingRecord sbbRecord(SbbListing item, DateTime now) => ListingRecord(
  url: item.url.toString(),
  sourceId: kSbbSourceId,
  title: '${item.institution} — ${item.title}',
  category: item.category,
  // SBB satırı yayın tarihi vermez; satırdaki tek tarih başvuru penceresidir,
  // yayın tarihi gibi sunulmamalıdır.
  publishedAt: null,
  deadline: item.deadline,
  quota: item.quota,
  fetchedAt: now,
);

ListingRecord ilanGovRecord(IlanGovListing item, DateTime now) => ListingRecord(
  url: item.url.toString(),
  sourceId: kIlanGovSourceId,
  // Kurum adı başlıkta: "Belediye" süzgeci belediye ilanlarını böyle bulur.
  title: '${item.institution} — ${item.title}',
  category: item.category,
  publishedAt: item.publishedAt,
  // Son başvuru yapılandırılmış alan değil; metinden tahmin edilmez.
  deadline: null,
  places: [?item.city],
  fetchedAt: now,
);

/// Yalnız kamu işçi alımı (özel sektör İŞKUR ilanları kapsam dışı).
ListingRecord iskurRecord(IskurListing item, DateTime now) => ListingRecord(
  url: item.url.toString(),
  sourceId: kIskurSourceId,
  title: '${item.institution} - ${item.occupation}',
  category: 'İşçi${item.period.isEmpty ? '' : ' (${item.period})'}',
  // Listede yayın tarihi yok; tahmin edilmez.
  publishedAt: null,
  deadline: item.deadline,
  quota: item.quota,
  places: [?item.city],
  fetchedAt: now,
);
