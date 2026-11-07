import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/subscription_check.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

class _Store implements StoreAdapter {
  _Store({this.owned, this.fail = false});
  final String? owned;
  final bool fail;
  final _updates = StreamController<List<StorePurchaseUpdate>>.broadcast();

  @override
  Stream<List<StorePurchaseUpdate>> get updates => _updates.stream;

  @override
  Future<void> restore() async {
    if (fail) throw StateError('Play yok');
    if (owned != null) {
      _updates.add([
        StorePurchaseUpdate(
          purchase: StorePurchase(
            productId: owned!,
            status: StorePurchaseStatus.purchased,
          ),
          complete: () async {},
        ),
      ]);
    }
  }

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => const [];

  @override
  Future<void> buy(StoreProduct product) async {}
}

Future<bool> _proAfter(
  _Store adapter, {
  Future<Set<String>> Function()? activeProducts,
}) async {
  final store = SettingsStore()..setBool(ProSettingsKeys.proLifetime, true);
  final pro = ProController(
    store: store,
    repository: PurchaseRepository(adapter: adapter),
  )..load();
  await verifySubscription(
    pro,
    adapter,
    store,
    settle: Duration.zero,
    activeProducts: activeProducts,
  );
  return pro.isPro;
}

void main() {
  test('StoreKit verified entitlement controls cached monthly Pro', () async {
    expect(
      await _proAfter(
        _Store(),
        activeProducts: () async => {proMonthlyProductId},
      ),
      isTrue,
    );
    expect(await _proAfter(_Store(), activeProducts: () async => {}), isFalse);
    expect(
      await _proAfter(_Store(), activeProducts: () async => {'foreign'}),
      isFalse,
    );
    expect(
      await _proAfter(
        _Store(),
        activeProducts: () async => throw StateError('unavailable'),
      ),
      isTrue,
    );
  });
  test('unrelated restored product never preserves Pro', () async {
    expect(await _proAfter(_Store(owned: 'foreign')), isFalse);
  });
  test('aktif aylık abonelik Pro\'yu korur', () async {
    expect(await _proAfter(_Store(owned: proMonthlyProductId)), isTrue);
  });
  test('eski ömür boyu satın alma Pro\'yu korur', () async {
    expect(await _proAfter(_Store(owned: 'kamubul_pro_lifetime')), isTrue);
  });
  test('biten abonelik Pro\'yu düşürür', () async {
    expect(await _proAfter(_Store()), isFalse);
  });
  test('mağazaya ulaşılamazsa önbellek korunur', () async {
    expect(await _proAfter(_Store(fail: true)), isTrue);
  });
}
