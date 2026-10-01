import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/notifications/secure_push_store.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native secure store round-trip, reopen and plaintext migration',
    (_) async {
      const channel = MethodChannel('kamubul/secure_push');
      final previous = await channel.invokeMethod<String>('read');
      try {
        await channel.invokeMethod<void>('write', '{}');
        final store = await SecurePushStore.load(SettingsStore());
        await store.write({
          'kamubul.push.id': 'local-check-id',
          'kamubul.push.secret': 'local-check-secret',
        });
        final reopened = await SecurePushStore.load(SettingsStore());
        expect(reopened.read('kamubul.push.id'), 'local-check-id');
        expect(reopened.read('kamubul.push.secret'), 'local-check-secret');
        await channel.invokeMethod<void>(
          'write',
          jsonEncode({'kamubul.push.enabled': '1'}),
        );
        final settings = SettingsStore()
          ..setString('kamubul.push.secret', 'obsolete-plaintext');
        final authoritative = await SecurePushStore.load(settings);
        expect(authoritative.read('kamubul.push.secret'), isNull);
        expect(authoritative.read('kamubul.push.enabled'), '1');
        expect(settings.getString('kamubul.push.secret'), isNull);
      } finally {
        // Local-only probe restores prior state; no Firebase, API or real device registry.
        await channel.invokeMethod<void>('write', previous ?? '{}');
      }
    },
  );
}
