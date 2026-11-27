import 'dart:async';

import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

const proMonthlyProductId = 'kamubul_pro_monthly';
const proLegacyLifetimeProductId = 'kamubul_pro_lifetime';

/// Açılışta ve ön plana dönüşte geçerli mağaza haklarını eşitler.
/// Mağazadan yetkili yanıt alındıysa `true`, mağazaya ulaşılamadıysa önceki
/// yerel durumu koruyarak `false` döner.
Future<bool> verifySubscription(
  ProController pro,
  SettingsStore store, {
  required Future<Set<String>> Function() activeProducts,
  required Set<String> restorableProducts,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final hadPaidPro = pro.hasLifetimePurchase;
  final bool ownsPro;
  try {
    final owned = await activeProducts().timeout(timeout);
    ownsPro = owned.any(restorableProducts.contains);
  } on Object {
    return false;
  }
  // A purchase may have completed while the store query was pending.
  if (!ownsPro && !hadPaidPro) return true;
  if (ownsPro == pro.hasLifetimePurchase) return true;

  store.setBool(ProSettingsKeys.proLifetime, ownsPro);
  pro.load();
  // Dinleyicileri (reklam politikası, ekranlar) uyandırır; süre eklemez.
  pro.grantTemporaryPro(Duration.zero);
  unawaited(store.flush().catchError((Object _) {}));
  return true;
}
