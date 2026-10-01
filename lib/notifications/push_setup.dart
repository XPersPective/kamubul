/// Sunucu bildirimlerinin uygulamaya bağlanması: tek genel kayıtçı (mevcut
/// `alertTapUrl` deseniyle aynı), ayarlar deposu köprüsü ve bildirim
/// dokunuşu olayları. `KAMUBUL_API` verilmediyse [pushRegistrar] `null`'dır
/// ve arayüz sunucu bildirimi seçeneğini göstermez.
library;

import 'dart:async';

import 'package:napp_core/napp_core.dart';

import '../data/remote_sync.dart';
import 'alert_service.dart';
import 'firebase_push.dart';
import 'push_registration.dart';

PushRegistrar? pushRegistrar;

bool _listening = false;

class _SettingsPushStore implements PushStateStore {
  _SettingsPushStore(this._store);

  final SettingsStore _store;

  @override
  String? read(String key) {
    final value = _store.getString(key);
    return value == null || value.isEmpty ? null : value;
  }

  // SettingsStore silme sunmaz; boş metin "yok" demektir.
  @override
  void write(String key, String? value) => _store.setString(key, value ?? '');
}

/// Açılışta bir kez çağrılır. Kullanıcı sunucu bildirimini açmadıysa Firebase'e
/// hiç dokunulmaz.
Future<void> initPush(SettingsStore store) async {
  if (kApiBaseUrl.isEmpty) return;
  final Uri base;
  try {
    base = Uri.parse(kApiBaseUrl);
  } on FormatException {
    return;
  }
  final registrar = PushRegistrar(
    baseUrl: base,
    platform: FirebasePush(),
    store: _SettingsPushStore(store),
  );
  pushRegistrar = registrar;
  if (registrar.enabled) await attachPushListeners();
}

/// Bildirim dokunuşu ve jeton yenileme olaylarını bağlar (tek seferlik).
Future<void> attachPushListeners() async {
  final registrar = pushRegistrar;
  if (registrar == null || _listening) return;
  if (!await registrar.platform.initialize()) return;
  _listening = true;
  registrar.platform.onNotificationOpened.listen(openAlertUrl);
  registrar.platform.onForegroundNotification.listen((notification) {
    if (!registrar.enabled) return;
    unawaited(
      showPendingNotification(notification).catchError((Object error) {
        // Sunum hatası uygulamayı kapatmaz; jeton/ilan içeriği loglanmaz.
      }),
    );
  });
  registrar.platform.onTokenRefresh.listen(
    (token) => unawaited(registrar.onTokenRefreshed(token)),
  );
  final initial = await registrar.platform.takeInitialNotificationUrl();
  if (initial != null) openAlertUrl(initial);
}
