/// FCM uygulaması ([PushPlatform]). Firebase ayarı derleme anında
/// `--dart-define` ile verilir; repoda `google-services.json`, anahtar ya da
/// sır bulunmaz. Ayar verilmezse ya da başlatma başarısız olursa özellik
/// sessizce kapalı kalır ve uygulama yalnızca yerel 12 saatlik denetimle çalışır.
///
///   --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=...
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_registration.dart';

const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
const String _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

bool get firebaseConfigured =>
    _apiKey.isNotEmpty &&
    _appId.isNotEmpty &&
    _senderId.isNotEmpty &&
    _projectId.isNotEmpty;

String? _httpsUrl(RemoteMessage message) {
  final url = message.data['url'];
  if (url is! String) return null;
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' ? uri.toString() : null;
}

class FirebasePush implements PushPlatform {
  bool? _ready;

  @override
  String get platformName => Platform.isIOS ? 'ios' : 'android';

  @override
  Future<bool> initialize() async {
    final known = _ready;
    if (known != null) return known;
    if (!firebaseConfigured) return _ready = false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
          ),
        );
      }
      return _ready = true;
    } on Object {
      return _ready = false;
    }
  }

  @override
  Future<String?> requestToken() async {
    if (!await initialize()) return null;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }
      return await messaging.getToken();
    } on Object {
      // iOS'ta APNs jetonu henüz hazır değilse ya da izin akışı bozulduysa.
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh =>
      _ready == true ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  @override
  Stream<String> get onNotificationOpened => _ready == true
      ? FirebaseMessaging.onMessageOpenedApp
            .map(_httpsUrl)
            .where((url) => url != null)
            .cast<String>()
      : const Stream.empty();

  @override
  Future<String?> takeInitialNotificationUrl() async {
    if (_ready != true) return null;
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      return message == null ? null : _httpsUrl(message);
    } on Object {
      return null;
    }
  }
}
