import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:kamubul/data/recovering_banner_controller.dart';

class _TestBanner extends BannerAd {
  _TestBanner(BannerAdListener listener)
    : super(
        adUnitId: 'test',
        size: AdSize.banner,
        listener: listener,
        request: const AdRequest(),
      );

  int requests = 0;
  int disposals = 0;

  @override
  Future<void> load() async => requests++;

  @override
  Future<void> dispose() async => disposals++;

  void fail() => listener.onAdFailedToLoad?.call(
    this,
    LoadAdError(3, 'test', 'empty', null),
  );

  void succeed() => listener.onAdLoaded?.call(this);
}

void main() {
  late AdPolicy policy;
  late RecoveringBannerController controller;
  late List<_TestBanner> banners;
  late bool foreground;

  setUp(() {
    policy = AdPolicy()..setSdkReady(true);
    banners = [];
    foreground = true;
    controller = RecoveringBannerController(
      policy: policy,
      isForeground: () => foreground,
      createBanner: (listener) {
        final banner = _TestBanner(listener);
        banners.add(banner);
        return banner;
      },
    );
  });

  tearDown(() => controller.dispose());

  testWidgets('a failed banner is disposed and a later load can show', (
    tester,
  ) async {
    controller.load();
    controller.load();
    expect(banners.single.requests, 1);
    final first = banners.single;
    first.fail();
    first.succeed();
    expect(first.disposals, 1);
    expect(controller.ad, isNull);
    expect(controller.shouldShow, isFalse);

    controller.load();
    await tester.pump(const Duration(seconds: 59));
    expect(banners, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(banners, hasLength(2));
    banners.last.succeed();
    expect(controller.ad, same(banners.last));
    expect(controller.shouldShow, isTrue);
  });

  testWidgets('an inactive app does not retry until it is foreground', (
    tester,
  ) async {
    controller.load();
    banners.single.fail();
    foreground = false;
    await tester.pump(const Duration(minutes: 1));
    expect(banners, hasLength(1));
    foreground = true;
    controller.load();
    expect(banners, hasLength(2));
    banners.last.succeed();
  });

  testWidgets('ad-free access cancels retry and discards pending responses', (
    tester,
  ) async {
    controller.load();
    final failed = banners.single;
    failed.fail();
    policy.setPro(true);
    controller.onProChanged();
    await tester.pump(const Duration(minutes: 2));
    controller.load();
    expect(banners, hasLength(1));

    policy.setPro(false);
    controller.load();
    final pending = banners.last;
    policy.setPro(true);
    controller.onProChanged();
    pending.succeed();
    expect(pending.disposals, 1);
    expect(controller.ad, isNull);
    expect(controller.shouldShow, isFalse);
  });
}
