/// PB-007 politika haritası: hangi alanlar yapılandırılmış gösterilir.
///
/// `false` olan alan doğrulanamamış demektir; arayüz o alanda ham metin
/// gösterir (kaynak cümle / "belirtilmemiş"), tek değer iddia etmez.
/// Kapı testi (`test/extraction_eval_test.dart`) politikası AÇIK her alanın
/// precision'ını [kExtractionPrecisionBar] üstünde tutar: ya çıkarıcı
/// düzeltilir ya da politika kapatılır.
library;

import 'extract_conditions.dart';

/// "Hatasız" çubuğu: yanlış bilgiye tahammül yok denecek kadar az.
const double kExtractionPrecisionBar = 0.95;

/// Alan adı -> yapılandırılmış gösterim açık mı?
const Map<String, bool> kExtractionPolicy = {
  // Kariyer Kapısı şart alanları (alıntılı serbest metin çıkarımı)
  'kpssType': true,
  'kpssScore': true,
  'maxAge': true,
  'education': true,
  'quotaType': true,
  // SBB liste alanları (yapılandırılmış satır ayrıştırma)
  'institution': true,
  'title': true,
  'category': true,
  'start': true,
  'deadline': true,
  'quota': true,
};

/// Politikası kapalı alanları çıkarımdan düşürür; arayüz ve yerel kayıt
/// yalnızca politikası açık alanların tek değerini iddia eder, kapalı alan
/// ham metinle ("belirtilmemiş") gösterilir.
///
/// [policy] yalnızca test içindir; üretimde [kExtractionPolicy] kullanılır.
ConditionFields applyExtractionPolicy(
  ConditionFields fields, {
  Map<String, bool> policy = kExtractionPolicy,
}) {
  bool enabled(String name) => policy[name] ?? false;
  return ConditionFields(
    kpssType: enabled('kpssType') ? fields.kpssType : null,
    kpssScore: enabled('kpssScore') ? fields.kpssScore : null,
    maxAge: enabled('maxAge') ? fields.maxAge : null,
    education: enabled('education') ? fields.education : null,
    quotaType: enabled('quotaType') ? fields.quotaType : null,
  );
}
