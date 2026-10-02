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

/// Bellekten okur; değişiklikler atomik ve kalıcı yazılmadan tamamlanmaz.
abstract class PushStateStore {
  String? read(String key);
  Future<void> write(Map<String, String?> values);
}

class DeviceCredentials {
  const DeviceCredentials(this.id, this.secret);
  final String id;
  final String secret;
}

String _hex(Random random, int bytes) => [
  for (var i = 0; i < bytes; i++)
    random.nextInt(256).toRadixString(16).padLeft(2, '0'),
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
const String _kHistory = 'kamubul.push.history';
const kPushStateKeys = [
  _kEnabled,
  _kId,
  _kSecret,
  _kLastPayload,
  _kLastSync,
  _kPendingDelete,
  _kHistory,
];

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
    if (search.filters.entries.any(
      (entry) =>
          kSubscribableFilterKeys.contains(entry.key) &&
          entry.value.length > 100,
    )) {
      continue;
    }
    SearchCriteria criteria;
    try {
      criteria = search.effectiveCriteria;
    } on FormatException {
      continue;
    }
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
        criteria: criteria,
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
       _utcOffset = utcOffset ?? (() => DateTime.now().timeZoneOffset) {
    if (baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Güvenli sunucu adresi gerekir',
      );
    }
  }

  final Uri baseUrl;
  final PushPlatform platform;
  final PushStateStore store;
  final Duration timeout;
  final http.Client _client;
  final Random? _random;
  final DateTime Function() _clock;
  final Duration Function() _utcOffset;

  List<SavedSearch> _lastSearches = const [];
  Future<void> _operations = Future.value();
  final _historyChanges = StreamController<void>.broadcast();
  Stream<void> get onHistoryChanged => _historyChanges.stream;

  // ponytail: per-installation FIFO; debounce edits before this queue if traffic grows.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// Kullanıcı sunucu bildirimlerini açtı mı.
  bool get enabled => store.read(_kEnabled) == '1';

  Uri _device(String id) => baseUrl.replace(
    path:
        '${baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path}/api/v2/installations/$id',
  );

  Future<DeviceCredentials> _credentials() async {
    final id = store.read(_kId);
    final secret = store.read(_kSecret);
    if (id != null &&
        secret != null &&
        isValidDeviceId(id) &&
        isValidDeviceSecret(secret)) {
      return DeviceCredentials(id, secret);
    }
    final fresh = generateCredentials(_random);
    await store.write({
      _kId: fresh.id,
      _kSecret: fresh.secret,
      _kLastPayload: null,
      _kHistory: null,
    });
    return fresh;
  }

  /// Kullanıcı eylemi: izin ister, jetonu alır, kaydı gönderir.
  Future<PushSyncOutcome> enable(List<SavedSearch> searches) =>
      _enqueue(() => _enable(searches));
  Future<PushSyncOutcome> _enable(List<SavedSearch> searches) async {
    if (!await platform.initialize()) return PushSyncOutcome.unavailable;
    final token = await platform.requestToken();
    if (token == null) return PushSyncOutcome.permissionDenied;
    try {
      await store.write({_kEnabled: '1'});
    } on Exception {
      return PushSyncOutcome.failed;
    }
    _lastSearches = searches;
    // Başarısız olursa açık kalır; bir sonraki eşitleme yeniden dener.
    return _register(token, searches, force: true);
  }

  /// Sunucudaki kaydı siler ve yerel kimliği temizler ("bildirim verilerimi sil").
  Future<bool> disable() => _enqueue(_disable);
  Future<bool> _disable() async {
    try {
      final id = store.read(_kId);
      final secret = store.read(_kSecret);
      await store.write({
        _kEnabled: null,
        _kLastPayload: null,
        _kLastSync: null,
        _kPendingDelete: '1',
        _kHistory: null,
      });
      if (!_historyChanges.isClosed) {
        _historyChanges.add(null);
      }
      if (id == null || secret == null) {
        await store.write({_kId: null, _kSecret: null, _kPendingDelete: null});
        return true;
      }
      final deleted = await _delete(id, secret);
      if (deleted) {
        await store.write({_kId: null, _kSecret: null, _kPendingDelete: null});
      }
      return deleted;
    } on Exception {
      return false;
    }
  }

  /// Etiketler değiştiğinde ya da uygulama açılınca çağrılır; yalnızca
  /// açıksa ve içerik değiştiyse (ya da 24 saati geçtiyse) ağa çıkar.
  Future<PushSyncOutcome> sync(
    List<SavedSearch> searches, {
    bool force = false,
  }) => _enqueue(() => _sync(searches, force: force));
  Future<PushSyncOutcome> _sync(
    List<SavedSearch> searches, {
    required bool force,
  }) async {
    _lastSearches = searches;
    if (store.read(_kPendingDelete) == '1') {
      final id = store.read(_kId);
      final secret = store.read(_kSecret);
      if (id != null && secret != null && await _delete(id, secret)) {
        try {
          await store.write({
            _kId: null,
            _kSecret: null,
            _kPendingDelete: null,
          });
        } on Exception {
          return PushSyncOutcome.failed;
        }
      }
    }
    if (!enabled) return PushSyncOutcome.disabled;
    if (!await platform.initialize()) return PushSyncOutcome.unavailable;
    final token = await platform.requestToken();
    if (token == null) return PushSyncOutcome.permissionDenied;
    return _register(token, searches, force: force);
  }

  /// Jeton yenilenince son bilinen etiketlerle kaydı tazeler.
  Future<PushSyncOutcome> onTokenRefreshed(String token) =>
      _enqueue(() => _refreshToken(token));
  Future<PushSyncOutcome> _refreshToken(String token) async {
    if (!enabled) return PushSyncOutcome.disabled;
    return _register(token, _lastSearches, force: true);
  }

  Future<PushSyncOutcome> _register(
    String token,
    List<SavedSearch> searches, {
    required bool force,
  }) async {
    try {
      final registration = buildRegistration(
        token: token,
        platform: platform.platformName,
        searches: searches,
        utcOffset: _utcOffset(),
      );
      final body = jsonEncode(registration.toV2Json());
      if (utf8.encode(body).length > 32768) return PushSyncOutcome.failed;
      final lastMs = int.tryParse(store.read(_kLastSync) ?? '');
      final recent =
          lastMs != null &&
          _clock().difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
              const Duration(hours: 24);
      if (!force && recent && store.read(_kLastPayload) == body) {
        return PushSyncOutcome.unchanged;
      }
      final credentials = await _credentials();
      final status = await _put(credentials, body);
      if (status == 200 || status == 201) {
        await _saveHistory(
          _historyState(),
          updates: {
            _kLastPayload: body,
            _kLastSync: '${_clock().millisecondsSinceEpoch}',
          },
        );
        return PushSyncOutcome.registered;
      }
      return PushSyncOutcome.failed;
    } on Exception {
      return PushSyncOutcome.failed;
    }
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

  Map<String, dynamic> _historyState() {
    try {
      final raw = jsonDecode(store.read(_kHistory) ?? 'null');
      if (raw is Map<String, dynamic> &&
          raw['owner'] == store.read(_kId) &&
          raw['origin'] == baseUrl.toString() &&
          raw['after'] is int &&
          raw['after'] >= 0 &&
          raw['after'] <= 9007199254740991 &&
          (raw['watermark'] == null ||
              (raw['watermark'] is int &&
                  raw['watermark'] >= raw['after'] &&
                  raw['watermark'] <= 9007199254740991)) &&
          raw['records'] is List &&
          raw['records'].length <= 100 &&
          raw['seen'] is List &&
          raw['seen'].length <= 200 &&
          raw['seen'].every(
            (id) => id is String && RegExp(r'^[a-f\d]{64}$').hasMatch(id),
          )) {
        return raw;
      }
    } on FormatException {
      /* Reconcile a corrupt cache from the authenticated feed. */
    }
    return {
      'owner': store.read(_kId),
      'origin': baseUrl.toString(),
      'after': 0,
      'watermark': null,
      'records': <dynamic>[],
      'seen': <dynamic>[],
    };
  }

  List<AlertRecord> get notificationHistory =>
      (_historyState()['records'] as List)
          .map(AlertRecord.fromJson)
          .whereType<AlertRecord>()
          .toList();

  Future<void> _saveHistory(
    Map<String, dynamic> state, {
    Map<String, String> updates = const {},
  }) async {
    final records = state['records'] as List, seen = state['seen'] as List;
    if (records.length > 100) records.removeRange(100, records.length);
    if (seen.length > 200) seen.removeRange(200, seen.length);
    final values = {
      for (final key in kPushStateKeys)
        if (key != _kHistory && store.read(key) != null) key: store.read(key)!,
    };
    values.addAll(updates);
    String encoded;
    // ponytail: 100 history / 200 received IDs, trimmed to the native 128KB state budget; SQLite is the upgrade path for longer retention.
    for (;;) {
      encoded = jsonEncode(state);
      values[_kHistory] = encoded;
      if (utf8.encode(jsonEncode(values)).length <= 120000) break;
      if (records.isEmpty) {
        throw const FormatException('notification history budget');
      }
      records.removeLast();
    }
    await store.write({...updates, _kHistory: encoded});
    if (!_historyChanges.isClosed) {
      _historyChanges.add(null);
    }
  }

  /// Clears visible cached records; cursor and received IDs prevent resurrection.
  Future<void> clearNotificationHistory() => _enqueue(() async {
    final state = _historyState();
    state['records'] = <dynamic>[];
    await _saveHistory(state);
  });

  /// Commit receipt before presentation; concurrent/restarted foreground retries dedupe.
  Future<bool> recordForeground(PendingNotification notification) =>
      _enqueue(() async {
        final id = notification.eventId;
        if (!enabled || id == null || !RegExp(r'^[a-f\d]{64}$').hasMatch(id)) {
          return false;
        }
        final state = _historyState(), seen = state['seen'] as List;
        if (seen.contains(id)) return false;
        final record = AlertRecord(
          id: id,
          kind: notification.digest ? AlertKind.digest : AlertKind.instant,
          searchName: '',
          title: notification.title,
          body: notification.body,
          listingUrl: notification.listingUrl,
          listingId: notification.listingId,
          createdAt: _clock(),
          delivery: AlertDelivery.received,
        );
        state['records'] = [
          record.toJson(),
          ...(state['records'] as List).where((r) => r is Map && r['id'] != id),
        ];
        seen.insert(0, id);
        await _saveHistory(state);
        return true;
      });

  /// No permission prompt, token request or new identity for a history read.
  Future<bool> syncHistory() => _enqueue(() async {
    final id = store.read(_kId), secret = store.read(_kSecret);
    if (!enabled ||
        id == null ||
        secret == null ||
        !isValidDeviceId(id) ||
        !isValidDeviceSecret(secret)) {
      return false;
    }
    try {
      var state = _historyState();
      var reset = false;
      // ponytail: five pages per opening; pinned cursor persists across a larger backlog.
      for (var i = 0; i < 5; i++) {
        final after = state['after'] as int,
            watermark = state['watermark'] as int?;
        final request =
            http.Request(
                'GET',
                _device(id).replace(
                  path: '${_device(id).path}/notifications',
                  queryParameters: {
                    'after': '$after',
                    'limit': '30',
                    if (watermark != null) 'watermark': '$watermark',
                  },
                ),
              )
              ..followRedirects = false
              ..headers.addAll({
                'Accept': 'application/json',
                'Authorization': 'Bearer $secret',
                'Cache-Control': 'no-store',
              });
        final page = await (() async {
          final response = await _client.send(request);
          if (response.statusCode != 200) {
            await response.stream.listen(null).cancel();
            if (response.statusCode == 409 && !reset) return null;
            throw const FormatException('notification history request');
          }
          final bytes = <int>[];
          await for (final chunk in response.stream) {
            if (bytes.length + chunk.length > 262144) {
              throw const FormatException('notification history size');
            }
            bytes.addAll(chunk);
          }
          return NotificationHistoryPage.decode(
            jsonDecode(utf8.decode(bytes)),
            after: after,
            expectedWatermark: watermark,
          );
        })().timeout(timeout);
        if (page == null) {
          reset = true;
          state['after'] = 0;
          state['watermark'] = null;
          await _saveHistory(state);
          continue;
        }
        final existing = {
          for (final record
              in (state['records'] as List)
                  .map(AlertRecord.fromJson)
                  .whereType<AlertRecord>())
            record.id: record,
        };
        for (final record in page.records) {
          if (existing[record.id]?.delivery == AlertDelivery.received) {
            record.delivery = AlertDelivery.received;
          }
          existing[record.id] = record;
        }
        final records = existing.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        state['records'] = records.map((r) => r.toJson()).toList();
        state['after'] = page.appliedThrough;
        state['watermark'] = page.hasMore ? page.watermark : null;
        await _saveHistory(state);
        if (!page.hasMore) return true;
      }
    } on Exception {
      return false;
    }
    return false;
  });

  void close() {
    _historyChanges.close();
    _client.close();
  }
}
