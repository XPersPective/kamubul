/// Sağlayıcıdan bağımsız metin modeli istemcisi.
///
/// Üç adaptör aynı arayüzü uygular: Anthropic Messages API, OpenAI uyumlu
/// Chat Completions (taban adres ayarlanabilir; OpenAI, OpenRouter, kendi
/// barındırdığınız modeller) ve Gemini. Sağlayıcı, model ve anahtar yalnızca
/// sunucu ortam değişkenlerinden gelir. Yapılandırılmış çıktı özellikleri
/// sağlayıcıya göre değiştiği için düz metin istenir; JSON'u çağıran taraf
/// kendisi doğrular. Örnekleme parametreleri (temperature vb.) gönderilmez:
/// yeni modellerde reddedilirler.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmRequest {
  const LlmRequest({
    required this.system,
    required this.user,
    this.maxTokens = 4096,
  });

  final String system;
  final String user;
  final int maxTokens;
}

class LlmResponse {
  const LlmResponse({
    required this.text,
    required this.inputTokens,
    required this.outputTokens,
    required this.model,
  });

  final String text;
  final int inputTokens;
  final int outputTokens;
  final String model;
}

class LlmException implements Exception {
  const LlmException(this.message, {this.statusCode, this.refused = false});

  final String message;
  final int? statusCode;

  /// Model güvenlik nedeniyle yanıtı reddetti; tekrar denemek işe yaramaz.
  final bool refused;

  bool get retryable =>
      !refused &&
      (statusCode == null ||
          statusCode == 408 ||
          statusCode == 409 ||
          statusCode == 429 ||
          statusCode! >= 500);

  @override
  String toString() => 'LlmException($statusCode): $message';
}

abstract class LlmClient {
  String get provider;
  String get model;
  Future<LlmResponse> complete(LlmRequest request);
}

/// Sunucu ortam değişkenlerinden okunan model ayarı.
class LlmConfig {
  const LlmConfig({
    required this.provider,
    required this.model,
    required this.apiKey,
    this.baseUrl,
    this.maxTokensParam = 'max_tokens',
    this.jsonMode = false,
  });

  /// `anthropic`, `openai` (OpenAI uyumlu) veya `gemini`.
  final String provider;
  final String model;
  final String apiKey;
  final String? baseUrl;

  /// OpenAI uyumlu uçlarda çıktı sınırı parametresinin adı
  /// (`max_tokens` veya `max_completion_tokens`).
  final String maxTokensParam;

  /// OpenAI uyumlu uçlarda `response_format: json_object` gönderilsin mi.
  final bool jsonMode;

  /// `AI_PROVIDER` yoksa ya da `off` ise `null` (yapay zekâ kapalı).
  /// Eksik/geçersiz ayar [ArgumentError] fırlatır; sessizce kapanmaz.
  static LlmConfig? fromEnv(Map<String, String> env) {
    final provider = (env['AI_PROVIDER'] ?? '').trim().toLowerCase();
    if (provider.isEmpty || provider == 'off') return null;
    if (!const {'anthropic', 'openai', 'gemini'}.contains(provider)) {
      throw ArgumentError.value(
        provider,
        'AI_PROVIDER',
        'anthropic|openai|gemini|off',
      );
    }
    final model = (env['AI_MODEL'] ?? '').trim();
    final key = (env['AI_API_KEY'] ?? '').trim();
    if (model.isEmpty) throw ArgumentError('AI_MODEL gerekli');
    if (key.isEmpty) throw ArgumentError('AI_API_KEY gerekli');
    final base = (env['AI_BASE_URL'] ?? '').trim();
    final param = (env['AI_MAX_TOKENS_PARAM'] ?? 'max_tokens').trim();
    if (param != 'max_tokens' && param != 'max_completion_tokens') {
      throw ArgumentError.value(param, 'AI_MAX_TOKENS_PARAM');
    }
    return LlmConfig(
      provider: provider,
      model: model,
      apiKey: key,
      baseUrl: base.isEmpty ? null : base,
      maxTokensParam: param,
      jsonMode: env['AI_JSON_MODE'] == '1',
    );
  }

