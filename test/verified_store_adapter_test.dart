import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/subscription_check.dart';
import 'package:kamubul/data/verified_store_adapter.dart';
import 'package:napp_pro/napp_pro.dart';

class _Store implements StoreAdapter {
  final events = StreamController<List<StorePurchaseUpdate>>.broadcast();
  int buys = 0, finishes = 0;
  @override
  Stream<List<StorePurchaseUpdate>> get updates => events.stream;
  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => [];
  @override
  Future<void> buy(StoreProduct product) async {
    buys++;
  }

  @override
  Future<void> restore() async {}
  void emit(StorePurchaseStatus status, {String id = proMonthlyProductId}) {
    events.add([
      StorePurchaseUpdate(
        purchase: StorePurchase(productId: id, status: status),
        complete: () async {
          finishes++;
        },
      ),
    ]);
  }
}

void main() {
  test(
    'only verified active monthly transactions are granted and finished',
    () async {
      for (final valid in [true, false]) {
        final store = _Store();
        final adapter = VerifiedStoreAdapter(
          delegate: store,
          entitlements: () async => valid ? {proMonthlyProductId} : {},
        );
        final next = adapter.updates.first;
        store.emit(StorePurchaseStatus.purchased);
        final update = (await next).single;
        expect(
          update.purchase.status,
          valid ? StorePurchaseStatus.purchased : StorePurchaseStatus.error,
        );
        await update.complete();
        expect(store.finishes, valid ? 1 : 0);
        await store.events.close();
      }
    },
  );

  test(
    'verification outage and foreign product never unlock or finish',
    () async {
      for (final foreign in [true, false]) {
        final store = _Store();
        final adapter = VerifiedStoreAdapter(
          delegate: store,
          entitlements: () async {
            if (!foreign) throw StateError('offline');
            return {'foreign'};
          },
        );
        final next = adapter.updates.first;
        store.emit(
          StorePurchaseStatus.purchased,
          id: foreign ? 'foreign' : proMonthlyProductId,
        );
        final update = (await next).single;
        expect(update.purchase.status, StorePurchaseStatus.error);
        await update.complete();
        expect(store.finishes, 0);
        await store.events.close();
      }
    },
  );

  test(
    'pending, cancellation and errors stay distinct; duplicate buy is blocked',
    () async {
      final store = _Store();
      final adapter = VerifiedStoreAdapter(
        delegate: store,
        entitlements: () async => {},
      );
      final observed = <StorePurchaseStatus>[];
      final sub = adapter.updates.listen((updates) async {
        observed.add(updates.single.purchase.status);
        await updates.single.complete();
      });
      const product = StoreProduct(id: proMonthlyProductId, price: '₺58,99');
      await adapter.buy(product);
      await expectLater(adapter.buy(product), throwsStateError);
      for (final status in [
        StorePurchaseStatus.pending,
        StorePurchaseStatus.canceled,
        StorePurchaseStatus.error,
      ]) {
        store.emit(status);
        await Future<void>.delayed(Duration.zero);
      }
      expect(observed, [
        StorePurchaseStatus.pending,
        StorePurchaseStatus.canceled,
        StorePurchaseStatus.error,
      ]);
      expect(store.finishes, 0);
      await adapter.buy(product);
      expect(store.buys, 2);
      await sub.cancel();
      await store.events.close();
    },
  );
}
