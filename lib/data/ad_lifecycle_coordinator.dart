import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

import '../ads_state.dart';
import 'fullscreen_ad_controllers.dart';
import 'recovering_banner_controller.dart';

/// In Flutter, [AppLifecycleState] is `null` before the first platform
/// transition on a cold foreground launch. Only explicit background/inactive
/// states block foreground ad work.
bool isAppForeground(AppLifecycleState? state) =>
    state == null || state == AppLifecycleState.resumed;

/// Coordinates trial verification, subscription expiry re-checks, temporary Pro
/// expiry, UMP/ATT consent recovery, and ad startup across the app lifecycle.
class AdLifecycleCoordinator {
  AdLifecycleCoordinator({
    required this.store,
    required this.pro,
    required this.policy,
    required this.banner,
    required this.rewarded,
    required this.interstitial,
    required this.appOpen,
    required this.adsAvailable,
    required this.isForeground,
    required this.verifySubscription,
    required this.syncTrial,
    required this.initializeConsent,
    required this.onStateChanged,
    required this.saveAdState,
    DateTime Function()? now,
    this.consentRetryDelay = const Duration(seconds: 60),
    this.trialRetryDelay = const Duration(seconds: 30),
    this.subscriptionRetryDelay = const Duration(seconds: 15),
    this.paidProRecheckInterval = const Duration(seconds: 30),
    this.freeRecheckInterval = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final SettingsStore store;
  final ProController pro;
  final AdPolicy policy;
  final RecoveringBannerController banner;
  final RecoveringRewardedAdManager rewarded;
  final WorkingInterstitialAdManager interstitial;
  final WorkingAppOpenAdManager appOpen;
  final bool adsAvailable;
  final bool Function() isForeground;
  final Future<bool> Function() verifySubscription;
  final Future<bool> Function() syncTrial;
  final Future<bool> Function() initializeConsent;
  final VoidCallback onStateChanged;
  final VoidCallback saveAdState;
  final DateTime Function() _now;
  final Duration consentRetryDelay;
  final Duration trialRetryDelay;
  final Duration subscriptionRetryDelay;
  final Duration paidProRecheckInterval;
  final Duration freeRecheckInterval;

  bool _trialSynced = false;
  bool _sessionCounted = false;
  bool _subscriptionChecked = false;
  bool _subscriptionVerified = false;
  DateTime? _lastSubscriptionCheckAt;
  bool _firstFrameReady = false;
  bool _adsStarted = false;
  bool _disposed = false;

  Future<void>? _startingAds;
  Future<void>? _trialRetry;
  Future<void>? _subscriptionInFlight;

  Timer? _trialExpiryTimer;
  Timer? _tempProExpiryTimer;
  Timer? _consentRetryTimer;
  Timer? _trialRetryTimer;
  Timer? _subscriptionRetryTimer;

  bool get adsStarted => _adsStarted;
  bool get subscriptionChecked => _subscriptionChecked;

  bool canUseAds() =>
      adsAvailable &&
      _sessionCounted &&
      _subscriptionChecked &&
      !pro.isPro &&
      trialDaysLeft(policy, _now()) == 0;

  /// Call once during app startup after initial [syncTrial] and [startAdSession].
  void start({
    required bool trialSynced,
    required bool sessionCounted,
    Future<bool>? initialSubscriptionCheck,
  }) {
    _trialSynced = trialSynced;
    _sessionCounted = sessionCounted;
    policy.setPro(pro.isPro);
    pro.addListener(_onProChanged);
    _scheduleTrialExpiry();
    _scheduleTempProExpiry();
    if (!_trialSynced) _scheduleTrialRetry();

    final check = initialSubscriptionCheck ?? verifySubscription();
    _subscriptionInFlight = _trackSubscriptionCheck(check);
    unawaited(_subscriptionInFlight);
  }

  void onFirstFrameReady() {
    if (_disposed) return;
    _firstFrameReady = true;
    startAdsIfEligible();
  }

  void onOnboardingCompleted() {
    if (_disposed) return;
    policy.setOnboardingCompleted(true);
    startAdsIfEligible();
  }

  void onResume() {
    if (_disposed) return;
    if (!_trialSynced) {
      unawaited(_retryTrialNow());
    }
    _maybeReverifySubscription();
    _refreshAdsForPro();
  }

  void onPrivacyConsentChanged(bool allowed) {
    if (_disposed) return;
    policy.setSdkReady(allowed);
    if (!allowed) {
      banner.onPolicyChanged();
      interstitial.clear();
      rewarded.clear();
    } else if (canUseAds()) {
      _adsStarted = true;
      banner.load();
      unawaited(rewarded.load());
      unawaited(interstitial.preloadIfEligible());
    }
    onStateChanged();
  }

  Future<void> _trackSubscriptionCheck(Future<bool> check) async {
    var verified = false;
    try {
      verified = await check;
    } on Object {
      verified = false;
    } finally {
      _subscriptionInFlight = null;
    }
    if (_disposed) return;
    _subscriptionChecked = true;
    _subscriptionVerified = verified;
    _lastSubscriptionCheckAt = _now();
    if (!verified && pro.hasLifetimePurchase) {
      _scheduleSubscriptionRetry();
    } else {
      _subscriptionRetryTimer?.cancel();
      _subscriptionRetryTimer = null;
    }
    _refreshAdsForPro();
  }

  void _maybeReverifySubscription({bool force = false}) {
    if (_disposed || _subscriptionInFlight != null) return;
    if (!force && _subscriptionVerified && _lastSubscriptionCheckAt != null) {
      final interval = pro.hasLifetimePurchase
          ? paidProRecheckInterval
          : freeRecheckInterval;
      if (_now().difference(_lastSubscriptionCheckAt!) < interval) {
        return;
      }
    }
    _subscriptionRetryTimer?.cancel();
    _subscriptionRetryTimer = null;
    _subscriptionInFlight = _trackSubscriptionCheck(verifySubscription());
    unawaited(_subscriptionInFlight);
  }

  void _scheduleSubscriptionRetry() {
    if (_disposed || _subscriptionRetryTimer != null) return;
    _subscriptionRetryTimer = Timer(subscriptionRetryDelay, () {
      _subscriptionRetryTimer = null;
      if (_disposed || !isForeground()) return;
      _maybeReverifySubscription(force: true);
    });
  }

  void _onProChanged() {
    if (_disposed) return;
    _scheduleTempProExpiry();
    _refreshAdsForPro();
  }

  void _refreshAdsForPro() {
    if (_disposed) return;
    final wasPro = policy.isPro;
    final isNowPro = pro.isPro;
    policy.setPro(isNowPro);
    if (isNowPro) {
      _consentRetryTimer?.cancel();
      _consentRetryTimer = null;
      banner.onProChanged();
      interstitial.clear();
      rewarded.clear();
    } else {
      banner.onProChanged();
      if (wasPro) onStateChanged();
      startAdsIfEligible();
    }
  }

  void startAdsIfEligible() {
    if (_disposed ||
        !_firstFrameReady ||
        !isForeground() ||
        !canUseAds() ||
        _startingAds != null) {
      return;
    }
    if (_adsStarted) {
      if (policy.canShowBanner()) {
        banner.load();
        unawaited(rewarded.load());
        unawaited(interstitial.preloadIfEligible());
      }
      return;
    }
    _consentRetryTimer?.cancel();
    _consentRetryTimer = null;
    _startingAds = _startAds().whenComplete(() => _startingAds = null);
    unawaited(_startingAds);
  }

  Future<void> _startAds() async {
    final ready = await initializeConsent();
    if (_disposed) return;
    if (!ready) {
      if (canUseAds()) _scheduleConsentRetry();
      return;
    }
    if (!canUseAds()) return;
    _adsStarted = true;
    policy.setSdkReady(true);
    onStateChanged();
    banner.load();
    unawaited(rewarded.load());
    unawaited(interstitial.preloadIfEligible());
    if (isForeground() && policy.canShowAppOpen(_now())) {
      await appOpen.loadAndShowIfAllowed(
        canShowNow: () => !_disposed && isForeground() && canUseAds(),
        onShown: saveAdState,
      );
    }
  }

  void _scheduleConsentRetry() {
    if (_disposed || _consentRetryTimer != null) return;
    _consentRetryTimer = Timer(consentRetryDelay, () {
      _consentRetryTimer = null;
      startAdsIfEligible();
    });
  }

  void _scheduleTrialExpiry() {
    _trialExpiryTimer?.cancel();
    _trialExpiryTimer = null;
    final end = trialEndsAt(policy);
    if (end == null) return;
    final remaining = end.difference(_now());
    if (remaining <= Duration.zero) return;
    _trialExpiryTimer = Timer(remaining + const Duration(milliseconds: 100), () {
      _trialExpiryTimer = null;
      if (_disposed) return;
      onStateChanged();
      _refreshAdsForPro();
    });
  }

  void _scheduleTempProExpiry() {
    _tempProExpiryTimer?.cancel();
    _tempProExpiryTimer = null;
    final until = pro.tempProUntil;
    if (until == null) return;
    final remaining = until.difference(_now());
    if (remaining <= Duration.zero) return;
    _tempProExpiryTimer = Timer(
      remaining + const Duration(milliseconds: 100),
      () {
        _tempProExpiryTimer = null;
        if (_disposed) return;
        onStateChanged();
        _refreshAdsForPro();
      },
    );
  }

  void _scheduleTrialRetry() {
    if (_disposed || _trialSynced || _trialRetryTimer != null) return;
    _trialRetryTimer = Timer(trialRetryDelay, () {
      _trialRetryTimer = null;
      if (_disposed || _trialSynced || !isForeground()) return;
      unawaited(_retryTrialNow());
    });
  }

  Future<void> _retryTrialNow() {
    if (_trialSynced) return Future<void>.value();
    return _trialRetry ??= _runTrialRetry().whenComplete(
      () => _trialRetry = null,
    );
  }

  Future<void> _runTrialRetry() async {
    final synced = await syncTrial();
    if (_disposed) return;
    _trialSynced = synced;
    if (!synced) {
      _scheduleTrialRetry();
      return;
    }
    _trialRetryTimer?.cancel();
    _trialRetryTimer = null;
    if (_sessionCounted) {
      restoreAds(policy, store);
    } else {
      _sessionCounted = startAdSession(policy, store, _now());
    }
    _scheduleTrialExpiry();
    onStateChanged();
    _refreshAdsForPro();
  }

  void dispose() {
    _disposed = true;
    pro.removeListener(_onProChanged);
    _trialExpiryTimer?.cancel();
    _tempProExpiryTimer?.cancel();
    _consentRetryTimer?.cancel();
    _trialRetryTimer?.cancel();
    _subscriptionRetryTimer?.cancel();
    appOpen.dispose();
    interstitial.dispose();
    rewarded.dispose();
  }
}
