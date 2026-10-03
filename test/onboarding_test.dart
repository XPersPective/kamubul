import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ui/onboarding_page.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:napp_core/napp_core.dart';
import 'package:kamubul/ui/premium.dart';

Future<void> press(WidgetTester tester, String label) async {
  final button = find.text(label);
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('steps expose accessible headings and labelled 48dp targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const titles = [
      'Resmî kamu ilanları, tek yerde',
      'Nerede iş arıyorsunuz?',
      'Sizin şartlarınız',
      'Hazırsınız',
    ];
    const brand = Color(0xFF17659C);
    try {
      for (final theme in [
        premiumTheme(AppTheme.light(brandColor: brand)),
        premiumTheme(AppTheme.dark(brandColor: brand)),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: theme,
            home: OnboardingPage(onCreate: (_) async {}, onDone: () {}),
          ),
        );
        for (var step = 0; step < titles.length; step++) {
          final heading = tester.getSemantics(find.text(titles[step]));
          expect(
            heading,
            matchesSemantics(
              label: 'Adım ${step + 1} / 4: ${titles[step]}',
              isHeader: true,
              isLiveRegion: true,
            ),
          );
          final action = step == 3 ? 'İlanları bul' : 'Devam';
          await tester.ensureVisible(find.text(action));
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (step < 3) await press(tester, action);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'skip completes without creating a search or requesting permission',
    (tester) async {
      var saves = 0, done = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingPage(
            onCreate: (_) async => saves++,
            onDone: () => done++,
          ),
        ),
      );
      await press(tester, 'Atla');
      expect(saves, 0);
      expect(done, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile age carries current reference date and validates before save',
    (tester) async {
      Map<String, String>? saved;
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingPage(
            onCreate: (filters) async => saved = filters,
            onDone: () => done++,
          ),
        ),
      );
      await press(tester, 'Devam');
      await tester.enterText(find.byType(TextField), 'Ankara');
      await press(tester, 'Devam');
      await tester.enterText(find.byType(TextField), '15');
      await press(tester, 'Devam');
      await tester.enterText(find.byType(TextField), 'p3');
      await press(tester, 'İlanları bul');
      expect(saved, isNull);
      expect(done, 0);
      expect(
        find.text('Yaşınızı 16–80 arasında tam sayı olarak girin.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await press(tester, 'Geri');
      await tester.enterText(find.byType(TextField), '30');
      await press(tester, 'Devam');
      await press(tester, 'İlanları bul');
      expect(done, 1);
      expect(saved!['yasTarih'], dayKey(wallClock(DateTime.now())));
      expect(saved!['kpss'], 'P3');
      final criteria = SearchCriteria.fromLegacy(saved!).values;
      expect(criteria['age'], 30);
      expect(criteria['cities'], ['Ankara']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save is single flight and failure preserves fields for retry', (
    tester,
  ) async {
    final pending = Completer<void>();
    var attempts = 0, done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          onCreate: (_) {
            attempts++;
            return attempts == 1 ? pending.future : Future.value();
          },
          onDone: () => done++,
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await press(tester, 'Devam');
    }
    await tester.enterText(find.byType(TextField), 'p93');
    await press(tester, 'İlanları bul');
    expect(attempts, 1);
    expect(find.text('Kaydediliyor…'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Atla'))
          .onPressed,
      isNull,
    );
    pending.completeError(Exception('storage unavailable'));
    await tester.pumpAndSettle();
    expect(done, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'p93',
    );
    expect(
      find.text(
        'Bilgiler kaydedilemedi. Yeniden deneyebilir veya atlayabilirsiniz.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await press(tester, 'İlanları bul');
    expect(attempts, 2);
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'city suggestions use shared identities and invalid criteria never save',
    (tester) async {
      Map<String, String>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingPage(
            onCreate: (filters) async => saved = filters,
            onDone: () {},
          ),
        ),
      );
      await press(tester, 'Devam');
      await tester.enterText(find.byType(TextField), 'Atlantis');
      await press(tester, 'Devam');
      await press(tester, 'Devam');
      await press(tester, 'İlanları bul');
      expect(saved, isNull);
      expect(
        find.text('Geçerli bir şehir adı girin veya alanı boş bırakın.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await press(tester, 'Geri');
      await press(tester, 'Geri');
      await tester.enterText(find.byType(TextField), 'istanbul');
      await tester.pumpAndSettle();
      expect(find.text('İstanbul'), findsOneWidget);
      await press(tester, 'Devam');
      await press(tester, 'Devam');
      await tester.enterText(find.byType(TextField), 'KPSS');
      await press(tester, 'İlanları bul');
      expect(saved, isNull);
      expect(
        find.text('KPSS puan türünü P3, P93 veya P94 biçiminde girin.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.enterText(find.byType(TextField), 'p94');
      await press(tester, 'İlanları bul');
      expect(saved!['sehir'], 'İstanbul');
      expect(saved!['kpss'], 'P94');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all four steps remain usable at 320px, 1.3x text with keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.3),
              viewInsets: const EdgeInsets.only(bottom: 300),
            ),
            child: child!,
          ),
          home: OnboardingPage(onCreate: (_) async {}, onDone: () {}),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await press(tester, 'Devam');
        expect(tester.takeException(), isNull);
      }
      await press(tester, 'İlanları bul');
      expect(tester.takeException(), isNull);
    },
  );
}