  /// Anahtar günlüğe/hataya sızmasın.
  @override
  String toString() => 'LlmConfig($provider, $model, anahtar: gizli)';

  LlmClient build({
    http.Client? client,
    Duration? timeout,
    Future<void> Function(Duration)? delay,
  }) {
    final options = LlmHttpOptions(
      client: client ?? http.Client(),
      timeout: timeout ?? const Duration(seconds: 90),
      delay: delay ?? (d) => Future<void>.delayed(d),
    );
    return switch (provider) {
      'anthropic' => AnthropicLlmClient(config: this, options: options),
      'gemini' => GeminiLlmClient(config: this, options: options),
      _ => OpenAiCompatibleLlmClient(config: this, options: options),
    };
  }
}

/// Ortak HTTP seçenekleri (istemci, zaman aşımı, yeniden deneme).
class LlmHttpOptions {
  const LlmHttpOptions({
    required this.client,
    required this.timeout,
    required this.delay,
    this.maxRetries = 2,
  });

  final http.Client client;
  final Duration timeout;
  final Future<void> Function(Duration) delay;
  final int maxRetries;
}

Uri _endpoint(String? configured, String fallback, String path) {
  final base = Uri.parse(configured ?? fallback);
  final loopback = base.host == 'localhost' || base.host == '127.0.0.1';
  if (base.host.isEmpty ||
      !(base.scheme == 'https' || (base.scheme == 'http' && loopback))) {
    throw ArgumentError.value(configured, 'AI_BASE_URL', 'https gerekir');
  }
  final prefix = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(path: '$prefix$path');
}

Future<Map<String, Object?>> _postJson(
  LlmHttpOptions options,
  Uri url,
  Map<String, String> headers,
  Map<String, Object?> body,
) async {
  LlmException? last;
  for (var attempt = 0; attempt <= options.maxRetries; attempt++) {
    if (attempt > 0) {
      await options.delay(Duration(seconds: 1 << attempt));
    }
    try {
      final response = await options.client
          .post(
            url,
            headers: {'Content-Type': 'application/json', ...headers},
            body: jsonEncode(body),
          )
          .timeout(options.timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, Object?>) return decoded;
        throw const LlmException('yanıt nesne değil');
      }
      // Yanıt gövdesi anahtar içermez ama uzun olabilir; kısaltılır.
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      last = LlmException(
        text.length > 300 ? text.substring(0, 300) : text,
        statusCode: response.statusCode,
      );
    } on LlmException {
      rethrow;
    } on TimeoutException {
      last = const LlmException('zaman aşımı');
    } on FormatException {
      throw const LlmException('yanıt JSON değil');
    } on Exception catch (error) {
      last = LlmException('bağlantı hatası: ${error.runtimeType}');
    }
    if (!last.retryable) throw last;
  }
  throw last!;
}

int _int(Object? v) => v is int ? v : 0;

class AnthropicLlmClient implements LlmClient {
  AnthropicLlmClient({required LlmConfig config, required this._options})
    : _config = config,
      _url = _endpoint(
        config.baseUrl,
        'https://api.anthropic.com',
        '/v1/messages',
      );

  final LlmConfig _config;
  final LlmHttpOptions _options;
  final Uri _url;

