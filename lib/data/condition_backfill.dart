import 'package:kamubul_core/kamubul_core.dart';

import 'listing_store.dart';

/// Şartları henüz ayıklanmamış ilanların resmî metnini sırayla okuyup kural
/// tabanlı çıkarıcıyı uygular (PB-025, ADR-005 1. katman). Nazik: tur başına
/// en çok [limit] ilan, istekler arasında [gap]; bir kaynak hata verirse tur
/// biter, ilan sonraki turda yeniden denenir. Dönen değer işlenen ilan sayısı.
Future<int> backfillConditions(
  ListingStore store, {
  int limit = 12,
  Duration gap = const Duration(milliseconds: 1500),
  DateTime? now,
  Future<String?> Function(ListingRecord record)? readText,
}) async {
  final pending = await store.uncheckedConditions(
    now: now ?? DateTime.now(),
    limit: limit,
  );
  var done = 0;
  for (final record in pending) {
    final String? text;
    try {
      text = await (readText ?? (r) => listingConditionText(store, r))(record);
    } on Exception {
      break; // kaynak erişilemiyor: sonraki turda yeniden denenir
    }
    // Metni olmayan kaynak (ör. SBB PDF) yine işaretlenir; boşuna denenmez.
    await store.applyConditions(
      record.url,
      text == null ? const ConditionFields() : extractConditions(text),
      at: now,
    );
    done++;
    if (gap > Duration.zero) await Future<void>.delayed(gap);
  }
  return done;
}

/// Kaynağa göre ilanın şart metni; okunamayan kaynakta null.
Future<String?> listingConditionText(
  ListingStore store,
  ListingRecord record,
) async {
  final url = Uri.tryParse(record.url);
  if (url == null) return null;
  switch (record.sourceId) {
    case kKariyerSourceId:
      final detail = await loadKariyerDetail(url);
      await store.applyDetail(
        record.url,
        deadline: detail.deadline,
        quota: detail.quota > 0 ? detail.quota : null,
        places: detail.places,
      );
      return [
        detail.body,
        for (final position in detail.positions) position.conditions,
      ].join('\n');
    case kIlanGovSourceId:
      final id = url.pathSegments.elementAtOrNull(1);
      return id == null ? null : loadIlanGovDetailText(id);
    case kIskurSourceId:
      final id = url.queryParameters['uiID'];
      return id == null ? null : loadIskurDetailText(id);
    default:
      return null;
  }
}
