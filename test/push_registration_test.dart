import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/notifications/push_registration.dart';
import 'package:kamubul_core/kamubul_core.dart';

class _Store implements PushStateStore {
  final map = <String, String>{};
  @override
  String? read(String key) => map[key];
  @override
  void write(String key, String? value) =>
      value == null ? map.remove(key) : map[key] = value;
}

class _Platform implements PushPlatform {
  bool available = true;
  String? token = 'fcm-token-fcm-token-fcm-token';
  int tokenRequests = 0;

  @override
  String get platformName => 'android';
  @override
  Future<bool> initialize() async => available;
  @override
  Future<String?> requestToken() async {
    tokenRequests++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<String> get onNotificationOpened => const Stream.empty();
  @override
  Stream<PendingNotification> get onForegroundNotification => const Stream.empty();
  @override
  Future<String?> takeInitialNotificationUrl() async => null;
}

SavedSearch _search(int id, String name, Map<String, String> filters) =>
    SavedSearch(id: id, name: name, filters: filters, createdAt: DateTime(2026, 9, 1));

void main() {
  late _Store store;
  late _Platform platform;
  late List<http.Request> requests;
  late int Function(http.Request) respond;
  var now = DateTime(2026, 9, 29, 12);

  PushRegistrar registrar() => PushRegistrar(
    baseUrl: Uri.parse('https://kamubul.example'),
    platform: platform,
    store: store,
    random: Random(7),
    clock: () => now,
    utcOffset: () => const Duration(hours: 3),
    client: MockClient((request) async {
      requests.add(request);
      return http.Response('{}', respond(request));
    }),
  );

  setUp(() {
    store = _Store();
    platform = _Platform();
    requests = [];
    respond = (r) => r.method == 'PUT' ? 201 : 200;
    now = DateTime(2026, 9, 29, 12);
  });

  test('kimlik ve gizli anahtar sunucunun beklediği biçimde üretilir', () {
    final credentials = generateCredentials(Random(1));
    expect(isValidDeviceId(credentials.id), isTrue);
    expect(isValidDeviceSecret(credentials.secret), isTrue);
    expect(generateCredentials().id, isNot(credentials.id));
  });

  test('kullanıcı açmadıkça sunucuya hiçbir şey gitmez', () async {
    final result = await registrar().sync([_search(1, 'Ankara', {'sehir': 'ANKARA'})]);
    expect(result, PushSyncOutcome.disabled);
    expect(requests, isEmpty);
    expect(platform.tokenRequests, 0);
  });

  test('etkinleştirme: izin ister, kaydı gönderir; kayıt sunucu doğrulamasından geçer', () async {
    final result = await registrar().enable([
      _search(1, 'Ankara işçi', {'sehir': 'ANKARA', 'kategori': '1', 'gizliAlan': 'x', 'bildirim': 'digest'}),
      _search(2, 'Kapalı', {'sehir': 'İZMİR', 'bildirim': 'off'}),
    ]);
    expect(result, PushSyncOutcome.registered);
    final put = requests.single;
    expect(put.method, 'PUT');
    expect(put.url.path, startsWith('/v1/devices/'));
    expect(put.headers['Authorization'], startsWith('Bearer '));
    final json = jsonDecode(put.body) as Map<String, Object?>;
    // Sunucunun kendi doğrulayıcısından geçmeli.
    final parsed = DeviceRegistration.parse(json);
    expect(parsed.searches, hasLength(1)); // bildirimi kapalı arama gönderilmez
    expect(parsed.searches.single.id, 's1');
    expect(parsed.searches.single.filters.containsKey('gizliAlan'), isFalse);
    expect(parsed.searches.single.filters['bildirim'], 'digest');
    expect(parsed.utcOffsetMinutes, 180);
    expect(parsed.platform, 'android');
    expect(store.read('kamubul.push.enabled'), '1');
  });

  test('izin reddedilirse açılmaz ve sunucuya gitmez', () async {
    platform.token = null;
    expect(await registrar().enable(const []), PushSyncOutcome.permissionDenied);
    expect(requests, isEmpty);
    expect(store.read('kamubul.push.enabled'), isNull);
    platform.available = false;
    expect(await registrar().enable(const []), PushSyncOutcome.unavailable);
  });

  test('içerik değişmediyse ağa çıkılmaz; değişince ya da 24 saat sonra çıkılır', () async {
    final r = registrar();
    final searches = [_search(1, 'Ankara', {'sehir': 'ANKARA'})];
    await r.enable(searches);
    requests.clear();
    expect(await r.sync(searches), PushSyncOutcome.unchanged);
    expect(requests, isEmpty);

    expect(
      await r.sync([_search(1, 'Ankara', {'sehir': 'ANKARA', 'yas': '30'})]),
      PushSyncOutcome.registered,
    );
    expect(requests, hasLength(1));

    requests.clear();
    now = now.add(const Duration(hours: 25));
    expect(
      await r.sync([_search(1, 'Ankara', {'sehir': 'ANKARA', 'yas': '30'})]),
      PushSyncOutcome.registered,
    );
    expect(requests, hasLength(1));
  });

  test('aynı kimlik/anahtar her eşitlemede kullanılır; jeton yenilenince kayıt tazelenir', () async {
    final r = registrar();
    await r.enable([_search(1, 'Ankara', {'sehir': 'ANKARA'})]);
    final first = requests.single.url.path;
    requests.clear();
    expect(await r.onTokenRefreshed('yeni-jeton-yeni-jeton-yeni-jeton'), PushSyncOutcome.registered);
    expect(requests.single.url.path, first);
    expect((jsonDecode(requests.single.body) as Map)['fcmToken'], 'yeni-jeton-yeni-jeton-yeni-jeton');
  });

  test('sunucu hatasında failed döner ve açık kalır; sonraki eşitleme yeniden dener', () async {
    respond = (_) => 503;
    final r = registrar();
    final searches = [_search(1, 'Ankara', {'sehir': 'ANKARA'})];
    expect(await r.enable(searches), PushSyncOutcome.failed);
    expect(r.enabled, isTrue);
    respond = (_) => 201;
    expect(await r.sync(searches), PushSyncOutcome.registered);
  });

  test('kapatma sunucudaki kaydı siler ve yerel kimliği temizler', () async {
    final r = registrar();
    await r.enable([_search(1, 'Ankara', {'sehir': 'ANKARA'})]);
    requests.clear();
    expect(await r.disable(), isTrue);
    expect(requests.single.method, 'DELETE');
    expect(store.read('kamubul.push.id'), isNull);
    expect(store.read('kamubul.push.secret'), isNull);
    expect(r.enabled, isFalse);
  });

  test('silme başarısız olursa bir sonraki eşitlemede yeniden denenir', () async {
    final r = registrar();
    await r.enable([_search(1, 'Ankara', {'sehir': 'ANKARA'})]);
    respond = (req) => req.method == 'DELETE' ? 503 : 201;
    expect(await r.disable(), isFalse);
    expect(store.read('kamubul.push.pendingDelete'), '1');
    expect(r.enabled, isFalse);
    requests.clear();
    respond = (_) => 200;
    await r.sync(const []);
    expect(requests.single.method, 'DELETE');
    expect(store.read('kamubul.push.pendingDelete'), isNull);
    expect(store.read('kamubul.push.id'), isNull);
  });

  test('403 alırsa yeni kimlikle bir kez yeniden dener', () async {
    var puts = 0;
    respond = (req) {
      if (req.method != 'PUT') return 200;
      puts++;
      return puts == 1 ? 403 : 201;
    };
    final r = registrar();
    expect(await r.enable([_search(1, 'Ankara', {'sehir': 'ANKARA'})]), PushSyncOutcome.registered);
    expect(requests, hasLength(2));
    expect(requests[0].url.path, isNot(requests[1].url.path));
  });

  test('aşırı uzun süzgeç değeri ve 20\'den fazla etiket sunucu sınırlarına uyar', () {
    final registration = buildRegistration(
      token: 'x' * 30,
      platform: 'ios',
      utcOffset: const Duration(hours: 3),
      searches: [
        for (var i = 1; i <= 25; i++)
          _search(i, 'Etiket $i', {'q': i == 1 ? 'y' * 200 : 'ok'}),
      ],
    );
    expect(registration.searches, hasLength(20));
    expect(registration.searches.first.filters.containsKey('q'), isFalse);
    expect(() => DeviceRegistration.parse(registration.toJson()), returnsNormally);
  });
}
