import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

const proMonthlyProductId = 'kamubul_pro_monthly';
const proLegacyLifetimeProductId = 'kamubul_pro_lifetime';

/// Açılışta ilk kurulum dahil geçerli mağaza haklarını eşitler.
/// Mağazaya ulaşılamazsa önceki yerel durum korunur.
Future<void> verifySubscription(
  ProController pro,
  SettingsStore store, {
  required Future<Set<String>> Function() activeProducts,
  required Set<String> restorableProducts,
}) async {
  final hadPaidPro = pro.hasLifetimePurchase;
  final bool ownsPro;
  try {
    final owned = await activeProducts().timeout(const Duration(seconds: 5));
    ownsPro = owned.any(restorableProducts.contains);
  } on Object {
    return;
  }
  // A purchase may have completed while the initial store query was pending.
  if (!ownsPro && !hadPaidPro) return;
  if (ownsPro == pro.hasLifetimePurchase) return;

  store.setBool(ProSettingsKeys.proLifetime, ownsPro);
  pro.load();
  // Dinleyicileri (reklam politikası, ekranlar) uyandırır; süre eklemez.
  pro.grantTemporaryPro(Duration.zero);
}
