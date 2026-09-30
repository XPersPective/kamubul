/// Kaynak satırlarını ortak [ListingRecord] biçimine çevirir; uygulama ve
/// sunucu aynı eşlemeyi kullanır.
library;

import '../data/listing_models.dart';
import 'kariyer_feed.dart';
import 'sbb_feed.dart';

const String kKariyerSourceId = 'kariyerkapisi';
const String kSbbSourceId = 'kamuilan_sbb';

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
