import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul/data/assistant_client.dart';
import 'package:kamubul/ui/assistant_chat.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  testWidgets(
    'aynı ilanın yeni revizyonu eski sohbet metnini yeniden kullanmaz',
    (tester) async {
      final sent = <String>[];
      var loads = 0;
      final client = AssistantClient(
        store: SettingsStore(),
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
          sent.add(
            (jsonDecode(request.body)['listing'] as Map)['text'] as String,
          );
          return http.Response('{"intent":"answer","reply":"Tamam"}', 200);
        }),
      );
      final messages = <ChatMessage>[];
      Future<void> show(int revision) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantChatView(
              client: client,
              messages: messages,
              listingId: 'ilangov:1',
              listingRevision: revision,
              listingTitle: 'Aynı başlık',
              loadListingText: () async {
                loads++;
                return 'Revizyon $revision kaynak metni';
              },
            ),
          ),
        ),
      );
      Future<void> send() async {
        await tester.enterText(find.byType(TextField), 'Yaş şartı nedir?');
        await tester.tap(find.byTooltip('Gönder'));
        await tester.pumpAndSettle();
      }

      await show(1);
      await send();
      await send();
      expect(loads, 1);
      await show(2);
      await send();
      expect(loads, 2);
      expect(sent, [
        'Revizyon 1 kaynak metni',
        'Revizyon 1 kaynak metni',
        'Revizyon 2 kaynak metni',
      ]);
    },
  );

  testWidgets('metni henüz alınmamış ilan sorusu AI hakkı tüketmez', (
    tester,
  ) async {
    var calls = 0;
    final client = AssistantClient(
      store: SettingsStore(),
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantChatView(
            client: client,
            messages: [],
            listingTitle: 'Alım',
            loadListingText: () async => null,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Yaş sınırı var mı?'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('metni henüz hazır değil'), findsOneWidget);
  });

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
