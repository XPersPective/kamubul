import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/subscription_check.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

class _Store implements StoreAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<bool> _proAfter(
  Future<Set<String>> Function() activeProducts, {
  bool cached = false,
  bool play = false,
}) async {
  final store = SettingsStore();
  if (cached) store.setBool(ProSettingsKeys.proLifetime, true);
  final pro = ProController(
    store: store,
    repository: PurchaseRepository(adapter: _Store()),
  )..load();
  await verifySubscription(
    pro,
    store,
    activeProducts: activeProducts,
    restorableProducts: {
      proMonthlyProductId,
      if (play) proLegacyLifetimeProductId,
    },
  );
  expect(
    store.getInt(ProSettingsKeys.proTempUntil) ?? 0,
    lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch),
  );
  final restored = pro.isPro;
  pro.dispose();
  return restored;
}

void main() {
  test(
    'verified monthly Pro restores after a reinstall on both platforms',
    () async {
      for (final play in [false, true]) {
        expect(
          await _proAfter(() async => {proMonthlyProductId}, play: play),
          isTrue,
        );
      }
    },
  );

  test('legacy lifetime Pro restores on Android only', () async {
    expect(
      await _proAfter(() async => {proLegacyLifetimeProductId}, play: true),
      isTrue,
    );
    expect(await _proAfter(() async => {proLegacyLifetimeProductId}), isFalse);
  });

  test(
    'verified absence or foreign products do not keep a stale purchase',
    () async {
      for (final play in [false, true]) {
        expect(
          await _proAfter(() async => {}, cached: true, play: play),
          isFalse,
        );
        expect(
          await _proAfter(() async => {'foreign'}, cached: true, play: play),
          isFalse,
        );
      }
    },
  );

  test(
    'store unavailability preserves the cache without granting new Pro',
    () async {
      Future<Set<String>> unavailable() async =>
          throw StateError('unavailable');
      expect(await _proAfter(unavailable, cached: true), isTrue);
      expect(await _proAfter(unavailable), isFalse);

      final store = SettingsStore()
        ..setBool(ProSettingsKeys.proLifetime, true);
      final pro = ProController(
        store: store,
        repository: PurchaseRepository(adapter: _Store()),
      )..load();
      expect(
        await verifySubscription(
          pro,
          store,
          activeProducts: unavailable,
          restorableProducts: const {proMonthlyProductId},
        ),
        isFalse,
      );
      expect(
        await verifySubscription(
          pro,
          store,
          activeProducts: () async => const {},
          restorableProducts: const {proMonthlyProductId},
        ),
        isTrue,
      );
      expect(pro.isPro, isFalse);
      pro.dispose();
    },
  );

  test('a stale empty startup query does not clear a new purchase', () async {
    final store = SettingsStore();
    final pro = ProController(
      store: store,
      repository: PurchaseRepository(adapter: _Store()),
    )..load();
    final response = Completer<Set<String>>();
    final check = verifySubscription(
      pro,
      store,
      activeProducts: () => response.future,
      restorableProducts: {proMonthlyProductId},
    );
    store.setBool(ProSettingsKeys.proLifetime, true);
    pro.load();
    response.complete({});
    await check;
    expect(pro.isPro, isTrue);
    pro.dispose();
  });
}
