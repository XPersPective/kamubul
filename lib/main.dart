import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

import 'data/listing_store.dart';
import 'home_page.dart';
import 'ads_state.dart';
import 'notifications/alert_service.dart';
import 'notifications/push_setup.dart';
import 'ui/onboarding_page.dart';

const contactEmail = String.fromEnvironment('CONTACT_EMAIL');
const privacyUrl = String.fromEnvironment(
  'PRIVACY_URL',
  defaultValue:
      'https://github.com/XPersPective/kamubul/blob/master/PRIVACY.md',
);
const sourceUrl = 'https://github.com/XPersPective/kamubul';
const otherAppsUrl = String.fromEnvironment('OTHER_APPS_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SettingsStore.load();
  final theme = ThemeModeController(store: store)..load();
  final identity = AppIdentity(
    appName: 'KamuBul',
    packageName: 'com.crazypenguin.kamubul',
    sourceUrl: sourceUrl,
    privacyPolicyUrl: privacyUrl,
    contactEmail: contactEmail.isEmpty ? 'hello@example.com' : contactEmail,
    otherAppsUrl: otherAppsUrl.isEmpty ? null : otherAppsUrl,
    iconAsset: 'assets/brand/kamubul_icon.png',
    brandColor: const Color(0xFF17659C),
  );
  final purchase = PurchaseRepository(
    adapter: InAppPurchaseAdapter(),
    productId: 'kamubul_pro_lifetime',
  );
  final pro = ProController(store: store, repository: purchase)..load();
  pro.startListening();
  final policy = AdPolicy();
  restoreAds(policy, store);
  policy
    ..setPro(pro.isPro)
    ..setOnboardingCompleted(true)
    ..startSession(DateTime.now());
  saveAds(policy, store);
  pro.addListener(() => policy.setPro(pro.isPro));
  final banner = BannerAdController(policy: policy);
  final rewarded = RewardedAdManager(policy: policy);
  final interstitial = InterstitialAdManager(policy: policy);
  final appOpen = AppOpenAdManager(policy: policy);
  if (!pro.isPro) {
    unawaited(() async {
      final ready = await ConsentManager.initialize();
      if (!ready) return;
      policy.setSdkReady(true);
      banner.load();
      await rewarded.load();
      await interstitial.load();
      if (policy.canShowAppOpen(DateTime.now())) {
        await appOpen.tryLoad(DateTime.now());
        await appOpen.showIfAvailable();
        saveAds(policy, store);
      }
    }());
  }
  WidgetsBinding.instance.addObserver(SettingsLifecycleObserver(store));
  unawaited(registerBackgroundAlerts());
  unawaited(initPush(store));
  runApp(
    KamuBulApp(
      identity: identity,
      store: store,
      theme: theme,
      pro: pro,
      purchase: purchase,
      policy: policy,
      banner: banner,
      rewarded: rewarded,
      saveAdState: () => saveAds(policy, store),
    ),
  );
}

class KamuBulApp extends StatelessWidget {
  const KamuBulApp({
    super.key,
    required this.identity,
    required this.store,
    required this.theme,
    required this.pro,
    required this.purchase,
    required this.policy,
    required this.banner,
    required this.rewarded,
    required this.saveAdState,
  });

  final AppIdentity identity;
  final SettingsStore store;
  final ThemeModeController theme;
  final ProController pro;
  final PurchaseRepository purchase;
  final AdPolicy policy;
  final BannerAdController banner;
  final RewardedAdManager rewarded;
  final VoidCallback saveAdState;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([theme, pro]),
    builder: (context, _) => MaterialApp(
      title: identity.appName,
      theme: AppTheme.light(brandColor: identity.brandColor),
      darkTheme: AppTheme.dark(brandColor: identity.brandColor),
      themeMode: theme.mode,
      localizationsDelegates: [
        NappLocalizationsDelegate(NappTranslations({})),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr')],
      home: _AppHome(
        identity: identity,
        store: store,
        theme: theme,
        pro: pro,
        purchase: purchase,
        policy: policy,
        banner: banner,
        rewarded: rewarded,
        saveAdState: saveAdState,
      ),
    ),
  );
}

/// İlk açılışta 4 adımlı, atlanabilir onboarding; sonrasında ana ekran.
class _AppHome extends StatefulWidget {
  const _AppHome({
    required this.identity,
    required this.store,
    required this.theme,
    required this.pro,
    required this.purchase,
    required this.policy,
    required this.banner,
    required this.rewarded,
    required this.saveAdState,
  });

  final AppIdentity identity;
  final SettingsStore store;
  final ThemeModeController theme;
  final ProController pro;
  final PurchaseRepository purchase;
  final AdPolicy policy;
  final BannerAdController banner;
  final RewardedAdManager rewarded;
  final VoidCallback saveAdState;

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> {
  late bool _onboarded = widget.store.getInt('kamubul.onboarded') != null;

  @override
  Widget build(BuildContext context) => _onboarded
      ? KamuHomePage(
          identity: widget.identity,
          store: widget.store,
          theme: widget.theme,
          pro: widget.pro,
          purchase: widget.purchase,
          policy: widget.policy,
          banner: widget.banner,
          rewarded: widget.rewarded,
          saveAdState: widget.saveAdState,
        )
      : OnboardingPage(
          onCreate: (filters) async {
            final listingStore = ListingStore();
            try {
              await listingStore.addSavedSearch(
                SavedSearch(
                  id: null,
                  name: 'Sizin için',
                  filters: filters,
                  createdAt: DateTime.now(),
                ),
              );
            } finally {
              await listingStore.close();
            }
            widget.store.setInt('kamubul.onboarded', 1);
            widget.store.setInt('kamubul.alerts.asked', 1);
          },
          onDone: () => setState(() => _onboarded = true),
        );
}
