import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:napp_pro/napp_pro.dart';

/// Reuse the shared store behavior while surfacing a declined Play checkout.
final class PlayStoreAdapter implements StoreAdapter {
  PlayStoreAdapter({InAppPurchase? plugin})
    : _plugin = plugin ?? InAppPurchase.instance {
    _delegate = InAppPurchaseAdapter(plugin: _plugin);
  }

  final InAppPurchase _plugin;
  late final InAppPurchaseAdapter _delegate;

  @override
  Stream<List<StorePurchaseUpdate>> get updates => _delegate.updates;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) =>
      _delegate.queryProducts(ids);

  @override
  Future<void> buy(StoreProduct product) async {
    final response = await _plugin.queryProductDetails({product.id});
    final details = response.productDetails
        .where((item) => item.id == product.id)
        .firstOrNull;
    if (details == null) throw StateError('purchase_unavailable');

    // Keep the native Play ProductDetails so Billing receives its offer token.
    final started = await _plugin.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
    if (!started) throw StateError('purchase_not_started');
  }

  @override
  Future<void> restore() => _delegate.restore();

  Future<Set<String>> activeProductIds() async {
    final play = _plugin
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final purchases = await play.queryPastPurchases();
    if (purchases.error != null) throw StateError('play_purchases_unavailable');

    // Query directly: the generic restore callback marks every item restored.
    return purchases.pastPurchases
        .where((purchase) => purchase.status == PurchaseStatus.purchased)
        .map((purchase) => purchase.productID)
        .toSet();
  }
}
