import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/rate_prompt_state.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  test('puan istemi kaydı saklanır ve geri yüklenir', () {
    final store = SettingsStore();
    final policy = RatePromptPolicy(minDaysAfterInstall: 0);
    restoreRatePrompt(policy, store);
    expect(
      policy.shouldPrompt(DateTime(2026, 9, 28, 8)),
      isFalse,
      reason: 'kurulum izi ve olumlu an yokken istem çıkmaz',
    );

    policy
      ..markFirstSeen(DateTime(2026, 9, 28, 9))
      ..markPositiveMoment();
    expect(policy.shouldPrompt(DateTime(2026, 9, 28, 10)), isTrue);
    saveRatePrompt(policy, store);

    final restored = RatePromptPolicy(minDaysAfterInstall: 0);
    restoreRatePrompt(restored, store);
    final snapshot = restored.snapshot();
    expect(snapshot.firstSeen, DateTime(2026, 9, 28, 9));
    expect(snapshot.promptedAt, [DateTime(2026, 9, 28, 10)]);
    expect(snapshot.positiveMoments, 1);
    expect(
      restored.shouldPrompt(DateTime(2026, 9, 28, 11)),
      isFalse,
      reason: 'iki istem arasında 90 gün yokken tekrar istenmez',
    );
  });

  test('varsayılan kota kurulumdan 14 gün geçmeden istem göstermez', () {
    final policy = RatePromptPolicy()
      ..markFirstSeen(DateTime(2026, 9, 1))
      ..markPositiveMoment();
    expect(policy.shouldPrompt(DateTime(2026, 9, 14)), isFalse);
    expect(policy.shouldPrompt(DateTime(2026, 9, 15)), isTrue);
  });
}
