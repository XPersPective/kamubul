import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/notifications/secure_push_store.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kamubul/secure_push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? stored;
  Future<void> Function(String)? beforeWrite;

  setUp(() {
    stored = null;
    beforeWrite = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') return stored;
      final value = call.arguments as String;
      await beforeWrite?.call(value);
      stored = value;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('migration persists complete identity before deleting plaintext preferences', () async {
    final settings = SettingsStore()
      ..setString('kamubul.push.id', 'old-id')
      ..setString('kamubul.push.secret', 'old-secret');
    beforeWrite = (value) async {
      expect(settings.getString('kamubul.push.secret'), 'old-secret');
      expect(jsonDecode(value), {
        'kamubul.push.id': 'old-id',
        'kamubul.push.secret': 'old-secret',
      });
    };
    final store = await SecurePushStore.load(settings);
    expect(store.read('kamubul.push.id'), 'old-id');
    expect(settings.getString('kamubul.push.secret'), isNull);
    expect(settings.getString('kamubul.push.id'), isNull);
    beforeWrite = null;
    final reopened = await SecurePushStore.load(settings);
    expect(reopened.read('kamubul.push.secret'), 'old-secret');
  });

  test(
    'failed migration retains the existing plaintext identity for retry',
    () async {
      final settings = SettingsStore()
        ..setString('kamubul.push.secret', 'preserve');
      beforeWrite = (_) async => throw PlatformException(code: 'locked');
      await expectLater(
        SecurePushStore.load(settings),
        throwsA(isA<PlatformException>()),
      );
      expect(settings.getString('kamubul.push.secret'), 'preserve');
      expect(stored, isNull);
    },
  );

  test(
    'writes are serialized and visible only after durable acknowledgement',
    () async {
      final store = await SecurePushStore.load(SettingsStore()),
          gate = Completer<void>();
      beforeWrite = (_) => gate.future;
      final first = store.write({
        'kamubul.push.id': 'identity',
        'kamubul.push.secret': 'secret',
      });
      final second = store.write({'kamubul.push.enabled': '1'});
      await Future<void>.delayed(Duration.zero);
      expect(store.read('kamubul.push.id'), isNull);
      gate.complete();
      await first;
      await second;
      expect(jsonDecode(stored!), {
        'kamubul.push.id': 'identity',
        'kamubul.push.secret': 'secret',
        'kamubul.push.enabled': '1',
      });
    },
  );

  test(
    'failed write preserves durable state and later writes can recover',
    () async {
      final store = await SecurePushStore.load(SettingsStore());
      await store.write({'kamubul.push.id': 'old'});
      beforeWrite = (_) async => throw PlatformException(code: 'storage_full');
      await expectLater(
        store.write({'kamubul.push.id': 'lost'}),
        throwsA(isA<PlatformException>()),
      );
      expect(store.read('kamubul.push.id'), 'old');
      beforeWrite = null;
      await store.write({'kamubul.push.enabled': '1'});
      expect(jsonDecode(stored!)['kamubul.push.id'], 'old');
    },
  );

  test(
    'corrupt or oversized native state is rejected without erasing legacy data',
    () async {
      final settings = SettingsStore()
        ..setString('kamubul.push.secret', 'preserve');
      for (final value in [
        'not json',
        '{"unexpected":"value"}',
        '{"kamubul.push.id":false}',
        'a' * 131073,
      ]) {
        stored = value;
        await expectLater(
          SecurePushStore.load(settings),
          throwsA(isA<FormatException>()),
        );
        expect(settings.getString('kamubul.push.secret'), 'preserve');
      }
    },
  );
}
