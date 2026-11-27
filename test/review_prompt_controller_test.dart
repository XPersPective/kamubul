import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/review_prompt_controller.dart';
import 'package:kamubul/ui/premium.dart';
import 'package:kamubul/ui/review_prompt_sheet.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  test('storeReviewUri uses App Store write-review on iOS and Play Store on Android', () {
    final identity = AppIdentity(
      appName: 'KamuBul',
      packageName: 'com.crazypenguin.kamubul',
      appStoreId: '6826592263',
      sourceUrl: 'https://github.com/XPersPective/kamubul',
      privacyPolicyUrl: 'https://xperspective.github.io/kamubul/gizlilik/',
      contactEmail: 'test@example.org',
    );
    expect(
      storeReviewUri(identity, isIos: true).toString(),
      'https://apps.apple.com/app/id6826592263?action=write-review',
    );
    expect(
      storeReviewUri(identity, isIos: false).toString(),
      'https://play.google.com/store/apps/details?id=com.crazypenguin.kamubul',
    );
  });

  test('prompts after 3 positive action points and stops permanently on alreadyReviewed', () {
    final store = SettingsStore();
    final now = DateTime(2026, 11, 27, 12, 0);
    final controller = ReviewPromptController(store: store)..markFirstSeen(now);

    expect(controller.shouldShowPrompt(now), isFalse);
    // 1 Asistan reply (weight 2) is not enough by itself.
    controller.recordPositiveAction(weight: 2);
    expect(controller.shouldShowPrompt(now), isFalse);
    // Saving or opening a listing pushes total to 3 -> eligible!
    controller.recordPositiveAction(weight: 1);
    expect(controller.shouldShowPrompt(now), isTrue);

    controller.markCompleted();
    expect(controller.isCompleted, isTrue);
    expect(controller.shouldShowPrompt(now.add(const Duration(days: 30))), isFalse);

    // Survives controller reload from the same store.
    final reloaded = ReviewPromptController(store: store);
    expect(reloaded.isCompleted, isTrue);
    expect(reloaded.shouldShowPrompt(now.add(const Duration(days: 30))), isFalse);
  });

  test('returning from store after >=6s marks reviewed; quick bounce snoozes 7 days', () {
    final store = SettingsStore();
    var now = DateTime(2026, 11, 27, 12, 0);
    final controller = ReviewPromptController(store: store)
      ..markFirstSeen(now)
      ..recordPositiveAction(weight: 3);

    expect(controller.shouldShowPrompt(now), isTrue);
    controller.markStoreOpened(now, fromPrompt: true);
    // Quick 2-second bounce -> does not mark permanently completed; snoozes 7 days.
    now = now.add(const Duration(seconds: 2));
    expect(controller.onAppResumed(now), isFalse);
    expect(controller.isCompleted, isFalse);
    controller.recordPositiveAction(weight: 3);
    expect(controller.shouldShowPrompt(now.add(const Duration(days: 6))), isFalse);
    expect(controller.shouldShowPrompt(now.add(const Duration(days: 8))), isTrue);

    // Genuine 12-second store visit -> permanently completed!
    now = now.add(const Duration(days: 8));
    controller.markStoreOpened(now, fromPrompt: true);
    now = now.add(const Duration(seconds: 12));
    expect(controller.onAppResumed(now), isTrue);
    expect(controller.isCompleted, isTrue);
    expect(controller.shouldShowPrompt(now.add(const Duration(days: 30))), isFalse);
  });

  test('defer cools down 5 days, needs 3 more actions, and caps total prompts', () {
    final store = SettingsStore();
    var now = DateTime(2026, 11, 27, 12, 0);
    final controller = ReviewPromptController(store: store, maxPrompts: 2)
      ..markFirstSeen(now)
      ..recordPositiveAction(weight: 3);

    expect(controller.shouldShowPrompt(now), isTrue);
    controller.markDeferred(now);
    expect(controller.shouldShowPrompt(now.add(const Duration(days: 4))), isFalse);
    // After 5 days, still needs +3 new positive actions.
    now = now.add(const Duration(days: 5));
    expect(controller.shouldShowPrompt(now), isFalse);
    controller.recordPositiveAction(weight: 3);
    expect(controller.shouldShowPrompt(now), isTrue);

    // Second deferral hits maxPrompts cap.
    controller.markDeferred(now);
    now = now.add(const Duration(days: 30));
    controller.recordPositiveAction(weight: 10);
    expect(controller.shouldShowPrompt(now), isFalse);
  });

  testWidgets('ReviewPromptSheet renders cleanly at narrow 1.3x dark and returns choices', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);

    ReviewPromptChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: premiumTheme(AppTheme.dark(brandColor: const Color(0xFF17659C))),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await showReviewPromptSheet(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('KamuBul işinize yarıyor mu?'), findsOneWidget);
    expect(find.text('Mağazada puan ver ve yorum yaz'), findsOneWidget);
    expect(find.text('Zaten yorum yaptım'), findsOneWidget);
    expect(find.text('Daha sonra'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final rateBtn = find.widgetWithText(
      FilledButton,
      'Mağazada puan ver ve yorum yaz',
    );
    expect(tester.getSize(rateBtn).height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Zaten yorum yaptım'));
    await tester.pumpAndSettle();
    expect(picked, ReviewPromptChoice.alreadyReviewed);
    expect(tester.takeException(), isNull);
  });
}
