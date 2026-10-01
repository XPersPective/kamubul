/// Sunucu bildirimlerinin uygulamaya bağlanması: tek genel kayıtçı (mevcut
/// `alertTapUrl` deseniyle aynı), ayarlar deposu köprüsü ve bildirim
/// dokunuşu olayları. `KAMUBUL_API` verilmediyse [pushRegistrar] `null`'dır
/// ve arayüz sunucu bildirimi seçeneğini göstermez.
library;

import 'dart:async';

import 'package:napp_core/napp_core.dart';
import 'package:flutter/widgets.dart';

import '../data/remote_sync.dart';
import 'alert_service.dart';
import 'firebase_push.dart';
import 'push_registration.dart';
import 'secure_push_store.dart';

PushRegistrar? pushRegistrar;

bool _listening = false;
AppLifecycleListener? _pushLifecycle;

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
  final PushRegistrar registrar;
  try {
    final secure = await SecurePushStore.load(store);
    registrar = PushRegistrar(
      baseUrl: base,
      platform: FirebasePush(),
      store: secure,
    );
  } on Exception {
    // No plaintext fallback or new server identity when secure storage fails.
    return;
  } on ArgumentError {
    return;
  }
  pushRegistrar = registrar;
  _pushLifecycle ??= AppLifecycleListener(
    onResume: () => unawaited(registrar.syncHistory()),
  );
  if (registrar.enabled) {
    unawaited(attachPushListeners().catchError((Object _) {}));
  }
}

/// Bildirim dokunuşu ve jeton yenileme olaylarını bağlar (tek seferlik).
Future<void> attachPushListeners() async {
  final registrar = pushRegistrar;
  if (registrar == null || _listening) return;
  unawaited(registrar.syncHistory());
  if (!await registrar.platform.initialize()) return;
  _listening = true;
  registrar.platform.onNotificationOpened.listen(openAlertUrl);
  registrar.platform.onForegroundNotification.listen((notification) {
    if (!registrar.enabled) return;
    unawaited(
      (() async {
        if (await registrar.recordForeground(notification) &&
            registrar.enabled) {
          await showPendingNotification(notification);
        }
      })().catchError((Object error) {
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
