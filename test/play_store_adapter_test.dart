import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:kamubul/data/play_store_adapter.dart';
import 'package:kamubul/data/subscription_check.dart';
import 'package:napp_pro/napp_pro.dart';

final class _PlayBilling implements InAppPurchase {
  bool canLaunch = false;
  final requests = <PurchaseParam>[];
  final offer = ProductDetails(
    id: proMonthlyProductId,
    title: 'KamuBul Pro',
    description: 'Monthly',
    price: '₺58,99',
    rawPrice: 58.99,
    currencyCode: 'TRY',
  );

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: ids.contains(offer.id) ? [offer] : [],
        notFoundIDs: ids.where((id) => id != offer.id).toList(),
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    requests.add(purchaseParam);
    return canLaunch;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a declined launch surfaces the error and allows a retry', () async {
    final plugin = _PlayBilling();
    final adapter = PlayStoreAdapter(plugin: plugin);
    const product = StoreProduct(id: proMonthlyProductId, price: '₺58,99');
    await expectLater(adapter.buy(product), throwsStateError);
    plugin.canLaunch = true;
    await adapter.buy(product);
    expect(plugin.requests, hasLength(2));
    expect(plugin.requests.last.productDetails, same(plugin.offer));
  });

  test('a missing product cannot launch Play Billing', () async {
    final plugin = _PlayBilling();
    final adapter = PlayStoreAdapter(plugin: plugin);
    await expectLater(
      adapter.buy(const StoreProduct(id: 'missing', price: '₺0,00')),
      throwsStateError,
    );
    expect(plugin.requests, isEmpty);
  });
}
