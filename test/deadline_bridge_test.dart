import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/notifications/alert_service.dart';
import 'package:kamubul_core/kamubul_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kamubul/reminders');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final now = DateTime.utc(2026, 10, 16, 9);
  ListingRecord record({bool saved = true, DateTime? end}) => ListingRecord(
    url: 'https://www.ilan.gov.tr/ilan/test',
    sourceId: 'ilangov',
    title: 'Test ilanı',
    category: 'personel',
    publishedAt: null,
    fetchedAt: now,
    deadline: end ?? DateTime.utc(2026, 10, 25, 20, 59),
    saved: saved,
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('sync sends only eligible local records; leaves opt-in native unless explicit', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });
    expect(
      await syncDeadlineReminders([
        record(),
        record(saved: false),
        record(end: now),
      ], now: now),
      isFalse,
    );
    final args = calls.single.arguments as Map;
    expect(args.containsKey('enabled'), isFalse);
    final plans = args['plans'] as List;
    expect(plans.length, 1);
    expect(
      plans.single['at'],
      DateTime.utc(2026, 10, 22, 6).millisecondsSinceEpoch,
    );
    expect(plans.single['expires'], record().deadline!.millisecondsSinceEpoch);
    expect(plans.single['url'], record().url);
  });
  test('off sends empty desired state even if records remain saved', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect((call.arguments as Map)['plans'], isEmpty);
      expect((call.arguments as Map)['enabled'], isFalse);
      return false;
    });
    expect(
      await syncDeadlineReminders([record()], enabled: false, now: now),
      isFalse,
    );
  });
  test('unsave cancels desired plan and deadline revision produces one replacement', () async {
    final plans = <List>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      plans.add((call.arguments as Map)['plans'] as List);
      return true;
    });
    await syncDeadlineReminders([record()], enabled: true, now: now);
    await syncDeadlineReminders([
      record(end: DateTime.utc(2026, 10, 27, 20, 59)),
    ], now: now);
    await syncDeadlineReminders([record(saved: false)], now: now);
    expect(plans.map((p) => p.length), [1, 1, 0]);
    expect(plans[0].single['expires'], isNot(plans[1].single['expires']));
  });
  test('native failure and invalid acknowledgment propagate rather than fake success', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'disk_full'),
    );
    await expectLater(
      syncDeadlineReminders([record()], enabled: true, now: now),
      throwsA(isA<PlatformException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      syncDeadlineReminders([], now: now),
      throwsFormatException,
    );
  });
}
