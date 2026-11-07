import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/assistant_client.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  test('one live question through the actual mobile HTTP client', () async {
    final client = AssistantClient(
      store: SettingsStore(),
      baseUrl: 'https://kamubul-api.devx8585.workers.dev',
    );
    final reply = await client.chat(
      'İlan şartındaki KPSS P3 puanı neyi ifade eder?',
    );
    expect(reply.intent, anyOf('answer', 'clarify'));
    expect(reply.reply.trim(), isNotEmpty);
    expect(reply.reply, startsWith('KPSS P3, lisans'));
    // No personal profile, fabricated listing or paid tier is sent.
    // ignore: avoid_print
    print('LIVE_ASSISTANT_OK ${reply.intent}: ${reply.reply}');
  }, skip: !const bool.fromEnvironment('KAMUBUL_LIVE_SMOKE'));
}
