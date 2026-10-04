import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:napp_core/napp_core.dart';

import 'remote_sync.dart';

/// Asistan yanıtı: criteria yalnız intent == 'criteria' iken doludur.
class AssistantReply {
  const AssistantReply({
    required this.intent,
    required this.reply,
    this.criteria,
  });

  final String intent;
  final String reply;
  final Map<String, Object?>? criteria;
}

class AssistantException implements Exception {
  const AssistantException(this.message);
  final String message;
}

/// Kriter asistanı istemcisi. Sunucu kapsam dışı istekleri modele göndermez;
/// istemci de boş/çok uzun mesajı hiç göndermez.
class AssistantClient {
  AssistantClient({required this.store, http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _base = baseUrl ?? kApiBaseUrl;

  static const maxMessage = 300;
  static const _idKey = 'kamubul.assistantId';

  final SettingsStore store;
  final http.Client _client;
  final String _base;

  bool get available => _base.isNotEmpty;

  String _installationId() {
    final existing = store.getString(_idKey);
    if (existing != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    store.setString(_idKey, id);
    return id;
  }

  Future<AssistantReply> ask(String message) async {
    final text = message.trim();
    if (!available) {
      throw const AssistantException('Asistan şu an kullanılamıyor.');
    }
    if (text.length < 4 || text.length > maxMessage) {
      throw const AssistantException(
        'Lütfen 4–300 karakterlik bir istek yazın.',
      );
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_base/api/v2/assistant'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'installationId': _installationId(),
              'message': text,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const AssistantException(
        'Bağlantı kurulamadı. Daha sonra tekrar deneyin.',
      );
    }
    if (response.statusCode == 429) {
      throw const AssistantException(
        'Bugünlük asistan hakkınız doldu. Yarın tekrar deneyin veya '
        'kriterleri elle girin.',
      );
    }
    if (response.statusCode != 200) {
      throw const AssistantException(
        'Asistan şu an yanıt veremiyor. Kriterleri elle girebilirsiniz.',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw const AssistantException('Beklenmeyen yanıt alındı.');
    }
    final criteria = body['criteria'];
    return AssistantReply(
      intent: body['intent'] is String ? body['intent'] as String : 'refuse',
      reply: body['reply'] is String ? body['reply'] as String : '',
      criteria: criteria is Map<String, dynamic>
          ? Map<String, Object?>.from(criteria)
          : null,
    );
  }
}
