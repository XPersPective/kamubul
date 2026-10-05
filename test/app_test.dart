import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

import 'package:kamubul/main.dart';

void main() {
  test('KamuBul uygulaması tanımlı', () {
    expect(KamuBulApp, isNotNull);
    expect('kamubul_pro_lifetime'.endsWith('_pro_lifetime'), isTrue);
  });
  testWidgets('sistem simgeleri özel başlıklarda tema değişimini izler', (
    tester,
  ) async {
    final store = SettingsStore();
    final theme = ThemeModeController(store: store)..load();
    final purchase = PurchaseRepository(adapter: InAppPurchaseAdapter());
    final policy = AdPolicy();
    await tester.pumpWidget(
      KamuBulApp(
        translations: await loadAppTranslations(),
        identity: AppIdentity(
          appName: 'KamuBul',
          packageName: 'com.crazypenguin.kamubul',
          sourceUrl: sourceUrl,
          privacyPolicyUrl: privacyUrl,
          contactEmail: 'test@example.org',
        ),
        store: store,
        theme: theme,
        pro: ProController(store: store, repository: purchase),
        purchase: purchase,
        policy: policy,
        banner: BannerAdController(policy: policy),
        rewarded: RewardedAdManager(policy: policy),
        saveAdState: () {},
      ),
    );
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      theme.setMode(mode);
      await tester.pumpAndSettle();
      final style = SystemChrome.latestStyle!;
      final expected = mode == ThemeMode.dark
          ? Brightness.light
          : Brightness.dark;
      expect(style.statusBarIconBrightness, expected);
      expect(style.systemNavigationBarIconBrightness, expected);
      expect(tester.takeException(), isNull);
    }
  });
}
