import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:napp_ads/napp_ads.dart';

/// App-local handle around [AppOpenAd] so tests can verify `show()` and disposal
/// without platform channels.
abstract interface class FullscreenAdHandle {
  Future<bool> show();
  Future<void> dispose();
}

/// App-local handle around [RewardedAd] so tests can verify reward settlement
/// and retry behavior without platform channels.
abstract interface class RewardedAdHandle {
  Future<void> show({
    required void Function() onEarned,
    required void Function() onDismissed,
    required void Function() onFailedToShow,
  });
  Future<void> dispose();
}

final class _AppOpenHandle implements FullscreenAdHandle {
  _AppOpenHandle(this._ad);

  final AppOpenAd _ad;

  @override
  Future<bool> show() {
    final completer = Completer<bool>();
    void finish(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (_) => finish(true),
      onAdFailedToShowFullScreenContent: (ad, _) {
        unawaited(ad.dispose().catchError((Object _) {}));
        finish(false);
      },
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose().catchError((Object _) {}));
        finish(true);
      },
    );
    unawaited(
      _ad.show().catchError((Object _) {
        unawaited(_ad.dispose().catchError((Object _) {}));
        finish(false);
      }),
    );
    return completer.future;
  }

  @override
  Future<void> dispose() => _ad.dispose().catchError((Object _) {});
}

final class _InterstitialHandle implements FullscreenAdHandle {
  _InterstitialHandle(this._ad);

  final InterstitialAd _ad;

  @override
  Future<bool> show() {
    final completer = Completer<bool>();
    void finish(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) => finish(true),
      onAdFailedToShowFullScreenContent: (ad, _) {
        unawaited(ad.dispose().catchError((Object _) {}));
        finish(false);
      },
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose().catchError((Object _) {}));
        finish(true);
      },
    );
    unawaited(
      _ad.show().catchError((Object _) {
        unawaited(_ad.dispose().catchError((Object _) {}));
        finish(false);
      }),
    );
    return completer.future;
  }

  @override
  Future<void> dispose() => _ad.dispose().catchError((Object _) {});
}

final class _RewardedHandle implements RewardedAdHandle {
  _RewardedHandle(this._ad);

  final RewardedAd _ad;

  @override
  Future<void> show({
    required void Function() onEarned,
    required void Function() onDismissed,
    required void Function() onFailedToShow,
  }) async {
    _ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose().catchError((Object _) {}));
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        unawaited(ad.dispose().catchError((Object _) {}));
        onFailedToShow();
      },
    );
    try {
      await _ad.show(onUserEarnedReward: (_, _) => onEarned());
    } on Object {
      unawaited(_ad.dispose().catchError((Object _) {}));
      onFailedToShow();
    }
  }

  @override
  Future<void> dispose() => _ad.dispose().catchError((Object _) {});
}

/// Replaces napp_ads's broken [AppOpenAdManager] (which never awaited load and
/// never called `ad.show()`). Respects the 4-second timeout and foreground/Pro guards.
class WorkingAppOpenAdManager {
  WorkingAppOpenAdManager({
    required this.policy,
    Future<FullscreenAdHandle?> Function()? loadAd,
    DateTime Function()? now,
  }) : _loadAd = loadAd ?? _defaultLoad,
       _now = now ?? DateTime.now;

  final AdPolicy policy;
  final Future<FullscreenAdHandle?> Function() _loadAd;
  final DateTime Function() _now;

  bool _running = false;
  bool _disposed = false;

  static Future<FullscreenAdHandle?> _defaultLoad() {
    final completer = Completer<FullscreenAdHandle?>();
    unawaited(
      AppOpenAd.load(
        adUnitId: AdsConfig.appOpenUnit,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) {
              completer.complete(_AppOpenHandle(ad));
            } else {
              unawaited(ad.dispose().catchError((Object _) {}));
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      ).catchError((Object _) {
        if (!completer.isCompleted) completer.complete(null);
      }),
    );
    return completer.future;
  }

  Future<bool> loadAndShowIfAllowed({
    required bool Function() canShowNow,
    VoidCallback? onShown,
  }) async {
    if (_disposed || _running) return false;
    final start = _now();
    if (!canShowNow() || !policy.canShowAppOpen(start)) return false;
    _running = true;
    try {
      FullscreenAdHandle? ad;
      var timedOut = false;
      try {
        ad = await Future<FullscreenAdHandle?>.value(_loadAd()).timeout(
          policy.appOpenLoadTimeout,
          onTimeout: () {
            timedOut = true;
            return null;
          },
        );
      } on Object {
        return false;
      }
      if (ad == null) return false;
      final now = _now();
      if (_disposed ||
          timedOut ||
          now.difference(start) > policy.appOpenLoadTimeout ||
          !canShowNow() ||
          !policy.canShowAppOpen(now)) {
        await ad.dispose();
        return false;
      }
      final didShow = await ad.show();
      if (didShow) {
        policy.recordFullscreen(_now(), isAppOpen: true);
        onShown?.call();
      }
      return didShow;
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
  }
}

/// Replaces napp_ads's broken [InterstitialAdManager] (which never called
/// `ad.show()` and was loaded on every session without ever being shown).
///
/// Only requests an ad from AdMob when the policy actually allows interstitials,
/// retries failed loads after a cooldown, and disposes immediately on Pro/consent revoke.
class WorkingInterstitialAdManager {
  WorkingInterstitialAdManager({
    required this.policy,
    required this.isForeground,
    Future<FullscreenAdHandle?> Function()? loadAd,
    DateTime Function()? now,
    this.retryDelay = const Duration(minutes: 2),
  }) : _loadAd = loadAd ?? _defaultLoad,
       _now = now ?? DateTime.now;

