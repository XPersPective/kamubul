import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';

void restoreAds(AdPolicy policy, SettingsStore store) {
  policy.setOnboardingCompleted(store.getInt('kamubul.onboarded') != null);
  DateTime? date(String key) {
    final ms = store.getInt('kamubul.ads.$key');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  policy.restore(
    AdPolicySnapshot(
      firstLaunchAt: date('first'),
      sessionCount: store.getInt('kamubul.ads.sessions') ?? 0,
      lastAppOpenAt: date('open'),
      lastFullscreenAt: date('fullscreen'),
      lastRewardedDay: date('rewarded'),
    ),
  );
}

void saveAds(AdPolicy policy, SettingsStore store) {
  final state = policy.snapshot();
  void date(String key, DateTime? value) {
    if (value != null) {
      store.setInt('kamubul.ads.$key', value.millisecondsSinceEpoch);
    }
  }

  date('first', state.firstLaunchAt);
  store.setInt('kamubul.ads.sessions', state.sessionCount);
  date('open', state.lastAppOpenAt);
  date('fullscreen', state.lastFullscreenAt);
  date('rewarded', state.lastRewardedDay);
}
