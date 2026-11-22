import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ads_state.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  test('onboarding marker gates eligible app-open ads across restart', () {
    final store = SettingsStore();
    store.setInt(
      'kamubul.ads.first',
      DateTime(2026, 9, 1).millisecondsSinceEpoch,
    );
    store.setInt('kamubul.ads.sessions', 100);
    final policy = AdPolicy()
      ..setSdkReady(true)
      ..setOnboardingCompleted(true);
    restoreAds(policy, store);
    policy.startSession(DateTime(2026, 10, 3));
    expect(policy.canShowAppOpen(DateTime(2026, 10, 3)), isFalse);
    store.setInt('kamubul.onboarded', 1);
    restoreAds(policy, store);
    policy.startSession(DateTime(2026, 10, 3));
    expect(policy.canShowAppOpen(DateTime(2026, 10, 3)), isTrue);
    policy.setPro(true);
    expect(policy.canShowAppOpen(DateTime(2026, 10, 3)), isFalse);
  });

  test('reklam koruma süresi ve oturum sayısı yeniden açılışta korunur', () {
    final store = SettingsStore();
    final first = AdPolicy()..startSession(DateTime(2026, 9, 1));
    saveAds(first, store);
    final restored = AdPolicy();
    restoreAds(restored, store);
    expect(restored.snapshot().firstLaunchAt, DateTime(2026, 9, 1));
    expect(restored.snapshot().sessionCount, 1);
  });

  test('mevcut deneme ilk kullanım doğrulaması olmadan devam eder', () {
    final first = DateTime(2026, 10, 4);
    final store = SettingsStore()
      ..setInt('kamubul.ads.first', first.millisecondsSinceEpoch)
      ..setInt('kamubul.ads.sessions', 2);
    final policy = AdPolicy();
    final now = DateTime(2026, 10, 5);

    expect(startAdSession(policy, store, now), isTrue);
    expect(policy.snapshot().firstLaunchAt, first);
    expect(policy.snapshot().sessionCount, 3);
    expect(trialDaysLeft(policy, now), 0);
  });

  test('Pro kullanıcıdan hiçbir reklam istenmez', () {
    final policy = AdPolicy()
      ..setPro(true)
      ..setSdkReady(true)
      ..setOnboardingCompleted(true)
      ..startSession(DateTime(2026, 9, 28));
    expect(policy.isPro, isTrue);
    expect(policy.canShowBanner(), isFalse);
    expect(policy.canShowAppOpen(DateTime(2026, 9, 28)), isFalse);
    expect(policy.canShowInterstitial(DateTime(2026, 9, 28)), isFalse);
    expect(policy.canShowRewarded(DateTime(2026, 9, 28)), isFalse);
  });

  test('reklamsız deneme ilk kullanımdan tam 24 saat sonra biter', () {
    final firstUse = DateTime.utc(2026, 10, 4, 16);
    final expiresAt = firstUse.add(const Duration(hours: 24));
    final store = SettingsStore();
    final policy = AdPolicy();
    expect(trialDaysLeft(policy, firstUse), 0);
    policy.startSession(firstUse);
    expect(trialDaysLeft(policy, firstUse), 1);
    saveAds(policy, store);

    final reopened = AdPolicy();
    restoreAds(reopened, store);
    reopened.startSession(firstUse.add(const Duration(hours: 12)));
    expect(trialEndsAt(reopened)?.toUtc(), expiresAt);
    expect(
      trialDaysLeft(reopened, expiresAt.subtract(const Duration(seconds: 1))),
      1,
    );
    expect(trialDaysLeft(reopened, expiresAt), 0);
  });
}
