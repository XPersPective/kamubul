import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/assistant_client.dart';
import 'package:kamubul/ui/assistant_chat.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  testWidgets('seçili ilanla soru sorulur, ilan metni sunucuya gider', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    final client = AssistantClient(
      store: SettingsStore(),
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'intent': 'answer',
            'reply': 'Yaş sınırı 35.',
            'criteria': null,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final messages = <ChatMessage>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantChatView(
            client: client,
            messages: messages,
            listingTitle: 'TEST KURUMU - Alım',
            loadListingText: () async => '35 yaşını doldurmamış olmak.',
          ),
        ),
      ),
    );
    expect(find.text('KamuBul Asistan'), findsOneWidget);
    expect(find.text('Yaş sınırı var mı?'), findsOneWidget);
    expect(sent, isNull); // Opening the assistant never consumes a message.
    await tester.tap(find.text('Yaş sınırı var mı?'));
    await tester.pumpAndSettle();
    expect(find.text('Yaş sınırı 35.'), findsOneWidget);
    expect(sent?['mode'], 'chat');
    expect((sent?['listing'] as Map)['text'], contains('35 yaşını'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ilan seçili değilken kriter yanıtı kaydet düğmesi gösterir', (
    tester,
  ) async {
    Map<String, Object?>? saved;
    final client = AssistantClient(
      store: SettingsStore(),
      baseUrl: 'https://api.test',
      client: MockClient(
        (_) async => http.Response(
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
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantChatView(
            client: client,
            messages: [],
            criteriaSummary: (c) => 'şehir: Ankara',
            onSaveCriteria: (c) async => saved = c,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Ankara lisans ilanları');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pumpAndSettle();
    expect(find.text('şehir: Ankara'), findsOneWidget);
    await tester.tap(find.text('Aramayı kaydet'));
    expect(saved?['cities'], ['Ankara']);
  });
}
