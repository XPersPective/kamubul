import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ads_state.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';

void main() {
  test('reklam koruma süresi ve oturum sayısı yeniden açılışta korunur', () {
    final store = SettingsStore();
    final first = AdPolicy()..startSession(DateTime(2026, 9, 1));
    saveAds(first, store);
    final restored = AdPolicy();
    restoreAds(restored, store);
    expect(restored.snapshot().firstLaunchAt, DateTime(2026, 9, 1));
    expect(restored.snapshot().sessionCount, 1);
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
}
