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

  test('1 günlük reklamsız dönem ilk kurulumdan itibaren 24 saat sürer', () {
    final policy = AdPolicy();
    expect(trialDaysLeft(policy, DateTime(2026, 10, 4)), 0);
    policy.startSession(DateTime(2026, 10, 4));
    expect(trialDaysLeft(policy, DateTime(2026, 10, 4)), 1);
    expect(trialDaysLeft(policy, DateTime(2026, 10, 4, 23, 59)), 1);
    expect(trialDaysLeft(policy, DateTime(2026, 10, 5)), 0);
  });

  test('reklam koruması ve ödüllü reklam eşiği aynı 24 saate uyar', () {
    final policy = AdPolicy(
      minDaysForFullscreen: adFreeTrialDays,
      minDaysForRewarded: adFreeTrialDays,
    );

    expect(adFreeTrialDays, 1);
    expect(policy.minDaysForFullscreen, 1);
    expect(policy.minDaysForRewarded, 1);
  });
}
