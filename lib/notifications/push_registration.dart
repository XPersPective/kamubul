/// Sunucu bildirimlerine anonim abonelik.
///
/// Kullanıcı açıkça etkinleştirmedikçe (bildirim izni verip anahtarı açtıkça)
/// sunucuya HİÇBİR şey gitmez. Hesap yoktur: cihaz rastgele bir kimlik ve gizli
/// anahtar üretir; sunucu yalnızca anahtarın özetini saklar. Sunucuya yalnızca
/// FCM jetonu, saat dilimi farkı, sessiz saatler, günlük tavan ve kayıtlı
/// aramaların süzgeçleri gider. Kapatınca ya da "bildirim verilerimi sil"
/// deyince kayıt sunucudan silinir.
///
/// Platform (Firebase) [PushPlatform] arayüzünün arkasındadır; bu dosya saf
/// Dart'tır ve Firebase yapılandırılmadan da test edilir.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:kamubul_core/kamubul_core.dart';

/// Firebase/FCM erişimi. Uygulamada `FirebasePush`, testte sahte uygulama.
abstract class PushPlatform {
  /// `android` veya `ios`.
  String get platformName;

  /// Firebase yapılandırılmış ve başlatılabildi mi.
  Future<bool> initialize();

  /// Gerekirse bildirim izni ister; reddedilirse `null`.
  Future<String?> requestToken();

  Stream<String> get onTokenRefresh;

  /// Bildirime dokunulduğunda ilan bağlantısı.
  Stream<String> get onNotificationOpened;

  /// Uygulama açıkken gösterilecek sunucu bildirimi.
  Stream<PendingNotification> get onForegroundNotification;

  /// Uygulama bildirime dokunularak açıldıysa bağlantı (tek seferlik).
  Future<String?> takeInitialNotificationUrl();
}

/// Küçük kalıcı anahtar-değer deposu (uygulamada `SettingsStore`).
abstract class PushStateStore {
  String? read(String key);
  void write(String key, String? value);
}

class DeviceCredentials {
  const DeviceCredentials(this.id, this.secret);
  final String id;
  final String secret;
}

