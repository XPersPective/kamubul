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
  const AssistantException(this.message, {this.upgrade = false});
  final String message;

  /// Ücretsiz günlük hak doldu; Pro daha yüksek sınır verir.
  final bool upgrade;
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

  /// KamuBul Asistan sohbeti: seçili ilan metni ve son birkaç mesajla.
  Future<AssistantReply> chat(
    String message, {
    List<({String role, String text})> history = const [],
    String? listingTitle,
    String? listingText,
    bool pro = false,
    Map<String, Object?>? profile,
  }) => ask(
    message,
    extra: {
      'mode': 'chat',
      if (pro) 'tier': 'pro',
      if (profile != null && profile.isNotEmpty) 'profile': profile,
      'history': [
        for (final turn
            in history.length > 10
                ? history.sublist(history.length - 10)
                : history)
          {'role': turn.role, 'text': turn.text},
      ],
      if (listingText != null && listingText.trim().isNotEmpty)
        'listing': {
          'title': listingTitle ?? '',
          // Sunucu da kırpar; gereksiz veri gönderilmez.
          'text': listingText.length > 8000
              ? listingText.substring(0, 8000)
              : listingText,
        },
    },
  );

  Future<AssistantReply> ask(
    String message, {
    Map<String, Object?> extra = const {},
  }) async {
    final text = message.trim();
    if (!available) {
      throw const AssistantException('Asistan şu an kullanılamıyor.');
    }
    if (text.length < 2 || text.length > maxMessage) {
      throw const AssistantException('Mesaj en fazla 300 karakter olabilir.');
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
              ...extra,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const AssistantException(
        'Bağlantı kurulamadı. Daha sonra tekrar deneyin.',
      );
    }
    if (response.statusCode == 429) {
      final free = utf8.decode(response.bodyBytes).contains('free_limit');
      throw AssistantException(
        free
            ? 'Bugünkü ücretsiz asistan hakkınız doldu. Yarın yenilenir; '
                  'Pro ile günde çok daha fazla soru sorabilirsiniz.'
            : 'Asistan bugün yoğun. Lütfen daha sonra tekrar deneyin.',
        upgrade: free,
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
