import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/notifications/alert_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native reminder persistence, validation, replacement and cancellation',
    (tester) async {
      const channel = MethodChannel('kamubul/reminders');
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('SA015 cihaz kontrolü'))),
      );
      // Dedicated KamuBul QA emulator only; grant notification permission before running.
      final now = DateTime.now().millisecondsSinceEpoch;
      Map<String, Object> plan(int expires) => {
        'url': 'https://www.ilan.gov.tr/ilan/sa015-device-test',
        'title': 'SA015 cihaz testi — üretim ilanı değildir',
        'at': now + 3000,
        'expires': expires,
      };
      addTearDown(
        () =>
            channel.invokeMethod<bool>('sync', {'enabled': false, 'plans': []}),
      );
      expect(
        await channel.invokeMethod<bool>('sync', {
          'enabled': false,
          'plans': [],
        }),
        isFalse,
      );
      expect(await deadlineRemindersEnabled(), isFalse);
      final initial = plan(now + 86400000);
      expect(
        await channel.invokeMethod<bool>('sync', {
          'enabled': true,
          'plans': [initial],
        }),
        isTrue,
      );
      expect(
        await channel.invokeMethod<bool>('sync', {
          'plans': [initial, initial],
        }),
        isTrue,
      );
      await expectLater(
        channel.invokeMethod<bool>('sync', {
          'plans': [
            {...initial, 'url': 'http://example.invalid'},
          ],
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(await deadlineRemindersEnabled(), isTrue);
      await expectLater(
        channel.invokeMethod<bool>('sync', {
          'plans': List.filled(501, initial),
        }),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'reminder_capacity',
          ),
        ),
      );
      expect(await deadlineRemindersEnabled(), isTrue);
      expect(
        await channel.invokeMethod<bool>('sync', {
          'plans': [plan(now + 86400001)],
        }),
        isTrue,
      );
      expect(await channel.invokeMethod<bool>('sync', {'plans': []}), isTrue);
      expect(
        await channel.invokeMethod<bool>('sync', {
          'plans': [initial],
        }),
        isTrue,
      );
      debugPrint(
        'SA015_NATIVE_SCHEDULED: inspect owned no_backup state, alarm and notification on QA emulator',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
      expect(
        await channel.invokeMethod<bool>('sync', {
          'enabled': false,
          'plans': [],
        }),
        isFalse,
      );
      expect(await deadlineRemindersEnabled(), isFalse);
      expect(await channel.invokeMethod<String>('consumeTap'), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
