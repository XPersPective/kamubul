import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/ad_consent.dart';

void main() {
  test('concurrent startup awaits consent and SDK exactly once', () async {
    final updated = Completer<void>();
    final calls = <String>[];
    final gate = AdConsentGate(
      update: () {
        calls.add('update');
        return updated.future;
      },
      showForm: () async => calls.add('form'),
      canRequest: () async {
        calls.add('allowed');
        return true;
      },
      tracking: () async => calls.add('att'),
      initializeSdk: () async => calls.add('sdk'),
    );
    final first = gate.initialize();
    final second = gate.initialize();
    expect(identical(first, second), isTrue);
    expect(calls, ['update']);
    updated.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await gate.initialize(), isTrue);
    expect(calls, ['update', 'form', 'allowed', 'att', 'sdk']);
  });

  test(
    'denial or form failure never initializes SDK; retry can recover',
    () async {
      var allowed = false;
      var formFails = true;
      var sdk = 0;
      final gate = AdConsentGate(
        update: () async {},
        showForm: () async {
          if (formFails) throw StateError('form');
        },
        canRequest: () async => allowed,
        tracking: () async {},
        initializeSdk: () async {
          sdk++;
        },
      );
      expect(await gate.initialize(), isFalse);
      formFails = false;
      expect(await gate.initialize(), isFalse);
      expect(sdk, 0);
      allowed = true;
      expect(await gate.initialize(), isTrue);
      expect(sdk, 1);
    },
  );

  test('stalled consent fails closed', () async {
    var sdk = false;
    final gate = AdConsentGate(
      update: () => Completer<void>().future,
      showForm: () async {},
      canRequest: () async => true,
      tracking: () async {},
      initializeSdk: () async {
        sdk = true;
      },
      timeout: const Duration(milliseconds: 1),
    );
    expect(await gate.initialize(), isFalse);
    expect(sdk, isFalse);
  });
}
