import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/trial_sync.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kamubul/device');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'a' * 64);
  });

  test('yeniden kurulumda sunucudaki eski başlangıç kullanılır', () async {
    final store = SettingsStore();
    store.setInt(
      'kamubul.ads.first',
      DateTime.utc(2026, 10, 20).millisecondsSinceEpoch,
    );
    await syncTrialStart(
      store,
      baseUrl: 'https://api.test',
      client: MockClient(
        (_) async => http.Response('{"firstSeen":"2026-10-01T00:00:00Z"}', 200),
      ),
    );
    expect(
      store.getInt('kamubul.ads.first'),
      DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
    );
  });

  test(
    'sunucu hatasında yerel değer korunur, daha yeni sunucu değeri alınmaz',
    () async {
      final store = SettingsStore();
      final local = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      store.setInt('kamubul.ads.first', local);
      await syncTrialStart(
        store,
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('', 503)),
      );
      expect(store.getInt('kamubul.ads.first'), local);
      expect(earliestFirstLaunch(local, DateTime.utc(2026, 10, 9)), local);
    },
  );
}
