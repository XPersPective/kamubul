import 'dart:async';

import 'package:flutter/services.dart';
import 'package:napp_pro/napp_pro.dart';

import 'subscription_check.dart';

typedef EntitlementReader = Future<Set<String>> Function();

/// StoreKit verifies the signed transaction locally; no client receipt is trusted.
Future<Set<String>> readStoreKitEntitlements() async {
  const channel = MethodChannel('kamubul/storekit');
  final values = await channel.invokeListMethod<String>('activeProducts');
  if (values == null) throw StateError('storekit_unavailable');
  return values.toSet();
}

/// App-local guard around the shared lifetime-purchase adapter.
/// Unverified transactions stay unfinished for a later store delivery.
class VerifiedStoreAdapter implements StoreAdapter {
  VerifiedStoreAdapter({
    required this.delegate,
    required this.entitlements,
    this.restorableProducts = const {proMonthlyProductId},
  });

  final StoreAdapter delegate;
  final EntitlementReader entitlements;
  final Set<String> restorableProducts;
  bool _buying = false;
  Future<void>? _restoring;

  late final Stream<List<StorePurchaseUpdate>>
  _updates = delegate.updates.asyncMap((updates) async {
    final result = <StorePurchaseUpdate>[];
    for (final update in updates) {
      final purchase = update.purchase;
      if (purchase.status != StorePurchaseStatus.pending) _buying = false;
      if (purchase.status != StorePurchaseStatus.purchased) {
        result.add(
          StorePurchaseUpdate(
            purchase: purchase,
            // Pending/failed/cancelled transactions must not be finished.
            complete: () async {},
          ),
        );
        continue;
      }
      var verified = false;
      try {
        verified =
            restorableProducts.contains(purchase.productId) &&
            (await entitlements()).contains(purchase.productId);
      } on Object {
        // Connectivity/verification failures never grant or finish a purchase.
      }
      result.add(
        verified
            ? update
            : StorePurchaseUpdate(
                purchase: StorePurchase(
                  productId: purchase.productId,
                  status: StorePurchaseStatus.error,
                  error: 'purchase_verification_failed',
                ),
                complete: () async {},
              ),
      );
    }
    return result;
  }).asBroadcastStream();

  @override
  Stream<List<StorePurchaseUpdate>> get updates => _updates;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) =>
      delegate.queryProducts(ids.intersection({proMonthlyProductId}));

  @override
  Future<void> buy(StoreProduct product) async {
    if (product.id != proMonthlyProductId || _buying) {
      throw StateError('purchase_unavailable');
    }
    _buying = true;
    try {
      await delegate.buy(product);
    } on Object {
      _buying = false;
      rethrow;
    }
  }

  @override
  Future<void> restore() =>
      _restoring ??= delegate.restore().whenComplete(() => _restoring = null);
}
