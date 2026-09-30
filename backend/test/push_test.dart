import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_backend/src/push.dart';
import 'package:test/test.dart';

const _message = PushMessage(
  token: 'tok',
  title: 'Ankara',
  body: 'KURUM - İlan',
  url: 'https://kariyerkapisi.gov.tr/IlanDetay?i=1',
);

FcmPushSender _sender(MockClientHandler handler) =>
    FcmPushSender(client: MockClient(handler), projectId: 'proje-1');

void main() {
  test('FCM v1 isteği: adres, gövde ve kanal', () async {
    late http.Request seen;
    final outcome = await _sender((request) async {
      seen = request;
      return http.Response('{"name":"m"}', 200);
    }).send(_message);
    expect(outcome, PushOutcome.sent);
    expect(
      seen.url.toString(),
      'https://fcm.googleapis.com/v1/projects/proje-1/messages:send',
    );
    final body = (jsonDecode(seen.body) as Map)['message'] as Map;
    expect(body['token'], 'tok');
    expect(body['data'], {'url': _message.url, 'kind': 'instant'});
    expect(
      ((body['android'] as Map)['notification'] as Map)['channel_id'],
      'kamubul_alerts',
    );
    expect((body['notification'] as Map)['title'], 'Ankara');
  });

  test('UNREGISTERED ve geçersiz jeton silinecek olarak işaretlenir', () async {
    Future<PushOutcome> run(int status, Object body) =>
        _sender((_) async => http.Response(jsonEncode(body), status))
            .send(_message);

    expect(
      await run(404, {
        'error': {
          'status': 'NOT_FOUND',
          'details': [
            {'errorCode': 'UNREGISTERED'},
          ],
        },
      }),
      PushOutcome.invalidToken,
    );
    expect(
      await run(400, {
        'error': {
          'status': 'INVALID_ARGUMENT',
          'message':
              'The registration token is not a valid FCM registration token',
        },
      }),
      PushOutcome.invalidToken,
    );
  });

  test('geçici hatalar ve ağ hatası failed olur (cihaz silinmez)', () async {
    expect(
      await _sender((_) async => http.Response('{}', 500)).send(_message),
      PushOutcome.failed,
    );
    expect(
      await _sender((_) async => http.Response('{}', 429)).send(_message),
      PushOutcome.failed,
    );
    expect(
      await _sender((_) async => throw http.ClientException('ağ'))
          .send(_message),
      PushOutcome.failed,
    );
    // Başka bir 400 (ör. geçersiz gövde) jetonu geçersiz saymaz.
    expect(
      await _sender(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'INVALID_ARGUMENT',
              'message': 'payload too big',
            },
          }),
          400,
        ),
      ).send(_message),
      PushOutcome.failed,
    );
  });
}
