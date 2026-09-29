/// Bildirim gönderimi: FCM HTTP v1 (Google öncelikli) veya yalnızca günlük.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class PushMessage {
  const PushMessage({
    required this.token,
    required this.title,
    required this.body,
    required this.url,
    this.digest = false,
  });

  final String token;
  final String title;
  final String body;

  /// Bildirime dokunulunca açılacak ilan bağlantısı.
  final String url;
  final bool digest;
}

enum PushOutcome { sent, invalidToken, failed }

abstract class PushSender {
  Future<PushOutcome> send(PushMessage message);
}

/// Geliştirme ve kuru çalıştırma: hiçbir yere göndermez.
class LogPushSender implements PushSender {
  LogPushSender(this._log);

  final void Function(String) _log;

  @override
  Future<PushOutcome> send(PushMessage message) async {
    _log('push(log) ${message.title} → ${message.url}');
    return PushOutcome.sent;
  }
}

class NoPushSender implements PushSender {
  @override
  Future<PushOutcome> send(PushMessage message) async => PushOutcome.sent;
}

/// FCM HTTP v1. [client] kimlik doğrulamalıdır (Bearer jetonunu ekler).
class FcmPushSender implements PushSender {
  FcmPushSender({
    required this._client,
    required String projectId,
    String host = 'https://fcm.googleapis.com',
  }) : _url = Uri.parse('$host/v1/projects/$projectId/messages:send');

  final http.Client _client;
  final Uri _url;

  /// Uygulamanın yerel bildirim kanalıyla aynı kimlik (`alert_service.dart`).
  static const String androidChannelId = 'kamubul_alerts';

  @override
  Future<PushOutcome> send(PushMessage message) async {
    final http.Response response;
    try {
      response = await _client.post(
        _url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': message.token,
            'notification': {'title': message.title, 'body': message.body},
            'data': {
              'url': message.url,
              'kind': message.digest ? 'digest' : 'instant',
            },
            'android': {
              'priority': 'HIGH',
              'notification': {'channel_id': androidChannelId},
            },
            'apns': {
              'payload': {
                'aps': {'sound': 'default'},
              },
            },
          },
        }),
      );
    } on Exception {
      return PushOutcome.failed;
    }
    if (response.statusCode == 200) return PushOutcome.sent;
    if (_isInvalidToken(response)) return PushOutcome.invalidToken;
    return PushOutcome.failed;
  }

  bool _isInvalidToken(http.Response response) {
    if (response.statusCode != 404 && response.statusCode != 400) return false;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final error = json is Map ? json['error'] : null;
      if (error is! Map) return response.statusCode == 404;
      final details = error['details'];
      if (details is List) {
        for (final detail in details) {
          if (detail is Map && detail['errorCode'] == 'UNREGISTERED') {
            return true;
          }
        }
      }
      if (response.statusCode == 404) return true;
      final message = '${error['message']}'.toLowerCase();
      return error['status'] == 'INVALID_ARGUMENT' && message.contains('token');
    } on FormatException {
      return response.statusCode == 404;
    }
  }
}