String _hex(Random random, int bytes) => [
  for (var i = 0; i < bytes; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

DeviceCredentials generateCredentials([Random? random]) {
  final source = random ?? Random.secure();
  return DeviceCredentials(_hex(source, 16), _hex(source, 32));
}

enum PushSyncOutcome {
  /// Kullanıcı etkinleştirmedi; hiçbir şey gönderilmedi.
  disabled,

  /// Firebase yapılandırılmamış (derlemede FIREBASE_* verilmedi).
  unavailable,
  permissionDenied,
  unchanged,
  registered,
  failed,
}

/// Uygulamadaki sabit bildirim tercihleri (`AlertSettings` ile aynı).
const int kPushQuietStartHour = 22;
const int kPushQuietEndHour = 8;
const int kPushMaxInstantPerDay = 6;

const String _kEnabled = 'kamubul.push.enabled';
const String _kId = 'kamubul.push.id';
const String _kSecret = 'kamubul.push.secret';
const String _kLastPayload = 'kamubul.push.lastPayload';
const String _kLastSync = 'kamubul.push.lastSyncMs';
const String _kPendingDelete = 'kamubul.push.pendingDelete';

/// Sunucuya gidecek kayıt: yalnızca izinli süzgeç anahtarları, sınırlı
/// uzunlukta, bildirimi kapalı aramalar hariç.
DeviceRegistration buildRegistration({
  required String token,
  required String platform,
  required List<SavedSearch> searches,
  required Duration utcOffset,
}) {
  final subscribed = <SubscribedSearch>[];
  for (final search in searches) {
    final id = search.id;
    if (id == null) continue;
    if (alertModeOf(search.filters) == SearchAlertMode.off) continue;
    final name = search.name.trim();
    if (name.isEmpty) continue;
    final filters = <String, String>{
      for (final entry in search.filters.entries)
        if (kSubscribableFilterKeys.contains(entry.key) &&
            entry.value.isNotEmpty &&
            entry.value.length <= 100)
          entry.key: entry.value,
    };
    subscribed.add(
      SubscribedSearch(
        id: 's$id',
        name: name.length > 80 ? name.substring(0, 80) : name,
        filters: filters,
      ),
    );
    if (subscribed.length >= kMaxSubscribedSearches) break;
  }
  return DeviceRegistration(
    fcmToken: token,
    platform: platform,
    utcOffsetMinutes: utcOffset.inMinutes.clamp(-720, 840),
    quietStartHour: kPushQuietStartHour,
    quietEndHour: kPushQuietEndHour,
    maxInstantPerDay: kPushMaxInstantPerDay,
    searches: subscribed,
  );
}

class PushRegistrar {
  PushRegistrar({
    required this.baseUrl,
    required this.platform,
    required this.store,
    http.Client? client,
    this._random,
    DateTime Function()? clock,
    Duration Function()? utcOffset,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _utcOffset = utcOffset ?? (() => DateTime.now().timeZoneOffset);

  final Uri baseUrl;
  final PushPlatform platform;
  final PushStateStore store;
  final Duration timeout;
  final http.Client _client;
  final Random? _random;
  final DateTime Function() _clock;
  final Duration Function() _utcOffset;

  List<SavedSearch> _lastSearches = const [];

  /// Kullanıcı sunucu bildirimlerini açtı mı.
  bool get enabled => store.read(_kEnabled) == '1';

  Uri _device(String id) => baseUrl.replace(
    path: '${baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path}/v1/devices/$id',
  );

  DeviceCredentials _credentials({bool renew = false}) {
    final id = store.read(_kId);
    final secret = store.read(_kSecret);
    if (!renew && id != null && secret != null && isValidDeviceId(id) && isValidDeviceSecret(secret)) {
      return DeviceCredentials(id, secret);
    }
    final fresh = generateCredentials(_random);
    store
      ..write(_kId, fresh.id)
      ..write(_kSecret, fresh.secret)
      ..write(_kLastPayload, null);
    return fresh;
  }

  /// Kullanıcı eylemi: izin ister, jetonu alır, kaydı gönderir.
  Future<PushSyncOutcome> enable(List<SavedSearch> searches) async {
    if (!await platform.initialize()) return PushSyncOutcome.unavailable;
    final token = await platform.requestToken();
    if (token == null) return PushSyncOutcome.permissionDenied;
    store.write(_kEnabled, '1');
    _lastSearches = searches;
    // Başarısız olursa açık kalır; bir sonraki eşitleme yeniden dener.
    return _register(token, searches, force: true);
  }

  /// Sunucudaki kaydı siler ve yerel kimliği temizler ("bildirim verilerimi sil").
  Future<bool> disable() async {
    final id = store.read(_kId);
    final secret = store.read(_kSecret);
    store.write(_kEnabled, null);
    store.write(_kLastPayload, null);
    store.write(_kLastSync, null);
    if (id == null || secret == null) {
      store
        ..write(_kId, null)
        ..write(_kSecret, null)
        ..write(_kPendingDelete, null);
      return true;
    }
    final deleted = await _delete(id, secret);
    if (deleted) {
      store
        ..write(_kId, null)
        ..write(_kSecret, null)
        ..write(_kPendingDelete, null);
    } else {
      // Ağ yok: silme bir sonraki eşitlemede yeniden denenir.
      store.write(_kPendingDelete, '1');
    }
    return deleted;
  }

  /// Etiketler değiştiğinde ya da uygulama açılınca çağrılır; yalnızca
  /// açıksa ve içerik değiştiyse (ya da 24 saati geçtiyse) ağa çıkar.
  Future<PushSyncOutcome> sync(List<SavedSearch> searches, {bool force = false}) async {
    _lastSearches = searches;
    if (store.read(_kPendingDelete) == '1') {
      final id = store.read(_kId);
      final secret = store.read(_kSecret);
      if (id != null && secret != null && await _delete(id, secret)) {
        store
          ..write(_kId, null)
          ..write(_kSecret, null)
          ..write(_kPendingDelete, null);
      }
    }
    if (!enabled) return PushSyncOutcome.disabled;
    if (!await platform.initialize()) return PushSyncOutcome.unavailable;
    final token = await platform.requestToken();
    if (token == null) return PushSyncOutcome.permissionDenied;
    return _register(token, searches, force: force);
  }

  /// Jeton yenilenince son bilinen etiketlerle kaydı tazeler.
  Future<PushSyncOutcome> onTokenRefreshed(String token) async {
    if (!enabled) return PushSyncOutcome.disabled;
    return _register(token, _lastSearches, force: true);
  }

  Future<PushSyncOutcome> _register(
    String token,
    List<SavedSearch> searches, {
    required bool force,
  }) async {
    final registration = buildRegistration(
      token: token,
      platform: platform.platformName,
      searches: searches,
      utcOffset: _utcOffset(),
    );
    final body = jsonEncode(registration.toJson());
    final lastMs = int.tryParse(store.read(_kLastSync) ?? '');
    final recent =
        lastMs != null &&
        _clock().difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) < const Duration(hours: 24);
    if (!force && recent && store.read(_kLastPayload) == body) {
      return PushSyncOutcome.unchanged;
    }
    var credentials = _credentials();
    var status = await _put(credentials, body);
    if (status == 403) {
      // Kimlik başkasına aitse (pratikte olmaz) yeni kimlikle bir kez dene.
      credentials = _credentials(renew: true);
      status = await _put(credentials, body);
    }
    if (status == 200 || status == 201) {
      store
        ..write(_kLastPayload, body)
        ..write(_kLastSync, '${_clock().millisecondsSinceEpoch}');
      return PushSyncOutcome.registered;
    }
    return PushSyncOutcome.failed;
  }

  Future<int> _put(DeviceCredentials credentials, String body) async {
    try {
      final response = await _client
          .put(
            _device(credentials.id),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${credentials.secret}',
            },
            body: body,
          )
          .timeout(timeout);
      return response.statusCode;
    } on Exception {
      return -1;
    }
  }

  Future<bool> _delete(String id, String secret) async {
    try {
      final response = await _client
          .delete(_device(id), headers: {'Authorization': 'Bearer $secret'})
          .timeout(timeout);
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  void close() => _client.close();
}
