import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:napp_ads/napp_ads.dart' hide ConsentManager;
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

import 'store_features.dart';
import 'data/ad_consent.dart';
import 'data/ad_lifecycle_coordinator.dart';
import 'data/fullscreen_ad_controllers.dart';
import 'data/play_store_adapter.dart';
import 'data/recovering_banner_controller.dart';
import 'data/verified_store_adapter.dart';
import 'data/listing_store.dart';
import 'data/subscription_check.dart';
import 'data/trial_sync.dart';
import 'home_page.dart';
import 'ads_state.dart';
import 'notifications/alert_service.dart';
import 'notifications/push_setup.dart';
import 'ui/onboarding_page.dart';
import 'ui/premium.dart';

const contactEmail = String.fromEnvironment('CONTACT_EMAIL');
const privacyUrl = String.fromEnvironment(
  'PRIVACY_URL',
  defaultValue: 'https://kamubul-api.devx8585.workers.dev/privacy/',
);
const sourceUrl = 'https://github.com/XPersPective/kamubul';
const otherAppsUrl = String.fromEnvironment(
  'OTHER_APPS_URL',
  defaultValue:
      'https://raw.githubusercontent.com/XPersPective/napp_apps/HEAD/apps.json',
);

// Ortak kitin "yalnız cihazda" gizlilik cümlesi KamuBul için doğru değil:
// Asistan, isteğe bağlı bildirim ve deneme süresi sunucuya veri gönderir.
const _aboutTexts = {
  'about.slogan': 'Resmî kamu ilanlarını tek yerde, anlaşılır ve güvenilir biçimde takip edin.',
  'about.openSourceTitle': 'Açık kaynak ve ilkelerimiz',
  'about.openSourceBody':
      'KamuBul’u insanların gerçekten işine yarayan, sade ve güvenilir bir '
      'uygulama olsun diye geliştiriyoruz. İlanları yalnız resmî kaynaklardan '
      'alırız. Kodun tamamı açıktır: uygulamanın ne yaptığını herkes inceleyip '
      'doğrulayabilir, hata bildirebilir ve katkıda bulunabilir. Hesap istemeyiz, '
      'yalnız hizmet için gereken veriyi işleriz ve kişisel verilerinizi satmayız.',
  'about.privacyLocal':
      'Kayıtlı aramalarınız ve kaydettiğiniz ilanlar yalnız bu cihazda saklanır. '
      'Asistan’a yazdıklarınız, açarsanız anlık bildirim kriterleriniz ve deneme '
      'süresi için cihazdan türetilen bir özet sunucumuza şifreli bağlantıyla '
      'gönderilir. Ayrıntılar gizlilik politikasındadır.',
};

