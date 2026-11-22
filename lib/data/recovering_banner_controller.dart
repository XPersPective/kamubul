import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:napp_ads/napp_ads.dart';

/// Keeps the shared banner widget and policy while recovering failed requests.
class RecoveringBannerController extends BannerAdController {
  RecoveringBannerController({
    required super.policy,
    required this.isForeground,
    BannerAd Function(BannerAdListener)? createBanner,
  }) : _createBanner = createBanner ?? _defaultBanner;

  final bool Function() isForeground;
  final BannerAd Function(BannerAdListener) _createBanner;

  BannerAd? _banner;
  Timer? _retry;
  bool _ready = false;
  bool _disposed = false;

  static BannerAd _defaultBanner(BannerAdListener listener) => BannerAd(
    adUnitId: AdsConfig.bannerUnit,
    size: AdSize.banner,
    request: const AdRequest(),
    listener: listener,
  );

  @override
  BannerAd? get ad => _banner;

  @override
  bool get isLoaded => _ready;

  @override
  bool get shouldShow => _ready && policy.canShowBanner();

  @override
  void load() {
    if (_disposed ||
        !isForeground() ||
        !policy.canShowBanner() ||
        _banner != null ||
        _retry != null) {
      return;
    }

    final banner = _createBanner(
      BannerAdListener(
        onAdLoaded: (ad) {
          if (!identical(_banner, ad)) return;
          _ready = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, _) => _onFailure(ad),
      ),
    );
    _banner = banner;
    unawaited(_request(banner));
  }

  Future<void> _request(BannerAd banner) async {
    try {
      await banner.load();
    } catch (_) {
      _onFailure(banner);
    }
  }

  void _onFailure(Ad ad) {
    if (!identical(_banner, ad)) return;
    final wasVisible = _ready;
    _clearBanner();
    if (!_disposed && policy.canShowBanner()) {
      _retry = Timer(const Duration(minutes: 1), () {
        _retry = null;
        load();
      });
    }
    if (wasVisible) notifyListeners();
  }

  void _clearBanner() {
    final banner = _banner;
    _banner = null;
    _ready = false;
    if (banner != null) {
      unawaited(banner.dispose().catchError((Object _) {}));
    }
  }

  @override
  void onProChanged() {
    if (!policy.isPro) return;
    _retry?.cancel();
    _retry = null;
    final wasVisible = _ready;
    _clearBanner();
    if (wasVisible) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _clearBanner();
    super.dispose();
  }
}
