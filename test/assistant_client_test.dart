import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/assistant_client.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  test('kısa/uzun mesaj ağa hiç gitmez', () async {
    var calls = 0;
    final client = AssistantClient(
      store: SettingsStore(),
      baseUrl: 'https://api.test',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(client.ask('ab'), throwsA(isA<AssistantException>()));
    await expectLater(
      client.ask('a' * 301),
      throwsA(isA<AssistantException>()),
    );
    expect(calls, 0);
  });

  test('kriter yanıtı çözülür; kurulum kimliği kalıcıdır', () async {
    final store = SettingsStore();
    final bodies = <Map<String, dynamic>>[];
    final client = AssistantClient(
      store: store,
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'intent': 'criteria',
            'reply': 'Hazır',
            'criteria': {
              'version': 2,
              'cities': ['Ankara'],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final reply = await client.ask('Ankara lisans ilanları');
    expect(reply.intent, 'criteria');
    expect(reply.criteria?['cities'], ['Ankara']);
    await client.ask('İzmir lise ilanları');
    expect(bodies[0]['installationId'], bodies[1]['installationId']);
    expect(bodies[0]['installationId'], matches(RegExp(r'^[a-f0-9]{32}$')));
  });

  test('429 ve sunucu hatası kullanıcıya anlaşılır hata verir', () async {
    for (final status in [429, 502]) {
      final client = AssistantClient(
        store: SettingsStore(),
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('{}', status)),
      );
      await expectLater(
        client.ask('Ankara lisans ilanları'),
        throwsA(isA<AssistantException>()),
      );
    }
  });
}
