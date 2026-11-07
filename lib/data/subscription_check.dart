import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

/// Pro aylık aboneliktir (PB-026). napp_pro yalnız "satın alındı" işaretini
/// bilir; abonelik bitince işareti burada düşürürüz.
const proMonthlyProductId = 'kamubul_pro_monthly';

/// Açılışta mağazadan geri yükleme ister. Mağaza yanıt verir ama aktif
/// abonelik (ya da eski ömür boyu satın alma) gelmezse Pro kaldırılır.
/// Mağazaya ulaşılamazsa (çevrimdışı/Play yok) önbellekteki durum korunur.
// ponytail: istemci tarafı kontrol; sunucu doğrulaması (Play Developer API)
// PB-024'te ayrı madde.
Future<void> verifySubscription(
  ProController pro,
  StoreAdapter adapter,
  SettingsStore store, {
  Duration settle = const Duration(seconds: 4),
  Future<Set<String>> Function()? activeProducts,
}) async {
  if (!pro.hasLifetimePurchase) return;
  final owned = <String>{};
  if (activeProducts != null) {
    try {
      owned.addAll(await activeProducts());
    } on Object {
      return; // StoreKit unavailable: preserve the previous offline entitlement.
    }
    if (owned.contains(proMonthlyProductId)) return;
    _removePurchasedPro(pro, store);
    return;
  }
  final sub = adapter.updates.listen((updates) {
    for (final update in updates) {
      if (update.purchase.status == StorePurchaseStatus.purchased) {
        owned.add(update.purchase.productId);
      }
    }
  });
  try {
    await adapter.restore();
    // Geri yüklenen satın almalar akışa future'dan sonra da düşebilir.
    await Future<void>.delayed(settle);
  } on Object {
    return;
  } finally {
    await sub.cancel();
  }
  if (owned.contains(proMonthlyProductId) ||
      owned.contains('kamubul_pro_lifetime')) {
    return;
  }
  _removePurchasedPro(pro, store);
}

void _removePurchasedPro(ProController pro, SettingsStore store) {
  store.setBool(ProSettingsKeys.proLifetime, false);
  pro.load();
  // Yalnız dinleyicileri (reklam politikası, ekranlar) uyandırır; süre eklemez.
  pro.grantTemporaryPro(Duration.zero);
}
