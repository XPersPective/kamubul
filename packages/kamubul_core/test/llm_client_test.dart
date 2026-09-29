import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

LlmClient _build(LlmConfig config, MockClientHandler handler) =>
    config.build(client: MockClient(handler), delay: (_) async {});

const _request = LlmRequest(
  system: 'sistem',
  user: 'kullanıcı',
  maxTokens: 500,
);

void main() {
  test('Anthropic: istek biçimi ve yanıt ayrıştırma', () async {
    late http.Request seen;
    final client = _build(
      const LlmConfig(
        provider: 'anthropic',
        model: 'claude-opus-5-5',
        apiKey: 'gizli-anahtar',
      ),
      (request) async {
        seen = request;
        return _json({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'thinking', 'thinking': ''},
            {'type': 'text', 'text': '{"a":'},
            {'type': 'text', 'text': '1}'},
          ],
          'usage': {'input_tokens': 120, 'output_tokens': 30},
        });
      },
    );
    final response = await client.complete(_request);
    expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(seen.headers['x-api-key'], 'gizli-anahtar');
    expect(seen.headers['anthropic-version'], '2023-06-01');
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['max_tokens'], 500);
    expect(body['system'], 'sistem');
    expect(body.containsKey('temperature'), isFalse);
    expect(body.containsKey('thinking'), isFalse);
    expect(response.text, '{"a":1}');
    expect(response.inputTokens, 120);
    expect(response.outputTokens, 30);
  });

  test(
    'Anthropic: refusal durumu reddedildi olarak işaretlenir, yeniden denenmez',
    () async {
      var calls = 0;
      final client = _build(
        const LlmConfig(provider: 'anthropic', model: 'm', apiKey: 'k'),
        (request) async {
          calls++;
          return _json({'stop_reason': 'refusal', 'content': [], 'usage': {}});
        },
      );
      await expectLater(
        client.complete(_request),
        throwsA(
          isA<LlmException>().having((e) => e.refused, 'refused', isTrue),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'OpenAI uyumlu: taban adres, başlık ve parametre adı ayarlanabilir',
    () async {
      late http.Request seen;
      final client = _build(
        const LlmConfig(
          provider: 'openai',
          model: 'yerel-model',
          apiKey: 'k',
          baseUrl: 'https://gateway.example/v1',
          maxTokensParam: 'max_completion_tokens',
          jsonMode: true,
        ),
        (request) async {
          seen = request;
          return _json({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': '{"ok":true}'},
              },
            ],
            'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
          });
        },
      );
      final response = await client.complete(_request);
      expect(
        seen.url.toString(),
        'https://gateway.example/v1/chat/completions',
      );
      expect(seen.headers['Authorization'], 'Bearer k');
      final body = jsonDecode(seen.body) as Map<String, Object?>;
      expect(body['max_completion_tokens'], 500);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body['response_format'], {'type': 'json_object'});
      expect((body['messages'] as List).first, {
        'role': 'system',
        'content': 'sistem',
      });
      expect(response.text, '{"ok":true}');
      expect(response.outputTokens, 5);
    },
  );

  test('Gemini: istek biçimi ve yanıt ayrıştırma', () async {
    late http.Request seen;
    final client = _build(
      const LlmConfig(provider: 'gemini', model: 'gemini-x', apiKey: 'g'),
      (request) async {
        seen = request;
        return _json({
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {'text': '{"g":1}'},
                ],
              },
            },
          ],
          'usageMetadata': {'promptTokenCount': 7, 'candidatesTokenCount': 3},
        });
      },
    );
    final response = await client.complete(_request);
    expect(
      seen.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-x:generateContent',
    );
    expect(seen.headers['x-goog-api-key'], 'g');
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect((body['generationConfig'] as Map)['maxOutputTokens'], 500);
    expect(response.text, '{"g":1}');
    expect(response.inputTokens, 7);
  });

  test('429 ve 5xx yeniden denenir, 400 denenmez', () async {
    var calls = 0;
    final retrying = _build(
      const LlmConfig(provider: 'openai', model: 'm', apiKey: 'k'),
      (request) async {
        calls++;
        if (calls < 3) return _json({'error': 'yoğun'}, calls == 1 ? 429 : 503);
        return _json({
          'choices': [
            {
              'message': {'content': 'ok'},
            },
          ],
        });
      },
    );
    expect((await retrying.complete(_request)).text, 'ok');
    expect(calls, 3);

    calls = 0;
    final badRequest = _build(
      const LlmConfig(provider: 'openai', model: 'm', apiKey: 'k'),
      (request) async {
        calls++;
        return _json({'error': 'geçersiz'}, 400);
      },
    );
    await expectLater(
      badRequest.complete(_request),
      throwsA(isA<LlmException>()),
    );
    expect(calls, 1);
  });

  test('ortam değişkeninden ayar: kapalı, geçerli ve hatalı durumlar', () {
    expect(LlmConfig.fromEnv({}), isNull);
    expect(LlmConfig.fromEnv({'AI_PROVIDER': 'off'}), isNull);
    final config = LlmConfig.fromEnv({
      'AI_PROVIDER': 'Anthropic',
      'AI_MODEL': 'claude-opus-5-5',
      'AI_API_KEY': 'sk-gizli',
    })!;
    expect(config.provider, 'anthropic');
    expect(config.toString(), isNot(contains('sk-gizli')));
    expect(
      () => LlmConfig.fromEnv({'AI_PROVIDER': 'anthropic', 'AI_MODEL': 'm'}),
      throwsArgumentError,
    );
    expect(
      () => LlmConfig.fromEnv({
        'AI_PROVIDER': 'bilinmeyen',
        'AI_MODEL': 'm',
        'AI_API_KEY': 'k',
      }),
      throwsArgumentError,
    );
    expect(
      () => LlmConfig.fromEnv({
        'AI_PROVIDER': 'openai',
        'AI_MODEL': 'm',
        'AI_API_KEY': 'k',
        'AI_BASE_URL': 'http://evil.example',
      })!.build(),
      throwsArgumentError,
    );
  });
}
