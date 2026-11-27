import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/data/fullscreen_ad_controllers.dart';
import 'package:napp_ads/napp_ads.dart';

final class _FakeFullscreenAd implements FullscreenAdHandle {
  _FakeFullscreenAd({this.showResult = true});

  final bool showResult;
  int showCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> show() async {
    showCalls++;
    return showResult;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

final class _FakeRewardedAd implements RewardedAdHandle {
  _FakeRewardedAd({this.earn = true, this.failToShow = false});

  final bool earn;
  final bool failToShow;
  int showCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> show({
    required void Function() onEarned,
    required void Function() onDismissed,
    required void Function() onFailedToShow,
  }) async {
    showCalls++;
    if (failToShow) {
      onFailedToShow();
      return;
    }
    if (earn) onEarned();
    onDismissed();
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

AdPolicy _eligiblePolicy(DateTime now) {
  final policy = AdPolicy(minDaysForFullscreen: 1, minDaysForRewarded: 1)
    ..setSdkReady(true)
    ..setOnboardingCompleted(true);
  policy.restore(
    AdPolicySnapshot(
      firstLaunchAt: now.subtract(const Duration(days: 2)),
      sessionCount: 5,
      lastAppOpenAt: null,
      lastFullscreenAt: null,
      lastRewardedDay: null,
    ),
  );
  return policy;
}

void main() {
  test('app-open manager awaits load, calls show(), and records impression', () async {
    final now = DateTime(2026, 11, 27, 10, 0);
    final policy = _eligiblePolicy(now);
    final ad = _FakeFullscreenAd();
    var shownCallbacks = 0;
    final manager = WorkingAppOpenAdManager(
      policy: policy,
      now: () => now,
      loadAd: () async => ad,
    );

    final shown = await manager.loadAndShowIfAllowed(
      canShowNow: () => true,
      onShown: () => shownCallbacks++,
    );

    expect(shown, isTrue);
    expect(ad.showCalls, 1);
    expect(shownCallbacks, 1);
    expect(policy.snapshot().lastAppOpenAt, now);
    expect(policy.canShowAppOpen(now), isFalse);
  });

  test('app-open ad loaded after eligibility changes is disposed, not shown', () async {
    final now = DateTime(2026, 11, 27, 10, 0);
    final policy = _eligiblePolicy(now);
    final ad = _FakeFullscreenAd();
    final pending = Completer<FullscreenAdHandle?>();
    var foreground = true;
    final manager = WorkingAppOpenAdManager(
      policy: policy,
      now: () => now,
      loadAd: () => pending.future,
    );

    final future = manager.loadAndShowIfAllowed(canShowNow: () => foreground);
    foreground = false;
    pending.complete(ad);

    expect(await future, isFalse);
    expect(ad.showCalls, 0);
    expect(ad.disposeCalls, 1);
    expect(policy.snapshot().lastAppOpenAt, isNull);
  });

  testWidgets('interstitial only loads when eligible, calls show(), and retries on failure', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 27, 10, 0);
    final policy = AdPolicy(minDaysForFullscreen: 1, minDaysForRewarded: 1)
      ..setSdkReady(true);
    policy.restore(
      AdPolicySnapshot(
        firstLaunchAt: now.subtract(const Duration(days: 2)),
        sessionCount: 1, // Below minSessionsForFullscreen (5).
        lastAppOpenAt: null,
        lastFullscreenAt: null,
        lastRewardedDay: null,
      ),
    );
    var loads = 0;
    final ads = <_FakeFullscreenAd>[];
    var shouldFail = true;
    final manager = WorkingInterstitialAdManager(
      policy: policy,
      isForeground: () => true,
      now: () => now,
      retryDelay: const Duration(minutes: 2),
      loadAd: () async {
        loads++;
        if (shouldFail) return null;
        final ad = _FakeFullscreenAd();
        ads.add(ad);
        return ad;
      },
    );
    addTearDown(manager.dispose);

    // Not eligible yet: must not waste an AdMob request.
    await manager.preloadIfEligible();
    expect(loads, 0);

    // Once session guard is met, first load fails and schedules a 2-minute retry.
    policy.restore(
      AdPolicySnapshot(
        firstLaunchAt: now.subtract(const Duration(days: 2)),
        sessionCount: 5,
        lastAppOpenAt: null,
        lastFullscreenAt: null,
        lastRewardedDay: null,
      ),
    );
    await manager.preloadIfEligible();
    expect(loads, 1);
    expect(manager.isLoaded, isFalse);

    shouldFail = false;
    await tester.pump(const Duration(minutes: 2));
    expect(loads, 2);
    expect(manager.isLoaded, isTrue);

    var shownCallbacks = 0;
    final shown = await manager.showIfAllowed(
      onShown: () => shownCallbacks++,
    );
    expect(shown, isTrue);
    expect(ads.single.showCalls, 1);
    expect(shownCallbacks, 1);
    expect(policy.snapshot().lastFullscreenAt, now);

    // Pro clears a preloaded interstitial without showing it.
    now = now.add(const Duration(minutes: 5));
    await manager.preloadIfEligible();
    expect(manager.isLoaded, isTrue);
    final second = ads.last;
    manager.clear();
    expect(second.disposeCalls, 1);
    expect(manager.isLoaded, isFalse);
  });

  testWidgets('rewarded manager recovers after failed load and settles reward cleanly', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 27, 10, 0);
    final policy = _eligiblePolicy(now);
    var loads = 0;
    var shouldFail = true;
    final ads = <_FakeRewardedAd>[];
    final manager = RecoveringRewardedAdManager(
      policy: policy,
      isForeground: () => true,
      now: () => now,
      retryDelay: const Duration(minutes: 2),
      loadAd: () async {
        loads++;
        if (shouldFail) return null;
        final ad = _FakeRewardedAd(earn: true);
        ads.add(ad);
        return ad;
      },
    );
    addTearDown(manager.dispose);

    await manager.load();
    expect(loads, 1);
    expect(manager.isLoaded, isFalse);

    shouldFail = false;
    await tester.pump(const Duration(minutes: 2));
    expect(loads, 2);
    expect(manager.isLoaded, isTrue);

    bool? earnedResult;
    await manager.showIfAllowed(now, onSettled: (earned) => earnedResult = earned);
    expect(earnedResult, isTrue);
    expect(ads.single.showCalls, 1);
    expect(policy.canShowRewarded(now), isFalse);
  });

  test('failed show does not record fullscreen or rewarded impressions', () async {
    final now = DateTime(2026, 11, 27, 10, 0);
    final policy = _eligiblePolicy(now);
    final appOpen = WorkingAppOpenAdManager(
      policy: policy,
      now: () => now,
      loadAd: () async => _FakeFullscreenAd(showResult: false),
    );
    expect(await appOpen.loadAndShowIfAllowed(canShowNow: () => true), isFalse);
    expect(policy.snapshot().lastAppOpenAt, isNull);

    var loads = 0;
    final rewarded = RecoveringRewardedAdManager(
      policy: policy,
      isForeground: () => true,
      now: () => now,
      loadAd: () async {
        loads++;
        return loads == 1 ? _FakeRewardedAd(failToShow: true) : null;
      },
    );
    addTearDown(rewarded.dispose);
    await rewarded.load();
    bool? earned;
    await rewarded.showIfAllowed(now, onSettled: (v) => earned = v);
    expect(earned, isFalse);
    expect(policy.canShowRewarded(now), isTrue);
  });
}