  @override
  String get provider => 'anthropic';
  @override
  String get model => _config.model;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final json = await _postJson(
      _options,
      _url,
      {'x-api-key': _config.apiKey, 'anthropic-version': '2023-06-01'},
      {
        'model': _config.model,
        'max_tokens': request.maxTokens,
        'system': request.system,
        'messages': [
          {'role': 'user', 'content': request.user},
        ],
      },
    );
    if (json['stop_reason'] == 'refusal') {
      throw const LlmException('model yanıtı reddetti', refused: true);
    }
    final content = json['content'];
    final text = content is List
        ? content
              .whereType<Map<String, Object?>>()
              .where((b) => b['type'] == 'text')
              .map((b) => b['text'])
              .whereType<String>()
              .join()
        : '';
    final usage = json['usage'];
    return LlmResponse(
      text: text,
      inputTokens: usage is Map ? _int(usage['input_tokens']) : 0,
      outputTokens: usage is Map ? _int(usage['output_tokens']) : 0,
      model: _config.model,
    );
  }
}

class OpenAiCompatibleLlmClient implements LlmClient {
  OpenAiCompatibleLlmClient({required LlmConfig config, required this._options})
    : _config = config,
      _url = _endpoint(
        config.baseUrl,
        'https://api.openai.com/v1',
        '/chat/completions',
      );

  final LlmConfig _config;
  final LlmHttpOptions _options;
  final Uri _url;

  @override
  String get provider => 'openai';
  @override
  String get model => _config.model;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final json = await _postJson(
      _options,
      _url,
      {'Authorization': 'Bearer ${_config.apiKey}'},
      {
        'model': _config.model,
        _config.maxTokensParam: request.maxTokens,
        if (_config.jsonMode) 'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': request.system},
          {'role': 'user', 'content': request.user},
        ],
      },
    );
    final choices = json['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    if (first is! Map) throw const LlmException('yanıtta seçenek yok');
    if (first['finish_reason'] == 'content_filter') {
      throw const LlmException('model yanıtı reddetti', refused: true);
    }
    final message = first['message'];
    final text = message is Map && message['content'] is String
        ? message['content'] as String
        : '';
    final usage = json['usage'];
    return LlmResponse(
      text: text,
      inputTokens: usage is Map ? _int(usage['prompt_tokens']) : 0,
      outputTokens: usage is Map ? _int(usage['completion_tokens']) : 0,
      model: _config.model,
    );
  }
}

class GeminiLlmClient implements LlmClient {
  GeminiLlmClient({required LlmConfig config, required this._options})
    : _config = config,
      _url = _endpoint(
        config.baseUrl,
        'https://generativelanguage.googleapis.com',
        '/v1beta/models/${Uri.encodeComponent(config.model)}:generateContent',
      );

  final LlmConfig _config;
  final LlmHttpOptions _options;
  final Uri _url;

  @override
  String get provider => 'gemini';
  @override
  String get model => _config.model;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final json = await _postJson(
      _options,
      _url,
      {'x-goog-api-key': _config.apiKey},
      {
        'systemInstruction': {
          'parts': [
            {'text': request.system},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': request.user},
            ],
          },
        ],
        'generationConfig': {
          'maxOutputTokens': request.maxTokens,
          'responseMimeType': 'application/json',
        },
      },
    );
    final candidates = json['candidates'];
    final first = candidates is List && candidates.isNotEmpty
        ? candidates.first
        : null;
    if (first is! Map) {
      throw const LlmException('model yanıtı reddetti', refused: true);
    }
    final reason = first['finishReason'];
    if (reason == 'SAFETY' ||
        reason == 'PROHIBITED_CONTENT' ||
        reason == 'BLOCKLIST') {
      throw const LlmException('model yanıtı reddetti', refused: true);
    }
    final content = first['content'];
    final parts = content is Map ? content['parts'] : null;
    final text = parts is List
        ? parts
              .whereType<Map<String, Object?>>()
              .map((p) => p['text'])
              .whereType<String>()
              .join()
        : '';
    final usage = json['usageMetadata'];
    return LlmResponse(
      text: text,
      inputTokens: usage is Map ? _int(usage['promptTokenCount']) : 0,
      outputTokens: usage is Map ? _int(usage['candidatesTokenCount']) : 0,
      model: _config.model,
    );
  }
}
