import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:kamubul/ads_state.dart';
import 'package:kamubul/data/ad_lifecycle_coordinator.dart';
import 'package:kamubul/data/fullscreen_ad_controllers.dart';
import 'package:kamubul/data/recovering_banner_controller.dart';
import 'package:kamubul/data/subscription_check.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

final class _FakeStore implements StoreAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeBanner extends BannerAd {
  _FakeBanner(BannerAdListener listener)
    : super(
        adUnitId: 'test',
        size: AdSize.banner,
        listener: listener,
        request: const AdRequest(),
      );

  int requests = 0;
  int disposals = 0;

  @override
  Future<void> load() async {
    requests++;
    listener.onAdLoaded?.call(this);
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  test('isAppForeground treats cold-start null and resumed as foreground', () {
    expect(isAppForeground(null), isTrue);
    expect(isAppForeground(AppLifecycleState.resumed), isTrue);
    expect(isAppForeground(AppLifecycleState.inactive), isFalse);
    expect(isAppForeground(AppLifecycleState.hidden), isFalse);
    expect(isAppForeground(AppLifecycleState.paused), isFalse);
    expect(isAppForeground(AppLifecycleState.detached), isFalse);
  });

  testWidgets(
    'cold start with null lifecycleState starts ads immediately after first frame',
    (tester) async {
      final now = DateTime(2026, 11, 27, 12, 0);
      final store = SettingsStore()
        ..setInt(
          'kamubul.ads.first',
          now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        )
        ..setInt('kamubul.ads.sessions', 5)
        ..setInt('kamubul.onboarded', 1);
      final pro = ProController(
        store: store,
        repository: PurchaseRepository(adapter: _FakeStore()),
        now: () => now,
      )..load();
      final policy = AdPolicy(
        minDaysForFullscreen: adFreeTrialDays,
        minDaysForRewarded: adFreeTrialDays,
      );
      final sessionCounted = startAdSession(policy, store, now);
      AppLifecycleState? lifecycle;
      bool isForeground() => isAppForeground(lifecycle);
      final banners = <_FakeBanner>[];
      final banner = RecoveringBannerController(
        policy: policy,
        isForeground: isForeground,
        createBanner: (listener) {
          final b = _FakeBanner(listener);
          banners.add(b);
          return b;
        },
      );
      final rewarded = RecoveringRewardedAdManager(
        policy: policy,
        isForeground: isForeground,
        loadAd: () async => null,
      );
      final interstitial = WorkingInterstitialAdManager(
        policy: policy,
        isForeground: isForeground,
        loadAd: () async => null,
      );
      final appOpen = WorkingAppOpenAdManager(
        policy: policy,
        now: () => now,
        loadAd: () async => null,
      );
      var consentCalls = 0;
      var uiNotifications = 0;
      final coordinator = AdLifecycleCoordinator(
        store: store,
        pro: pro,
        policy: policy,
        banner: banner,
        rewarded: rewarded,
        interstitial: interstitial,
        appOpen: appOpen,
        adsAvailable: true,
        isForeground: isForeground,
        verifySubscription: () async => true,
        syncTrial: () async => true,
        initializeConsent: () async {
          consentCalls++;
          return true;
        },
        onStateChanged: () => uiNotifications++,
        saveAdState: () => saveAds(policy, store),
        now: () => now,
      );

      coordinator.start(trialSynced: true, sessionCounted: sessionCounted);
      coordinator.onFirstFrameReady();
      await tester.pump();
      await tester.pump();

      expect(consentCalls, 1);
      expect(coordinator.adsStarted, isTrue);
      expect(banners, hasLength(1));
      expect(banner.shouldShow, isTrue);
      expect(uiNotifications, greaterThanOrEqualTo(1));

      coordinator.dispose();
      banner.dispose();
      pro.dispose();
    },
  );

  testWidgets(
    'expired paid Pro recovers after startup failure and on resume, then starts ads',
    (tester) async {
      var now = DateTime(2026, 11, 27, 12, 0);
      final store = SettingsStore()
        ..setBool(ProSettingsKeys.proLifetime, true)
        ..setInt(
          'kamubul.ads.first',
          now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        )
        ..setInt('kamubul.ads.sessions', 5);
      final pro = ProController(
        store: store,
        repository: PurchaseRepository(adapter: _FakeStore()),
        now: () => now,
      )..load();
      final policy = AdPolicy(
        minDaysForFullscreen: adFreeTrialDays,
        minDaysForRewarded: adFreeTrialDays,
      );
      final sessionCounted = startAdSession(policy, store, now);
      var storeAvailable = false;
      var activeOwned = <String>{};
      final banners = <_FakeBanner>[];
      final banner = RecoveringBannerController(
        policy: policy,
        isForeground: () => true,
        createBanner: (listener) {
          final b = _FakeBanner(listener);
          banners.add(b);
          return b;
        },
      );
      final rewarded = RecoveringRewardedAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final interstitial = WorkingInterstitialAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final appOpen = WorkingAppOpenAdManager(
        policy: policy,
        now: () => now,
        loadAd: () async => null,
      );
      final coordinator = AdLifecycleCoordinator(
        store: store,
        pro: pro,
        policy: policy,
        banner: banner,
        rewarded: rewarded,
        interstitial: interstitial,
        appOpen: appOpen,
        adsAvailable: true,
        isForeground: () => true,
        verifySubscription: () => verifySubscription(
          pro,
          store,
          activeProducts: () async {
            if (!storeAvailable) throw StateError('play_offline');
            return activeOwned;
          },
          restorableProducts: const {proMonthlyProductId},
        ),
        syncTrial: () async => true,
        initializeConsent: () async => true,
        onStateChanged: () {},
        saveAdState: () => saveAds(policy, store),
        now: () => now,
        subscriptionRetryDelay: const Duration(seconds: 15),
        paidProRecheckInterval: const Duration(seconds: 30),
      );

      // Cold start: store unavailable -> cached Pro stays, no ads yet.
      coordinator.start(trialSynced: true, sessionCounted: sessionCounted);
      coordinator.onFirstFrameReady();
      await tester.pump();
      expect(pro.isPro, isTrue);
      expect(banners, isEmpty);

      // 15s later: store responds that subscription is expired -> Pro cleared & ads start!
      storeAvailable = true;
      now = now.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();

      expect(pro.isPro, isFalse);
      expect(pro.hasLifetimePurchase, isFalse);
      expect(policy.isPro, isFalse);
      expect(coordinator.adsStarted, isTrue);
      expect(banners, hasLength(1));
      expect(banner.shouldShow, isTrue);

      coordinator.dispose();
      banner.dispose();
      pro.dispose();
    },
  );

  testWidgets(
    'active paid Pro that expires while app stays in memory is revoked on resume',
    (tester) async {
      var now = DateTime(2026, 11, 27, 12, 0);
      final store = SettingsStore()
        ..setBool(ProSettingsKeys.proLifetime, true)
        ..setInt(
          'kamubul.ads.first',
          now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        )
        ..setInt('kamubul.ads.sessions', 5);
      final pro = ProController(
        store: store,
        repository: PurchaseRepository(adapter: _FakeStore()),
        now: () => now,
      )..load();
      final policy = AdPolicy(
        minDaysForFullscreen: adFreeTrialDays,
        minDaysForRewarded: adFreeTrialDays,
      );
      final sessionCounted = startAdSession(policy, store, now);
      var owned = <String>{proMonthlyProductId};
      final banners = <_FakeBanner>[];
      final banner = RecoveringBannerController(
        policy: policy,
        isForeground: () => true,
        createBanner: (listener) {
          final b = _FakeBanner(listener);
          banners.add(b);
          return b;
        },
      );
      final rewarded = RecoveringRewardedAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final interstitial = WorkingInterstitialAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final appOpen = WorkingAppOpenAdManager(
        policy: policy,
        now: () => now,
        loadAd: () async => null,
      );
      final coordinator = AdLifecycleCoordinator(
        store: store,
        pro: pro,
        policy: policy,
        banner: banner,
        rewarded: rewarded,
        interstitial: interstitial,
        appOpen: appOpen,
        adsAvailable: true,
        isForeground: () => true,
        verifySubscription: () => verifySubscription(
          pro,
          store,
          activeProducts: () async => owned,
          restorableProducts: const {proMonthlyProductId},
        ),
        syncTrial: () async => true,
        initializeConsent: () async => true,
        onStateChanged: () {},
        saveAdState: () => saveAds(policy, store),
        now: () => now,
        paidProRecheckInterval: const Duration(seconds: 30),
      );

      coordinator.start(trialSynced: true, sessionCounted: sessionCounted);
      coordinator.onFirstFrameReady();
      await tester.pump();
      expect(pro.isPro, isTrue);
      expect(banners, isEmpty);

      // Subscription expires 1 minute later; user resumes app.
      owned = {};
      now = now.add(const Duration(minutes: 1));
      coordinator.onResume();
      await tester.pump();
      await tester.pump();

      expect(pro.isPro, isFalse);
      expect(policy.isPro, isFalse);
      expect(banners, hasLength(1));
      expect(banner.shouldShow, isTrue);

      coordinator.dispose();
      banner.dispose();
      pro.dispose();
    },
  );

  testWidgets(
    'temporary 24h Pro expiry timer revokes Pro and starts ads automatically',
    (tester) async {
      var now = DateTime(2026, 11, 27, 12, 0);
      final store = SettingsStore()
        ..setInt(
          'kamubul.ads.first',
          now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        )
        ..setInt('kamubul.ads.sessions', 5);
      final pro = ProController(
        store: store,
        repository: PurchaseRepository(adapter: _FakeStore()),
        now: () => now,
      )..load();
      pro.grantTemporaryPro(const Duration(seconds: 10));
      final policy = AdPolicy(
        minDaysForFullscreen: adFreeTrialDays,
        minDaysForRewarded: adFreeTrialDays,
      );
      final sessionCounted = startAdSession(policy, store, now);
      final banners = <_FakeBanner>[];
      final banner = RecoveringBannerController(
        policy: policy,
        isForeground: () => true,
        createBanner: (listener) {
          final b = _FakeBanner(listener);
          banners.add(b);
          return b;
        },
      );
      final rewarded = RecoveringRewardedAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final interstitial = WorkingInterstitialAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final appOpen = WorkingAppOpenAdManager(
        policy: policy,
        now: () => now,
        loadAd: () async => null,
      );
      var stateChanges = 0;
      final coordinator = AdLifecycleCoordinator(
        store: store,
        pro: pro,
        policy: policy,
        banner: banner,
        rewarded: rewarded,
        interstitial: interstitial,
        appOpen: appOpen,
        adsAvailable: true,
        isForeground: () => true,
        verifySubscription: () async => true,
        syncTrial: () async => true,
        initializeConsent: () async => true,
        onStateChanged: () => stateChanges++,
        saveAdState: () => saveAds(policy, store),
        now: () => now,
      );

      coordinator.start(trialSynced: true, sessionCounted: sessionCounted);
      coordinator.onFirstFrameReady();
      await tester.pump();
      expect(pro.isPro, isTrue);
      expect(banners, isEmpty);

      now = now.add(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();

      expect(pro.isPro, isFalse);
      expect(policy.isPro, isFalse);
      expect(banners, hasLength(1));
      expect(banner.shouldShow, isTrue);
      expect(stateChanges, greaterThanOrEqualTo(1));

      coordinator.dispose();
      banner.dispose();
      pro.dispose();
    },
  );

  testWidgets(
    'failed consent retries in foreground and privacy revoke disposes banner',
    (tester) async {
      final now = DateTime(2026, 11, 27, 12, 0);
      final store = SettingsStore()
        ..setInt(
          'kamubul.ads.first',
          now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        )
        ..setInt('kamubul.ads.sessions', 5);
      final pro = ProController(
        store: store,
        repository: PurchaseRepository(adapter: _FakeStore()),
        now: () => now,
      )..load();
      final policy = AdPolicy(
        minDaysForFullscreen: adFreeTrialDays,
        minDaysForRewarded: adFreeTrialDays,
      );
      final sessionCounted = startAdSession(policy, store, now);
      var consentReady = false;
      var consentAttempts = 0;
      final banners = <_FakeBanner>[];
      final banner = RecoveringBannerController(
        policy: policy,
        isForeground: () => true,
        createBanner: (listener) {
          final b = _FakeBanner(listener);
          banners.add(b);
          return b;
        },
      );
      final rewarded = RecoveringRewardedAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final interstitial = WorkingInterstitialAdManager(
        policy: policy,
        isForeground: () => true,
        loadAd: () async => null,
      );
      final appOpen = WorkingAppOpenAdManager(
        policy: policy,
        now: () => now,
        loadAd: () async => null,
      );
      final coordinator = AdLifecycleCoordinator(
        store: store,
        pro: pro,
        policy: policy,
        banner: banner,
        rewarded: rewarded,
        interstitial: interstitial,
        appOpen: appOpen,
        adsAvailable: true,
        isForeground: () => true,
        verifySubscription: () async => true,
        syncTrial: () async => true,
        initializeConsent: () async {
          consentAttempts++;
          return consentReady;
        },
        onStateChanged: () {},
        saveAdState: () => saveAds(policy, store),
        now: () => now,
        consentRetryDelay: const Duration(seconds: 60),
      );

      coordinator.start(trialSynced: true, sessionCounted: sessionCounted);
      coordinator.onFirstFrameReady();
      await tester.pump();
      expect(consentAttempts, 1);
      expect(banners, isEmpty);

      consentReady = true;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(consentAttempts, 2);
      expect(banners, hasLength(1));
      expect(banner.shouldShow, isTrue);

      // Privacy options revoked -> banner disposed.
      coordinator.onPrivacyConsentChanged(false);
      expect(banner.shouldShow, isFalse);
      expect(banners.single.disposals, 1);

      // Privacy options re-allowed -> new banner loaded.
      coordinator.onPrivacyConsentChanged(true);
      await tester.pump();
      expect(banners, hasLength(2));
      expect(banner.shouldShow, isTrue);

      coordinator.dispose();
      banner.dispose();
      pro.dispose();
    },
  );
}
