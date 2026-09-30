/// Çıkarılan şart alanlarını ilan kaydına işler (uygulama ve sunucu aynı yolu
/// kullanır). Politikası kapalı ya da alıntısı olmayan alan yazılmaz; alan
/// "belirtilmemiş" kalır.
library;

import '../data/listing_models.dart';
import 'extract_conditions.dart';
import 'extraction_policy.dart';

ListingRecord applyConditionFields(
  ListingRecord record,
  ConditionFields fields,
) {
  final claimed = applyExtractionPolicy(fields);
  return record.copyWith(
    kpss: claimed.kpssType?.value,
    kpssQuote: claimed.kpssType?.quote,
    education: claimed.education?.value,
    educationQuote: claimed.education?.quote,
    maxAge: claimed.maxAge?.value,
    maxAgeQuote: claimed.maxAge?.quote,
    quotaType: claimed.quotaType?.value,
    quotaTypeQuote: claimed.quotaType?.quote,
  );
}