  final AdPolicy policy;
  final bool Function() isForeground;
  final Future<FullscreenAdHandle?> Function() _loadAd;
  final DateTime Function() _now;
  final Duration retryDelay;

  FullscreenAdHandle? _ad;
  Timer? _retry;
  bool _loading = false;
  bool _showing = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isLoaded => _ad != null;

  static Future<FullscreenAdHandle?> _defaultLoad() {
    final completer = Completer<FullscreenAdHandle?>();
    unawaited(
      InterstitialAd.load(
        adUnitId: AdsConfig.interstitialUnit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) {
              completer.complete(_InterstitialHandle(ad));
            } else {
              unawaited(ad.dispose().catchError((Object _) {}));
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      ).catchError((Object _) {
        if (!completer.isCompleted) completer.complete(null);
      }),
    );
    return completer.future;
  }

  Future<void> preloadIfEligible() async {
    if (_disposed ||
        _loading ||
        _showing ||
        _ad != null ||
        _retry != null ||
        !isForeground() ||
        !policy.canShowInterstitial(_now())) {
      return;
    }
    _loading = true;
    final gen = _generation;
    FullscreenAdHandle? loaded;
    try {
      loaded = await _loadAd();
    } on Object {
      loaded = null;
    } finally {
      _loading = false;
    }
    if (loaded == null) {
      if (!_disposed &&
          gen == _generation &&
          policy.canShowInterstitial(_now())) {
        _retry = Timer(retryDelay, () {
          _retry = null;
          unawaited(preloadIfEligible());
        });
      }
      return;
    }
    if (_disposed || gen != _generation || !policy.canShowBanner()) {
      await loaded.dispose();
      return;
    }
    _ad = loaded;
  }

  Future<bool> showIfAllowed({VoidCallback? onShown}) async {
    if (_disposed || _showing || !isForeground()) return false;
    final now = _now();
    if (!policy.canShowInterstitial(now)) return false;
    final ad = _ad;
    if (ad == null) {
      unawaited(preloadIfEligible());
      return false;
    }
    _ad = null;
    _showing = true;
    try {
      final didShow = await ad.show();
      if (didShow) {
        policy.recordFullscreen(_now(), isAppOpen: false);
        onShown?.call();
      }
      return didShow;
    } finally {
      _showing = false;
    }
  }

  void clear() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    final ad = _ad;
    _ad = null;
    if (ad != null) unawaited(ad.dispose());
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}

/// Subclasses [RewardedAdManager] so [GiftFlow] works unchanged while gaining
/// failure retry, Pro/consent cleanup, and automatic reload.
class RecoveringRewardedAdManager extends RewardedAdManager {
  RecoveringRewardedAdManager({
    required super.policy,
    required this.isForeground,
    Future<RewardedAdHandle?> Function()? loadAd,
    DateTime Function()? now,
    this.retryDelay = const Duration(minutes: 2),
  }) : _loadAd = loadAd ?? _defaultLoad,
       _now = now ?? DateTime.now;

  final bool Function() isForeground;
  final Future<RewardedAdHandle?> Function() _loadAd;
  final DateTime Function() _now;
  final Duration retryDelay;

  RewardedAdHandle? _ad;
  Timer? _retry;
  bool _loading = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isLoaded => _ad != null;

  static Future<RewardedAdHandle?> _defaultLoad() {
    final completer = Completer<RewardedAdHandle?>();
    unawaited(
      RewardedAd.load(
        adUnitId: AdsConfig.rewardedUnit,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) {
              completer.complete(_RewardedHandle(ad));
            } else {
              unawaited(ad.dispose().catchError((Object _) {}));
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      ).catchError((Object _) {
        if (!completer.isCompleted) completer.complete(null);
      }),
    );
    return completer.future;
  }

  @override
  Future<void> load() async {
    if (_disposed ||
        _loading ||
        _ad != null ||
        _retry != null ||
        !isForeground() ||
        !policy.canShowRewarded(_now())) {
      return;
    }
    _loading = true;
    final gen = _generation;
    RewardedAdHandle? loaded;
    try {
      loaded = await _loadAd();
    } on Object {
      loaded = null;
    } finally {
      _loading = false;
    }
    if (loaded == null) {
      if (!_disposed && gen == _generation && policy.canShowRewarded(_now())) {
        _retry = Timer(retryDelay, () {
          _retry = null;
          unawaited(load());
        });
      }
      return;
    }
    if (_disposed || gen != _generation || !policy.canShowBanner()) {
      await loaded.dispose();
      return;
    }
    _ad = loaded;
  }

  @override
  Future<void> showIfAllowed(
    DateTime now, {
    required void Function(bool earned) onSettled,
  }) async {
    if (_disposed || !policy.canShowRewarded(now)) {
      onSettled(false);
      return;
    }
    final ad = _ad;
    if (ad == null) {
      unawaited(load());
      onSettled(false);
      return;
    }
    _ad = null;
    var earned = false;
    var settled = false;
    void finish(bool didEarn, {required bool record}) {
      if (settled) return;
      settled = true;
      if (record && !policy.isPro) {
        policy.recordRewarded(_now());
      }
      onSettled(didEarn);
    }

    await ad.show(
      onEarned: () => earned = true,
      onDismissed: () => finish(earned, record: true),
      onFailedToShow: () {
        finish(false, record: false);
        unawaited(load());
      },
    );
  }

  void clear() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    final ad = _ad;
    _ad = null;
    if (ad != null) unawaited(ad.dispose());
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