Future<NappTranslations> loadAppTranslations() async =>
    (await ProLocalization.load(base: await NappTranslations.loadCore()))
        .mergedWith(const {'tr': _aboutTexts});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final translations = await loadAppTranslations();
  final store = await SettingsStore.load();
  final theme = ThemeModeController(store: store)..load();
  ReadingScale.attach(
    double.tryParse(store.getString(ReadingScale.key) ?? ''),
    (value) => store.setString(ReadingScale.key, value.toString()),
  );
  final identity = AppIdentity(
    appName: 'KamuBul',
    packageName: 'com.crazypenguin.kamubul',
    appStoreId: '6826592263',
    sourceUrl: sourceUrl,
    privacyPolicyUrl: privacyUrl,
    contactEmail: contactEmail.isEmpty ? 'hello@example.com' : contactEmail,
    otherAppsUrl: otherAppsUrl.isEmpty ? null : otherAppsUrl,
    iconAsset: 'assets/brand/kamubul_icon.png',
    brandColor: const Color(0xFF17659C),
    sloganKey: 'about.slogan',
  );
  final playAdapter = Platform.isAndroid ? PlayStoreAdapter() : null;
  final storeAdapter = VerifiedStoreAdapter(
    delegate: playAdapter ?? InAppPurchaseAdapter(),
    entitlements: playAdapter?.activeProductIds ?? readStoreKitEntitlements,
    restorableProducts: {
      proMonthlyProductId,
      if (playAdapter != null) proLegacyLifetimeProductId,
    },
  );
  final purchase = PurchaseRepository(
    adapter: storeAdapter,
    productId: proMonthlyProductId,
  );
  final pro = ProController(store: store, repository: purchase)..load();
  pro.startListening();
  Future<bool> checkSubscription() => verifySubscription(
    pro,
    store,
    activeProducts: storeAdapter.entitlements,
    restorableProducts: storeAdapter.restorableProducts,
  );
  final subscriptionCheck = checkSubscription();
  // Yeniden kurulum deneme süresini sıfırlamasın: sunucudaki ilk görülme.
  final trialSynced = await syncTrialStart(store);
  final policy = AdPolicy(
    minDaysForFullscreen: adFreeTrialDays,
    minDaysForRewarded: adFreeTrialDays,
  )..setPro(pro.isPro);
  final sessionCounted = startAdSession(policy, store, DateTime.now());
  final trialChanges = ValueNotifier(0);
  final binding = WidgetsBinding.instance;
  bool isForeground() => isAppForeground(binding.lifecycleState);
  final banner = RecoveringBannerController(
    policy: policy,
    isForeground: isForeground,
  );
  final rewarded = RecoveringRewardedAdManager(
    policy: policy,
    isForeground: isForeground,
  );
  final interstitial = WorkingInterstitialAdManager(
    policy: policy,
    isForeground: isForeground,
  );
  final appOpen = WorkingAppOpenAdManager(policy: policy);
  final coordinator = AdLifecycleCoordinator(
    store: store,
    pro: pro,
    policy: policy,
    banner: banner,
    rewarded: rewarded,
    interstitial: interstitial,
    appOpen: appOpen,
    adsAvailable: adsAvailable,
    isForeground: isForeground,
    verifySubscription: checkSubscription,
    syncTrial: () => syncTrialStart(store),
    initializeConsent: ConsentManager.initialize,
    onStateChanged: () => trialChanges.value++,
    saveAdState: () => saveAds(policy, store),
  )..start(
    trialSynced: trialSynced,
    sessionCounted: sessionCounted,
    initialSubscriptionCheck: subscriptionCheck,
  );
  AppLifecycleListener(onResume: coordinator.onResume);
  WidgetsBinding.instance.addObserver(SettingsLifecycleObserver(store));
  unawaited(registerBackgroundAlerts());
  await initPush(store);
  runApp(
    KamuBulApp(
      translations: translations,
      identity: identity,
      store: store,
      theme: theme,
      pro: pro,
      purchase: purchase,
      policy: policy,
      trialChanges: trialChanges,
      banner: banner,
      rewarded: rewarded,
      interstitial: interstitial,
      onPrivacyConsentChanged: coordinator.onPrivacyConsentChanged,
      onOnboardingCompleted: coordinator.onOnboardingCompleted,
      saveAdState: () => saveAds(policy, store),
    ),
  );
  unawaited(
    binding.waitUntilFirstFrameRasterized.then(
      (_) => coordinator.onFirstFrameReady(),
    ),
  );
}

class KamuBulApp extends StatelessWidget {
  const KamuBulApp({
    super.key,
    this.trialChanges,
    required this.translations,
    required this.identity,
    required this.store,
    required this.theme,
    required this.pro,
    required this.purchase,
    required this.policy,
    required this.banner,
    required this.rewarded,
    this.interstitial,
    this.onPrivacyConsentChanged,
    this.onOnboardingCompleted,
    required this.saveAdState,
  });

  final AppIdentity identity;
  final Listenable? trialChanges;
  final NappTranslations translations;
  final SettingsStore store;
  final ThemeModeController theme;
  final ProController pro;
  final PurchaseRepository purchase;
  final AdPolicy policy;
  final BannerAdController banner;
  final RewardedAdManager rewarded;
  final WorkingInterstitialAdManager? interstitial;
  final ValueChanged<bool>? onPrivacyConsentChanged;
  final VoidCallback? onOnboardingCompleted;
  final VoidCallback saveAdState;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([theme, pro, trialChanges]),
    builder: (context, _) => MaterialApp(
      title: identity.appName,
      theme: premiumTheme(AppTheme.light(brandColor: identity.brandColor)),
      darkTheme: premiumTheme(AppTheme.dark(brandColor: identity.brandColor)),
      themeMode: theme.mode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
          child: child!,
        );
      },
      localizationsDelegates: [
        NappLocalizationsDelegate(translations),
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
        interstitial: interstitial,
        onPrivacyConsentChanged: onPrivacyConsentChanged,
        onOnboardingCompleted: onOnboardingCompleted,
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
    this.interstitial,
    this.onPrivacyConsentChanged,
    this.onOnboardingCompleted,
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
  final WorkingInterstitialAdManager? interstitial;
  final ValueChanged<bool>? onPrivacyConsentChanged;
  final VoidCallback? onOnboardingCompleted;
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
          interstitial: widget.interstitial,
          onPrivacyConsentChanged: widget.onPrivacyConsentChanged,
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
          },
          onDone: () {
            widget.store.setInt('kamubul.onboarded', 1);
            widget.policy.setOnboardingCompleted(true);
            widget.onOnboardingCompleted?.call();
            setState(() => _onboarded = true);
          },
        );
}
