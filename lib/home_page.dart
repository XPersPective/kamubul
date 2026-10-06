import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kamubul_core/kamubul_core.dart'
    show
        SourceStatus,
        kIlanGovSourceId,
        kIskurSourceId,
        SourceState,
        CatalogueMetadata,
        SearchCriteria,
        dayKey,
        wallClock,
        educationLabel,
        RemoteCatalogueClient,
        RemoteCatalogueException,
        decodeAlertTap,
        CriteriaMatch;
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/catalogue_refresh.dart';
import 'data/listing_store.dart';
import 'data/remote_sync.dart';
import 'data/search_alerts.dart';
import 'data/turkish_cities.dart';
import 'data/user_data.dart';
import 'notifications/alert_service.dart';
import 'notifications/notification_center_page.dart';
import 'notifications/push_registration.dart';
import 'notifications/push_setup.dart';
import 'listings/listing_facts.dart';
import 'listings/listing_guide.dart';
import 'listings/official_listing_page.dart';
import 'ads_state.dart';
import 'data/assistant_client.dart';
import 'rate_prompt_state.dart';
import 'ui/premium.dart';
import 'ui/premium_widgets.dart';
import 'ui/assistant_chat.dart';
import 'ui/pro_page.dart';
import 'ui/turkish.dart';

class KamuHomePage extends StatefulWidget {
  const KamuHomePage({
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
    this.shareService,
    this.reviewService,
    this.ratePolicy,
    this.catalogueClient,
    this.otherAppsRepository,
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
  // Testler servisleri enjekte eder; üretime kendi örnekleri kurulur.
  final ShareService? shareService;
  final ReviewService? reviewService;
  final RatePromptPolicy? ratePolicy;
  final RemoteCatalogueClient? catalogueClient;
  final OtherAppsRepository? otherAppsRepository;

  @override
  State<KamuHomePage> createState() => _KamuHomePageState();
}

class _KamuHomePageState extends State<KamuHomePage> {
  static const _legacySavedKey = 'kamubul.saved_urls';
  static const _kategoriAdlari = ['Tümü', 'İşçi', 'Personel', 'Belediye'];

  int _tab = 0;
  int _category = 0;
  String _search = '';
  bool _last30 = false;
  String? _place;
  int? _ageFilter;
  String? _ageAsOf;
  SearchCriteria? _quickCriteria;
  String? _educationFilter;
  String? _kpssFilter;
  int? _activeSearchId;
  bool _includeUnknown = false;
  int _alertTapGeneration = 0;
  ({String key, int revision})? _pendingAlert;
  ({String key, int revision})? _activeAlert;
  Route<void>? _alertRoute;

  SavedSearch? get _activeSearch =>
      _searches.where((s) => s.id == _activeSearchId).firstOrNull;
  bool _loading = false;
  String? _error;
  List<String> _failedSources = const [];
  List<SourceStatus> _sourceStatuses = const [];
  DateTime? _lastRefresh;
  DateTime? _remoteLastSuccess;
  bool _remoteFailed = false;
  List<ListingRecord> _records = const [];
  List<SavedSearch> _searches = const [];
  ListingRecord? _assistantListing;
  final ListingStore _store = ListingStore();
  final TextEditingController _searchController = TextEditingController();
  late final ShareService _share = widget.shareService ?? ShareService();
  late final ReviewService _review = widget.reviewService ?? ReviewService();
  late final RatePromptPolicy _ratePolicy =
      widget.ratePolicy ?? RatePromptPolicy();
  late final OtherAppsRepository? _otherApps = _otherAppsRepository();

  OtherAppsRepository? _otherAppsRepository() {
    final injected = widget.otherAppsRepository;
    if (injected != null) return injected;
    final raw = widget.identity.otherAppsUrl;
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (raw == null ||
        raw.length > 2048 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return OtherAppsRepository(
      appsUrl: raw,
      cacheStore: widget.store,
      // Real napp_apps catalogue snapshot; first offline launch also has content.
      embedded: const [
        OtherApp(
          id: 'doctorfilter',
          androidPackage: 'com.crazypenguin.doctorfilter',
          iconUrl: 'https://raw.githubusercontent.com/XPersPective/napp_apps/HEAD/icons/doctorfilter.png',
          name: {
            'tr': 'DoctorFilter: Mavi Işık Filtre',
            'en': 'DoctorFilter Blue Light Filter',
          },
          description: {
            'tr': 'Mavi ışık filtresi ve ekran karartma: Kelvin ile gece modu, zamanlayıcı',
            'en': 'Blue light filter & screen dimmer: warm night mode in Kelvin, extra dim, timer',
          },
        ),
        OtherApp(
          id: 'halen',
          androidPackage: 'com.crazypenguin.halenquitsmoking',
          iconUrl: 'https://raw.githubusercontent.com/XPersPective/napp_apps/HEAD/icons/halen.png',
          name: {
            'tr': 'Halen: Quit Smoking Tracker',
            'en': 'Halen: Quit Smoking Tracker',
          },
          description: {
            'tr': 'Önce azalt, sonra bırak: kendini yeniden hesaplayan plan, cihazında gizli.',
            'en': 'Cut down first, then quit — an adaptive plan that stays private on your device.',
          },
          order: 2,
        ),
      ],
    );
  }

  void _openOtherApps() {
    final repository = _otherApps;
    if (repository == null) return;
    Navigator.of(context).push(
      sharedAxisRoute<void>(
        OtherAppsPage(identity: widget.identity, repository: repository),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    restoreRatePrompt(_ratePolicy, widget.store);
    _ratePolicy.markFirstSeen(DateTime.now());
    saveRatePrompt(_ratePolicy, widget.store);
    alertTapUrl.addListener(_openAlertFromNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _migrateLegacyBookmarks();
      await _loadLocal();
      // Soğuk açılışta bildirim dokunuşu: kayıt yereldeyse ayrıntı açılır.
      await consumeLaunchAlertTap();
      if (alertTapUrl.value != null) await _openAlertFromNotification();
      await _refresh();
    });
  }

  /// Stable server IDs read the API; legacy URL-only taps keep their local path.
  Future<void> _openAlertFromNotification() async {
    final payload = alertTapUrl.value;
    if (payload == null) return;
    alertTapUrl.value = null;
    final target = decodeAlertTap(payload);
    if (target == null) return;
    final key = _alertKey(target);
    final revision = target.revision ?? 1;
    if (_activeAlert?.key == key && _activeAlert!.revision >= revision) {
      // Returning to the visible target cancels a different pending tap as well.
      if (_pendingAlert != null) {
        ++_alertTapGeneration;
        _pendingAlert = null;
      }
      return;
    }
    if (_pendingAlert?.key == key && _pendingAlert!.revision >= revision) {
      return;
    }
    final tapGeneration = ++_alertTapGeneration;
    _pendingAlert = (key: key, revision: revision);
    try {
      await _resolveAlertTarget(target, tapGeneration);
    } finally {
      if (tapGeneration == _alertTapGeneration) _pendingAlert = null;
    }
  }

  String _alertKey(({String url, String? listingId, int? revision}) target) =>
      target.listingId == null ? 'url:${target.url}' : 'id:${target.listingId}';

  Future<void> _resolveAlertTarget(
    ({String url, String? listingId, int? revision}) target,
    int tapGeneration,
  ) async {
    final url = target.url;
    await _loadLocal();
    if (!mounted || tapGeneration != _alertTapGeneration) return;
    ListingRecord? record;
    for (final candidate in _records) {
      if (candidate.url == url) record = candidate;
    }
    final client = target.listingId == null
        ? null
        : widget.catalogueClient ?? defaultRemoteClient();
    if (client != null) {
      try {
        final generation = await _store.bindRemoteOrigin(
          catalogueOrigin(client),
        );
        final epoch = await _store.remoteDetailEpoch(
          expectedGeneration: generation,
        );
        var item = await _store.cachedRemoteDetail(
          target.listingId!,
          expectedGeneration: generation,
          expectedEpoch: epoch,
        );
        var fromCache =
            item != null && (item['revision'] as int) >= (target.revision ?? 1);
        if (!fromCache) {
          try {
            final fetched = await client.fetchListing(target.listingId!);
            if (fetched == null) {
              await _store.cachedRemoteDetail(
                target.listingId!,
                expectedGeneration: generation,
                expectedEpoch: epoch,
              );
              if (mounted && tapGeneration == _alertTapGeneration) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bu ilan artık sunucuda bulunmuyor.'),
                  ),
                );
              }
              return;
            }
            item = await _store.cacheRemoteDetail(
              target.listingId!,
              fetched,
              expectedGeneration: generation,
              expectedEpoch: epoch,
            );
          } on RemoteCatalogueException {
            // Network failure retains cached data; a newer delta/tombstone wins.
            item = await _store.cachedRemoteDetail(
              target.listingId!,
              expectedGeneration: generation,
              expectedEpoch: epoch,
            );
            if (item == null) rethrow;
            fromCache = true;
          }
        }
        if (!mounted || tapGeneration != _alertTapGeneration) return;
        final detail = ListingStore.projectRemoteListing(item);
        if (detail == null) throw const FormatException('invalid detail');
        _pushAlertPage(
          OfficialListingPage(
            listing: detail,
            unavailable: item['active'] == false,
            onAskAssistant: () => _askAssistantAbout(detail),
            cacheNotice: (item['revision'] as int) < (target.revision ?? 1)
                ? 'Güncel ayrıntı alınamadı. Önbellekteki eski bilgiler gösteriliyor.'
                : fromCache
                ? 'Önbellekteki ilan bilgileri gösteriliyor.'
                : null,
          ),
          target,
          item['revision'] as int,
        );
      } on Exception {
        if (mounted && tapGeneration == _alertTapGeneration) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('İlan ayrıntısı alınamadı. Yeniden deneyin.'),
            ),
          );
        }
      } finally {
        if (widget.catalogueClient == null) client.close();
      }
      return;
    }
    if (record == null) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.scheme == 'https') {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } on Exception {
          // Budanmış kayıtta sessiz kalınır; kullanıcı listeye bakabilir.
        }
      }
      return;
    }
    _pushAlertPage(_listingPage(record), target, target.revision ?? 1);
  }

  void _pushAlertPage(
    Widget page,
    ({String url, String? listingId, int? revision}) target,
    int revision,
  ) {
    final navigator = Navigator.of(context);
    final previous = _alertRoute;
    if (previous?.navigator == navigator) navigator.removeRoute(previous!);
    final route = sharedAxisRoute<void>(page);
    _alertRoute = route;
    _activeAlert = (key: _alertKey(target), revision: revision);
    _pendingAlert = null;
    // Opening a cold-tap page must not wait for Back before startup sync proceeds.
    unawaited(
      navigator.push(route).whenComplete(() {
        if (identical(_alertRoute, route)) {
          _alertRoute = null;
          _activeAlert = null;
        }
      }),
    );
  }

  /// PB-002 öncesi URL listesiyle kaydedilen yer imlerini veritabanına taşır.
  Future<void> _migrateLegacyBookmarks() async {
    final legacy = widget.store.getStringList(_legacySavedKey);
    if (legacy == null || legacy.isEmpty) return;
    final now = DateTime.now();
    final migrated = <ListingRecord>[];
    for (final raw in legacy) {
      final url = Uri.tryParse(raw);
      if (url == null || url.host != 'kariyerkapisi.gov.tr') continue;
      migrated.add(
        ListingRecord(
          url: raw,
          sourceId: 'kariyerkapisi',
          title: 'Kaydedilmiş ilan',
          category: '',
          publishedAt: null,
          fetchedAt: now,
          saved: true,
          savedAt: now,
        ),
      );
    }
    if (migrated.isNotEmpty) {
      try {
        await _store.mergeFeed(migrated, pruneBefore: now);
      } on Exception {
        // Taşıma sonraki açılışta yeniden denenir; liste korunur.
        return;
      }
    }
    widget.store.setStringList(_legacySavedKey, const []);
  }

  Future<void> _loadLocal() async {
    try {
      final records = await _store.allListings();
      final searches = await _store.savedSearches();
      final cached = await _store.remoteMetadata();
      List<SourceStatus>? statuses;
      if (cached.metadata != null) {
        try {
          statuses = CatalogueMetadata.decode(jsonDecode(cached.metadata!))
              .sources;
        } on FormatException {
          /* The listing cache remains usable. */
        }
      }
      if (!mounted) return;
      setState(() {
        _records = records;
        _searches = searches;
        _remoteLastSuccess = cached.lastSuccess;
        if (statuses != null) _sourceStatuses = statuses;
      });
      _restoreSelection();
      // Kullanıcı sunucu bildirimini açtıysa etiketler değişince kayıt tazelenir;
      // içerik değişmediyse ağa çıkılmaz.
      final registrar = pushRegistrar;
      if (registrar != null && registrar.enabled) {
        unawaited(registrar.sync(searches));
      }
    } on Exception {
      // Yerel okuma hatası: boş katalogla çevrimiçi yenileme denenir.
    }
  }

  /// Sunucu bildirimini açar/kapatır. Açmak kullanıcı eylemidir: bildirim izni
  /// istenir ve ancak o zaman sunucuya kayıt gider. Kapatmak sunucudaki kaydı
  /// siler ("bildirim verilerimi sil").
  Future<void> _setServerPush(bool on) async {
    final registrar = pushRegistrar;
    if (registrar == null) return;
    final messenger = ScaffoldMessenger.of(context);
    String message;
    if (on) {
      final outcome = await registrar.enable(_searches);
      if (outcome == PushSyncOutcome.registered ||
          outcome == PushSyncOutcome.unchanged) {
        unawaited(attachPushListeners());
      }
      message = switch (outcome) {
        PushSyncOutcome.registered ||
        PushSyncOutcome.unchanged => 'Sunucu bildirimleri açık.',
        PushSyncOutcome.permissionDenied => 'Bildirim izni verilmedi.',
        PushSyncOutcome.unavailable =>
          'Bu sürümde sunucu bildirimi yapılandırılmamış.',
        _ => 'Şu an bağlanılamadı; daha sonra otomatik denenecek.',
      };
    } else {
      final deleted = await registrar.disable();
      message = deleted
          ? 'Sunucu bildirimleri kapatıldı. Aramalarınız ve kriterleriniz '
                'cihazınızda duruyor.'
          : registrar.enabled
          ? 'Kapatma işlemi kaydedilemedi; yeniden deneyin.'
          : 'Kapatıldı. Aramalarınız ve kriterleriniz cihazınızda duruyor.';
    }
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// [manual]: kullanıcı aşağı çekti ya da yenile düğmesine bastı.
  Future<void> _refresh({bool manual = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await refreshCatalogue(_store);
    await _loadLocal();
    if (!mounted) return;
    setState(() {
      _lastRefresh = result.checkedAt;
      _remoteLastSuccess = result.remoteLastSuccess ?? _remoteLastSuccess;
      _remoteFailed = result.remoteFailed;
      _failedSources = result.failedSources;
      if (result.sourceStatuses.isNotEmpty) {
        _sourceStatuses = result.sourceStatuses;
      }
      final errors = [
        if (result.remoteFailed)
          'Sunucu kataloğu yenilenemedi. Mevcut önbellek korunuyor.',
        if (result.failedSources.isNotEmpty)
          '${turkishList(result.failedSources)} yenilenemedi. Son görülen liste korunuyor.',
      ];
      _error = errors.isEmpty ? null : errors.join(' ');
    });
    if (result.failedSources.isEmpty && !result.remoteFailed) {
      _ratePolicy.markPositiveMoment();
      try {
        await _review.maybePromptInApp(_ratePolicy, DateTime.now());
      } catch (_) {
        // Puan istemi en iyi çabadır; yenilemeyi asla engellemez.
      }
      saveRatePrompt(_ratePolicy, widget.store);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleSaved(ListingRecord record) async {
    HapticFeedback.mediumImpact();
    await _store.setSaved(record.url, !record.saved);
    await _loadLocal();
  }

  Future<void> _open(Uri url) async {
    if (url.scheme != 'https') return;
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Kullanıcıya tek, anlaşılır hata gösterilir.
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resmî sayfa açılamadı.')));
    }
  }

  Future<void> _shareApp() async {
    try {
      await _share.shareApp(
        widget.identity,
        message: 'KamuBul ile resmî kamu ilanlarını takip edin: {url}',
        isIos: Platform.isIOS,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylaşım penceresi açılamadı.')),
      );
    }
  }

  Future<void> _openRatePage() async {
    try {
      await _review.openRatePage(widget.identity, isIos: Platform.isIOS);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mağaza sayfası açılamadı.')),
      );
    }
  }

  Future<void> _exportData() async {
    try {
      final json = exportUserDataJson(
        searches: _searches,
        bookmarks: [
          for (final record in _records)
            if (record.saved) record,
        ],
      );
      await SharePlus.instance.share(ShareParams(text: json));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yedek oluşturulamadı ya da paylaşılamadı.'),
        ),
      );
    }
  }

  Future<void> _importData() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final UserDataImport imported;
    try {
      imported = parseUserDataJson(raw);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    for (final search in imported.searches) {
      await _store.addSavedSearch(search);
    }
    if (imported.bookmarks.isNotEmpty) {
      // DateTime(2000): içe aktarma yerel önbellekteki eski kayıtları budamaz.
      await _store.mergeFeed(imported.bookmarks, pruneBefore: DateTime(2000));
    }
    await _loadLocal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'İçe aktarıldı: ${imported.searches.length} arama, '
          '${imported.bookmarks.length} yer imi.',
        ),
      ),
    );
  }

  /// Kriterlere göre sıralama: kesin uyanlar önce, bilinmeyenler sonra;
  /// her grup içinde mevcut (yayın tarihi) sırası korunur.
  /// Her setState'te sıfırlanır: kaydırırken her kart için ~300 ilanı yeniden
  /// eşleştirmek (O(n²)) listeyi takılarak kaydırıyordu.
  List<ListingRecord>? _visibleCache;

  List<ListingRecord> get _visibleRecords =>
      _visibleCache ??= _computeVisibleRecords();

  List<ListingRecord> _computeVisibleRecords() {
    final matched = <ListingRecord>[], unknown = <ListingRecord>[];
    // Aynı ilan ilan.gov.tr'de de varsa liste tek kart gösterir (kayıtlı kopya korunur).
    final ids = {
      for (final record in _records)
        if (record.criteriaListing?['active'] != false &&
            record.criteriaListing?['id'] is String)
          record.criteriaListing!['id'] as String,
    };
    for (final record in _records) {
      if (_tab == 1 && !record.saved) continue;
      final twin = record.twin?.id;
      if (_tab != 1 && twin != null && ids.contains(twin)) continue;
      // Telefonun eski kaynak okuyucusundan kalan, sunucuda karşılığı olmayan
      // kayıtlar listede gösterilmez; kaydedilmişse Kaydedilenler'de durur.
      if (_tab != 1 && record.criteriaListing == null && !record.saved) {
        continue;
      }
      final match = _matchVisible(record);
      if (match == CriteriaMatch.match) {
        matched.add(record);
      } else if (_includeUnknown && match == CriteriaMatch.unknown) {
        unknown.add(record);
      }
    }
    return [...matched, ...unknown];
  }

  void _applySearch(SavedSearch search) {
    if (search.hasInvalidCriteria) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu aramanın kriterlerini önce Düzenle ile onarın.'),
        ),
      );
      return;
    }
    _searchController.text = search.filters['q'] ?? '';
    setState(() {
      _search = search.filters['q'] ?? '';
      _category = int.tryParse(search.filters['kategori'] ?? '') ?? 0;
      _last30 = search.filters['son30'] == '1';
      _place = (search.filters['sehir'] ?? '').isEmpty
          ? null
          : cityLabel(search.filters['sehir']!);
      _ageFilter = int.tryParse(search.filters['yas'] ?? '');
      _ageAsOf = search.effectiveCriteria.values['ageAsOf'] as String?;
      _quickCriteria = search.effectiveCriteria;
      _educationFilter = (search.filters['egitim'] ?? '').isEmpty
          ? null
          : educationLabel(search.filters['egitim']!);
      _kpssFilter = (search.filters['kpss'] ?? '').isEmpty
          ? null
          : search.filters['kpss'];
      _activeSearchId = search.id;
      _includeUnknown = false;
    });
  }

  Future<void> _chooseCity() async {
    final controller = TextEditingController(text: _place ?? '');
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final city = controller.text.trim();
          final canonical = canonicalCity(city);
          final known = _records
              .where(
                (record) =>
                    record.places.any((place) => placeMatchesCity(place, city)),
              )
              .length;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Şehre göre ara',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Şehir',
                    hintText: 'Örn. Ankara',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => update(() {}),
                  onSubmitted: (_) {
                    if (canonical != null) {
                      Navigator.pop(sheetContext, canonical);
                    }
                  },
                ),
                Text(
                  city.isEmpty
                      ? 'Şehir adını yazın.'
                      : canonical == null
                      ? '81 ilden birini yazın.'
                      : '$canonical • listede $known ilan',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canonical == null
                        ? null
                        : () => Navigator.pop(sheetContext, canonical),
                    child: const Text('Bu şehre göre süz'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || chosen == null) return;
    setState(() {
      _place = chosen;
      _patchQuickCriteria(['cities']);
      _activeSearchId = null;
      _includeUnknown = false;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _category = 0;
      _last30 = false;
      _place = null;
      _ageFilter = null;
      _ageAsOf = null;
      _quickCriteria = null;
      _educationFilter = null;
      _kpssFilter = null;
      _activeSearchId = null;
      _includeUnknown = false;
    });
  }

  static const _selectionKey = 'kamubul.selection';
  bool _selectionRestored = false;

  /// Süzgeç ve seçili kayıtlı arama her değişimde saklanır; açılışta döner.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _visibleCache =
        null; // fn içinde okunmuş olabilir; değişiklikten sonra sıfırla
    if (!_selectionRestored) return;
    final value = jsonEncode({
      'search': _activeSearchId,
      'filters': _currentFilters,
    });
    if (widget.store.getString(_selectionKey) != value) {
      widget.store.setString(_selectionKey, value);
    }
  }

  void _restoreSelection() {
    if (_selectionRestored) return;
    _selectionRestored = true;
    try {
      final raw = jsonDecode(widget.store.getString(_selectionKey) ?? '');
      final id = raw['search'];
      final saved = _searches.where((s) => s.id != null && s.id == id);
      if (saved.isNotEmpty) return _applySearch(saved.first);
      final filters = Map<String, String>.from(raw['filters'] as Map);
      final isDefault = filters.entries.every(
        (e) => const {'q': '', 'kategori': '0', 'son30': '0'}[e.key] == e.value,
      );
      if (isDefault) return;
      final search = SavedSearch(
        id: null,
        name: '',
        filters: filters,
        createdAt: DateTime.now(),
      );
      if (!search.hasInvalidCriteria) _applySearch(search);
    } on Object {
      // Kayıt yoksa ya da bozuksa varsayılan "Tümü" görünümü kalır.
    }
  }

  Map<String, String> get _currentFilters => {
    'q': _search,
    'kategori': '$_category',
    'son30': _last30 ? '1' : '0',
    'sehir': ?_place,
    'yas': ?_ageFilter?.toString(),
    'yasTarih': ?_ageAsOf,
    'egitim': ?_educationFilter,
    'kpss': ?_kpssFilter,
  };

  // Yalnız değiştirilen hızlı alanı yenile; çoklu seçim/puan/yıl kaybolmasın.
  void _patchQuickCriteria(List<String> keys) {
    final previous = _quickCriteria;
    if (previous == null) return;
    final replacement = SearchCriteria.fromLegacy(_currentFilters).values;
    final values = {...previous.values};
    for (final key in keys) {
      values.remove(key);
      if (replacement.containsKey(key)) values[key] = replacement[key];
    }
    _quickCriteria = SearchCriteria.parse(values);
  }

  CriteriaMatch _matchVisible(ListingRecord record) {
    final active = _activeSearch;
    if (active != null) return active.matchListing(record, now: DateTime.now());
    final quick = _quickCriteria;
    if (quick != null) {
      if (_tab != 1 && record.category == 'Yurt Dışı Eğitim İlanları') {
        return CriteriaMatch.noMatch;
      }
      final criteria = _tab == 1
          ? SearchCriteria.parse({...quick.values}..remove('categories'))
          : quick;
      return criteria.match(
        record.matchingData,
        now: DateTime.now(),
        forSaved: _tab == 1,
      );
    }
    return matchFilters(
      record,
      _tab == 1 ? {..._currentFilters, 'kategori': '0'} : _currentFilters,
      forSaved: _tab == 1,
    );
  }

  @override
  void dispose() {
    alertTapUrl.removeListener(_openAlertFromNotification);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentSearch() async {
    SavedSearch? existing;
    for (final search in _searches) {
      if (search.id == _activeSearchId) existing = search;
    }
    final seed =
        existing ??
        SavedSearch(
          id: null,
          name: '',
          filters: _currentFilters,
          criteria: _quickCriteria,
          createdAt: DateTime.now(),
        );
    var saved = await _promptEditSearch(seed, creating: existing == null);
    if (saved == null) return;
    if (existing != null) {
      await _store.updateSavedSearch(saved);
    } else {
      saved = await _store.addSavedSearch(saved);
    }
    await _loadLocal();
    if (mounted) _applySearch(saved);
    if (existing == null) await _maybeAskNotificationPermission();
  }

  /// İlk kayıtlı aramadan sonra yumuşak izin açıklaması gösterilir;
  /// reddedilirse uygulama aynen çalışır.
  Future<void> _maybeAskNotificationPermission() async {
    if (widget.store.getInt('kamubul.alerts.asked') != null) return;
    widget.store.setInt('kamubul.alerts.asked', 1);
    if (_searches.length > 1 || !mounted) return;
    await requestAlertPermission(context);
  }

  Future<void> _manageSearches() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            Text(
              'Kayıtlı aramalar',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            if (_searches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Henüz kayıtlı arama yok. Süzgeçleri seçip kaydedin.',
                ),
              ),
            for (final search in _searches)
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(search.name),
                subtitle: Text(
                  '${_filterSummary(search)}\nBildirim: ${_modeLabel(alertModeOf(search.filters))}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  tooltip: 'Arama işlemleri',
                  icon: const Icon(Icons.notifications_outlined),
                  onSelected: (value) async {
                    if (value == 'rename') {
                      final name = await _promptRename(search);
                      final trimmed = name?.trim();
                      if (trimmed == null || trimmed.isEmpty) return;
                      await _store.updateSavedSearch(
                        search.copyWith(name: trimmed),
                      );
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                      return;
                    }
                    if (value == 'delete') {
                      final ok = await _confirmDeleteSearch(search);
                      if (ok != true) return;
                      final id = search.id;
                      if (id != null) await _store.deleteSavedSearch(id);
                      // Silinen arama seçiliyse kriterleri de ekranda kalmasın.
                      if (_activeSearchId == search.id) _clearFilters();
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                      return;
                    }
                    if (value == 'edit') {
                      final updated = await _promptEditSearch(search);
                      if (updated == null) return;
                      await _store.updateSavedSearch(updated);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                      return;
                    }
                    final filters = <String, String>{...search.filters};
                    filters['bildirim'] = value;
                    await _store.updateSavedSearch(
                      search.copyWith(filters: filters),
                    );
                    await _loadLocal();
                  },
                  itemBuilder: (menuContext) => [
                    PopupMenuItem(
                      value: 'instant',
                      enabled: !search.hasInvalidCriteria,
                      child: Text('Anlık bildirim'),
                    ),
                    PopupMenuItem(
                      value: 'digest',
                      enabled: !search.hasInvalidCriteria,
                      child: const Text('Günlük özet'),
                    ),
                    PopupMenuItem(
                      value: 'off',
                      enabled: !search.hasInvalidCriteria,
                      child: const Text('Kapalı'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    PopupMenuItem(
                      value: 'rename',
                      enabled: !search.hasInvalidCriteria,
                      child: Text('Yeniden adlandır'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Sil')),
                  ],
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _applySearch(search);
                },
              ),
          ],
        ),
      ),
    );
    await _loadLocal();
    if (changed == true && _activeSearchId != null && mounted) {
      final stillExists = _searches.any((s) => s.id == _activeSearchId);
      if (!stillExists) {
        setState(() {
          _activeSearchId = null;
          _includeUnknown = false;
        });
      }
    }
  }

  /// Tek form yeni/düzenlenen aramanın profilini doğrular; ileri kriterleri korur.
  Future<SavedSearch?> _promptEditSearch(
    SavedSearch search, {
    bool creating = false,
  }) async {
    var values = <String, Object?>{};
    try {
      values = {...search.effectiveCriteria.values};
      if (values['education'] case final List education) {
        values['education'] = education
            .cast<String>()
            .map(educationLabel)
            .toSet()
            .toList();
      }
      if (values['cities'] case final List cities) {
        values['cities'] = cities
            .cast<String>()
            .map(cityLabel)
            .toSet()
            .toList();
      }
    } on FormatException {
      /* Kullanıcı aşağıdaki uyarıyla onarabilir. */
    }
    final name = TextEditingController(text: search.name);
    final age = TextEditingController(
      text: '${values['age'] ?? search.filters['yas'] ?? ''}',
    );
    final type = TextEditingController(
      text: '${values['kpssType'] ?? search.filters['kpss'] ?? ''}',
    );
    final score = TextEditingController(text: '${values['kpssScore'] ?? ''}');
    final year = TextEditingController(text: '${values['kpssYear'] ?? ''}');
    final keyword = TextEditingController(text: '${values['keyword'] ?? ''}');
    var keywordScope = values['keywordScope'] == 'title' ? 'title' : 'full';
    final ageDate = TextEditingController(
      text: '${values['ageAsOf'] ?? dayKey(wallClock(DateTime.now()))}',
    );
    String? error;
    final pendingChoices = <String, TextEditingController>{};
    final occupations = <String>{}, institutions = <String>{};
    for (final record in _records) {
      final listing = record.criteriaListing;
      if (listing == null || listing['active'] == false) continue;
      if (listing['institution'] case final String institution) {
        if (institution.trim().isNotEmpty && institution.length <= 100) {
          institutions.add(institution.trim());
        }
      }
      final groups = listing['requirementGroups'];
      for (final source in [
        listing,
        if (groups is List) ...groups.whereType<Map>(),
      ]) {
        final raw = source['occupations'];
        if (raw is List) {
          occupations.addAll(
            raw
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty && s.length <= 100)
                .map((s) => s.trim()),
          );
        }
      }
    }
    Widget criteriaSelector(
      String key,
      String label,
      Iterable<String> options,
      StateSetter update,
    ) {
      final selected = (values[key] as List?)?.cast<String>() ?? <String>[];
      final available = {...options, ...selected}.toList()
        ..sort((a, b) => foldTurkish(a).compareTo(foldTurkish(b)));
      TextEditingController? editor;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Autocomplete<String>(
            optionsBuilder: (text) => text.text.trim().isEmpty
                ? const Iterable<String>.empty()
                : available
                      .where(
                        (option) =>
                            foldTurkish(option)
                                .contains(foldTurkish(text.text)) &&
                            !selected.any(
                              (s) => foldTurkish(s) == foldTurkish(option),
                            ),
                      )
                      .take(20),
            fieldViewBuilder: (context, controller, focus, submit) {
              editor = controller;
              pendingChoices[key] = controller;
              return TextFormField(
                key: ValueKey('criteria-$key'),
                controller: controller,
                focusNode: focus,
                onFieldSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: label,
                  hintText: 'Seçmek için yazın',
                  helperText: available.isEmpty
                      ? 'Katalogda henüz seçenek yok.'
                      : 'En çok 10 seçim; boş bırakmak filtreyi kaldırır.',
                  helperMaxLines: 3,
                ),
              );
            },
            onSelected: (option) {
              update(() {
                if (selected.length >= 10) {
                  error = '$label için en çok 10 seçim yapabilirsiniz.';
                } else {
                  values[key] = [...selected, option];
                  error = null;
                }
              });
              editor?.clear();
            },
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final option in selected)
                InputChip(
                  deleteButtonTooltipMessage: '$label: $option seçimini kaldır',
                  label: Text(
                    option,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: () => update(
                    () => values[key] = selected
                        .where((s) => s != option)
                        .toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      );
    }

    try {
      return await showDialog<SavedSearch>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text(creating ? 'Aramayı kaydet' : 'Aramayı düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  if (search.hasInvalidCriteria)
                    const Text(
                      'Bu aramanın kriterleri okunamadı. Kaydetmeden önce tüm kriterleri yeniden kontrol edin.',
                    ),
                  TextField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Arama adı'),
                  ),
                  TextField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Yaşınız (uyum için, isteğe bağlı)',
                      helperText:
                          '16–80; boş bırakırsanız yaş filtresi uygulanmaz.',
                      helperMaxLines: 3,
                    ),
                  ),
                  TextField(
                    controller: ageDate,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Yaş bilgisi tarihi (YYYY-AA-GG)',
                      helperText: 'Yaşınız değiştiğinde güncelleyin. 366 günden eski veya gelecekteki bilgiyle yaş uygunluğu doğrulanmaz; kesin uygunluk bildirimi gönderilmez.',
                      helperMaxLines: 6,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ageDate.text = dayKey(wallClock(DateTime.now())),
                    child: const Text('Yaşımı bugün doğrula'),
                  ),
                  TextField(
                    controller: type,
                    maxLength: 4,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'KPSS puan türü (örn. P3, P93)',
                    ),
                  ),
                  TextField(
                    controller: score,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'KPSS puanınız (0–100)',
                      helperText: 'İlanın taban puanıyla karşılaştırılır.',
                      helperMaxLines: 3,
                    ),
                  ),
                  TextField(
                    controller: year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'KPSS sınav yılı (isteğe bağlı)',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('criteria-keyword'),
                    controller: keyword,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Anahtar kelime (isteğe bağlı)',
                      helperText: 'Arama adınız kişisel etikettir; ilanı bu kelimeyle süzebilirsiniz.',
                      helperMaxLines: 3,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: keywordScope,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kelimenin aranacağı alan',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'title',
                        child: Text('İlan başlığı'),
                      ),
                      DropdownMenuItem(
                        value: 'full',
                        child: Text('Başlık, kurum ve meslek'),
                      ),
                    ],
                    onChanged: (value) => update(() => keywordScope = value!),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aynı alandaki seçimler alternatiftir. Farklı alanların koşulları birlikte aranır.',
                  ),
                  criteriaSelector('cities', 'Şehirler', turkishCities, update),
                  criteriaSelector('education', 'Eğitim düzeyleri', const [
                    'Lise',
                    'Ön lisans',
                    'Lisans',
                    'Yüksek lisans',
                    'Doktora',
                  ], update),
                  criteriaSelector('categories', 'İlan türleri', const [
                    'işçi',
                    'personel',
                    'belediye',
                  ], update),
                  criteriaSelector(
                    'occupations',
                    'Meslekler',
                    occupations,
                    update,
                  ),
                  criteriaSelector(
                    'institutions',
                    'Kurumlar',
                    institutions,
                    update,
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  if (pendingChoices.values.any(
                    (c) => c.text.trim().isNotEmpty,
                  )) {
                    update(
                      () => error = 'Listeden bir seçenek seçin veya yazdığınız seçim metnini temizleyin. Serbest metin için Anahtar kelime alanını kullanın.',
                    );
                    return;
                  }
                  try {
                    if (name.text.trim().isEmpty ||
                        name.text.trim().length > 80) {
                      throw const FormatException(
                        'Arama adı 1–80 karakter olmalı.',
                      );
                    }
                    final criteria = <String, Object?>{...values};
                    criteria.remove('keyword');
                    criteria.remove('keywordScope');
                    if (keyword.text.trim().isNotEmpty) {
                      criteria['keyword'] = keyword.text.trim();
                      criteria['keywordScope'] = keywordScope;
                    }
                    criteria.remove('age');
                    criteria.remove('ageAsOf');
                    criteria.remove('kpssType');
                    criteria.remove('kpssScore');
                    criteria.remove('kpssYear');
                    if (age.text.trim().isNotEmpty) {
                      criteria['age'] = int.parse(age.text.trim());
                      criteria['ageAsOf'] = ageDate.text.trim();
                    }
                    if (type.text.trim().isNotEmpty) {
                      criteria['kpssType'] = type.text.trim().toUpperCase();
                    }
                    if (score.text.trim().isNotEmpty) {
                      criteria['kpssScore'] = double.parse(
                        score.text.trim().replaceAll(',', '.'),
                      );
                    }
                    if (year.text.trim().isNotEmpty) {
                      criteria['kpssYear'] = int.parse(year.text.trim());
                    }
                    final validated = SearchCriteria.parse(criteria);
                    final filters = <String, String>{...search.filters};
                    filters.remove('q');
                    filters.remove('sehir');
                    filters.remove('kategori');
                    if (keyword.text.trim().isNotEmpty) {
                      filters['q'] = keyword.text.trim();
                    }
                    final cities = validated.values['cities'] as List?;
                    if (cities?.length == 1) {
                      filters['sehir'] = cities!.single as String;
                    }
                    final categories = validated.values['categories'] as List?;
                    if (categories?.length == 1) {
                      final index = const [
                        'işçi',
                        'personel',
                        'belediye',
                      ].indexOf(categories!.single as String);
                      if (index >= 0) filters['kategori'] = '${index + 1}';
                    }
                    for (final key in [
                      'yas',
                      'yasTarih',
                      'egitim',
                      'kpss',
                      'kpssPuan',
                    ]) {
                      filters.remove(key);
                    }
                    if (validated.values['age'] != null) {
                      filters['yas'] = '${validated.values['age']}';
                      filters['yasTarih'] = ageDate.text.trim();
                    }
                    final education = validated.values['education'] as List?;
                    if (education?.length == 1) {
                      filters['egitim'] = education!.single as String;
                    }
                    if (validated.values['kpssType'] != null) {
                      filters['kpss'] = '${validated.values['kpssType']}';
                    }
                    if (validated.values['kpssScore'] != null) {
                      filters['kpssPuan'] = '${validated.values['kpssScore']}';
                    }
                    Navigator.pop(
                      dialogContext,
                      search.copyWith(
                        name: name.text.trim(),
                        filters: filters,
                        criteria: validated,
                      ),
                    );
                  } on FormatException {
                    update(
                      () => error = 'Kriterleri kontrol edin: yaş 16–80, tarih YYYY-AA-GG, KPSS türü P3/P93/P94 gibi, puan 0–100 ve yıl 2000–2100 olmalı. Puan için tür seçin.',
                    );
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Dialog route çıkış animasyonu bitmeden TextField controller'ını dispose etme.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final controller in [
        name,
        age,
        ageDate,
        type,
        score,
        year,
        keyword,
      ]) {
        controller.dispose();
      }
    }
  }

  /// Kayıtlı aramayı yeniden adlandırır; vazgeçilirse null döner.
  Future<String?> _promptRename(SavedSearch search) {
    final controller = TextEditingController(text: search.name);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aramayı yeniden adlandır'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Arama adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  /// Kayıtlı aramayı silmek için onay ister (C-021: kullanıcı verisi
  /// her zaman silinebilir).
  Future<bool?> _confirmDeleteSearch(SavedSearch search) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Arama silinsin mi?'),
      content: Text(
        '"${search.name}" ve bildirim tercihi bu cihazdan silinir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );

  String _modeLabel(SearchAlertMode mode) => switch (mode) {
    SearchAlertMode.instant => 'Anlık',
    SearchAlertMode.digest => 'Günlük özet',
    SearchAlertMode.off => 'Kapalı',
  };

  String _filterSummary(SavedSearch search) {
    if (search.hasInvalidCriteria) {
      return 'Kriterler okunamadı • Düzenle ile onarın';
    }
    final parts = <String>[];
    final criteria = search.effectiveCriteria.values;
    final q = criteria['keyword'] as String?;
    if (q != null && q.isNotEmpty) parts.add('"$q"');
    for (final key in [
      'categories',
      'cities',
      'occupations',
      'institutions',
      'education',
    ]) {
      final selected = criteria[key] as List?;
      if (selected != null && selected.isNotEmpty) {
        parts.add(
          selected
              .cast<String>()
              .map(
                (value) => key == 'education'
                    ? educationLabel(value)
                    : key == 'cities'
                    ? cityLabel(value)
                    : value,
              )
              .join(', '),
        );
      }
    }
    if (criteria['last30'] == true) parts.add('son 30 gün');
    final yas = criteria['age'];
    if (yas != null) {
      parts.add('yaş $yas (${criteria['ageAsOf']})');
    }
    final kpss = criteria['kpssType'] as String?;
    if (kpss != null && kpss.isNotEmpty) parts.add('KPSS $kpss');
    final score = criteria['kpssScore'];
    final year = criteria['kpssYear'];
    if (score != null) parts.add('$score puan');
    if (year != null) parts.add('$year sınavı');
    return parts.isEmpty ? 'Süzgeç yok' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    // Geri tuşu: İlanlar dışındaki sekmelerden önce İlanlar'a döner.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _tab == 0
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'KamuBul',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(const ['', 'Kaydedilenler', 'Asistan', 'Ayarlar'][_tab]),
        actions: [
          _membershipBadge(),
          IconButton(
            tooltip: 'Bildirimler',
            onPressed: () => Navigator.of(context)
                .push(sharedAxisRoute<void>(const NotificationCenterPage())),
            icon: const Icon(Icons.notifications_outlined),
          ),
          if (_tab == 0)
            IconButton(
              tooltip: 'Yenile',
              onPressed: _loading ? null : () => _refresh(manual: true),
              icon: const Icon(Icons.refresh),
            ),
          GiftFlow(
            policy: widget.policy,
            rewardedManager: widget.rewarded,
            onRewardEarned: () {
              widget.pro.grantTemporaryPro(const Duration(hours: 24));
              widget.saveAdState();
            },
          ),
        ],
      ),
      body: switch (_tab) {
        0 => _listingView(),
        1 => _savedView(),
        2 => _assistantView(),
        _ => _settingsView(),
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.pro.isPro) BannerAdWidget(controller: widget.banner),
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) {
              if (value == 4) {
                _openOtherApps();
              } else {
                setState(() => _tab = value);
              }
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.view_list_outlined),
                selectedIcon: Icon(Icons.view_list_rounded),
                label: 'İlanlar',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bookmark_outline),
                selectedIcon: Icon(Icons.bookmark_rounded),
                label: 'Kaydedilen',
              ),
              const NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome_rounded),
                label: 'Asistan',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Ayarlar',
              ),
              if (_otherApps != null)
                const NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Keşfet',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listingView() => RefreshIndicator(
    onRefresh: () => _refresh(manual: true),
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _intro()),
        SliverToBoxAdapter(child: _filters()),
        if (_loading && _records.isEmpty)
          SliverToBoxAdapter(child: listingSkeletons())
        else if (_visibleRecords.isEmpty)
          SliverFillRemaining(
            child: _emptyState(
              _error ??
                  (_uncertainCount > 0
                      ? 'Kriterlerinizi kesin karşılayan ilan yok. $_uncertainCount '
                            'ilanda bazı şartlar (ör. yaş) ilanda net yazmıyor; '
                            'göz atıp resmî metinden kontrol edebilirsiniz.'
                      : 'Bu seçimde henüz ilan yok. Süzgeçleri değiştirin ya da '
                            'listeyi aşağı çekerek yenileyin.'),
              onPressed: _clearFilters,
              uncertainAction: _uncertainCount > 0
                  ? () => setState(() => _includeUnknown = true)
                  : null,
            ),
          )
        else
          SliverList.builder(
            itemCount: _visibleRecords.length,
            itemBuilder: (_, index) => _listingCard(_visibleRecords[index]),
          ),
      ],
    ),
  );

  void _openPaywall() => Navigator.of(context).push(
    sharedAxisRoute<void>(
      ProPage(
        identity: widget.identity,
        controller: widget.pro,
        repository: widget.purchase,
        trialDays: trialDaysLeft(widget.policy, DateTime.now()),
      ),
    ),
  );

  /// Üst çubuktaki üyelik rozeti: Pro, deneme günleri ya da Pro daveti.
  Widget _membershipBadge() {
    final scheme = Theme.of(context).colorScheme;
    final pro = widget.pro.isPro;
    final days = pro ? 0 : trialDaysLeft(widget.policy, DateTime.now());
    // Dar ekran/büyük yazıda üst çubuk taşmasın: kısa etiket.
    final narrow =
        MediaQuery.sizeOf(context).width /
            MediaQuery.textScalerOf(context).scale(1) <
        330;
    final label = pro
        ? 'PRO'
        : days > 0
        ? (narrow ? '$days g' : 'Deneme · $days gün')
        : 'Pro';
    final background = pro
        ? const Color(0xFFE9B949)
        : scheme.primary.withValues(alpha: 0.12);
    final foreground = pro ? const Color(0xFF3A2A00) : scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _openPaywall,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pro
                      ? Icons.workspace_premium_rounded
                      : Icons.hourglass_bottom_rounded,
                  size: 15,
                  color: foreground,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: pro ? 1 : 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _syncLine {
    if (_tab == 1) {
      return '${_visibleRecords.length} kayıtlı ilan • çevrimdışı da açılır';
    }
    // Başarısız yenileme "güncellendi" sayılmaz; son başarılı zaman korunur.
    final cleanRefresh = _failedSources.isEmpty && !_remoteFailed
        ? _lastRefresh
        : null;
    final times = [?cleanRefresh, ?_remoteLastSuccess]..sort();
    if (times.isEmpty) {
      return _records.isEmpty
          ? 'Katalog cihazdan yükleniyor.'
          : 'Kaydedilmiş katalog • kaynaklar kontrol ediliyor';
    }
    final t = times.last;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final day = DateUtils.isSameDay(t, DateTime.now()) ? 'bugün' : _date(t);
    return 'Güncellendi $day $hhmm${_remoteFailed ? ' • önbellek' : ''} • '
        'açılışta ve aşağı çekince yenilenir';
  }

  /// Kompakt başlık: dikey alanı listeye bırakır.
  Widget _intro() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tab == 0)
            Text(
              'Güncel kamu ilanları',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                _remoteFailed ? Icons.cloud_off_rounded : Icons.sync_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _syncLine,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          if (_tab == 0 && _error != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          maxLength: 100,
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            maxLength,
          }) => null,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Aramayı temizle',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _search = '';
                      _patchQuickCriteria(['keyword']);
                    }),
                  ),
            hintText: 'Kurum veya meslek ara',
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
          onChanged: (value) => setState(() {
            _search = value;
            _patchQuickCriteria(['keyword']);
            _activeSearchId = null;
            _includeUnknown = false;
          }),
        ),
        const SizedBox(height: 10),
        Wrap(
          runSpacing: 8,
          children: [
            if (_place != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InputChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(_place!),
                  onDeleted: () => setState(() {
                    _place = null;
                    _patchQuickCriteria(['cities']);
                    _activeSearchId = null;
                    _includeUnknown = false;
                  }),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: const Text('Şehir'),
                  onPressed: _chooseCity,
                ),
              ),
            for (final (index, label) in _kategoriAdlari.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(label),
                  // "Tümü" yalnız hiçbir kriter/kayıtlı arama yokken seçili görünür.
                  selected: index == 0
                      ? _category == 0 &&
                            _activeSearchId == null &&
                            _quickCriteria == null
                      : _category == index,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    // "Tümü": kayıtlı aramadan kalan tüm kriterler dahil sıfırlanır.
                    if (index == 0) return _clearFilters();
                    setState(() {
                      _category = index;
                      _patchQuickCriteria(['categories']);
                      _activeSearchId = null;
                      _includeUnknown = false;
                    });
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: const Text('Son 30 gün'),
                selected: _last30,
                onSelected: (value) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _last30 = value;
                    _patchQuickCriteria(['last30']);
                    _activeSearchId = null;
                    _includeUnknown = false;
                  });
                },
              ),
            ),
            if (_ageFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InputChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text('Yaş uyarı: $_ageFilter'),
                  onDeleted: () => setState(() {
                    _ageFilter = null;
                    _ageAsOf = null;
                    _patchQuickCriteria(['age', 'ageAsOf']);
                    _activeSearchId = null;
                    _includeUnknown = false;
                  }),
                ),
              ),
            if (_educationFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InputChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(_educationFilter!),
                  onDeleted: () => setState(() {
                    _educationFilter = null;
                    _patchQuickCriteria(['education']);
                    _activeSearchId = null;
                    _includeUnknown = false;
                  }),
                ),
              ),
            if (_kpssFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InputChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text('KPSS $_kpssFilter'),
                  onDeleted: () => setState(() {
                    _kpssFilter = null;
                    _patchQuickCriteria([
                      'kpssType',
                      'kpssScore',
                      'kpssYear',
                      'onlyKpss',
                    ]);
                    _activeSearchId = null;
                    _includeUnknown = false;
                  }),
                ),
              ),
            if (_quickCriteria != null ||
                _activeSearch != null ||
                _place != null ||
                _ageFilter != null ||
                _educationFilter != null ||
                _kpssFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('Şartları kontrol et'),
                  selected: _includeUnknown,
                  onSelected: (value) =>
                      setState(() => _includeUnknown = value),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (_activeSearchId == null && _quickCriteria != null)
          Text(
            _filterSummary(
              SavedSearch(
                id: null,
                name: '',
                filters: _currentFilters,
                createdAt: DateTime.now(),
                criteria: _quickCriteria,
              ),
            ),
          ),
        const SizedBox(height: 12),
        _searchesCard(),
        const SizedBox(height: 10),
        Text(
          '${_visibleRecords.length} ilan',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  /// Kayıtlı aramalar ("Sizin için" dahil) ve yeni kriter ekleme; tek kart.
  Widget _searchesCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aramalarım',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (_searches.isNotEmpty)
                IconButton(
                  tooltip: 'Kayıtlı aramaları yönet',
                  onPressed: _manageSearches,
                  icon: const Icon(Icons.manage_search),
                ),
            ],
          ),
          if (_searches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 8),
              child: Text(
                'Kriterlerinizi kaydedin, uygun ilanlar öne çıksın.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final search in _searches)
                ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(search.name),
                  selected: _activeSearchId == search.id,
                  // Tekrar dokununca seçim kalkar, liste tüm ilanlara döner.
                  onSelected: (_) => _activeSearchId == search.id
                      ? _clearFilters()
                      : _applySearch(search),
                ),
              Tooltip(
                message: 'Bu aramayı kaydet',
                child: ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  label: const Text('Kriter ekle'),
                  onPressed: _saveCurrentSearch,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listingCard(ListingRecord record) {
    final unresolved = _matchVisible(record) == CriteriaMatch.unknown;
    final expired = record.expired;
    final profileMatch = _searches.any(
      (search) =>
          !search.hasInvalidCriteria &&
          search.name == 'Sizin için' &&
          ((search.criteria?.values.keys.any(
                    (key) => !['version', 'keywordScope'].contains(key),
                  ) ??
                  false) ||
              [
                'sehir',
                'yas',
                'egitim',
                'kpss',
              ].any((key) => (search.filters[key] ?? '').isNotEmpty)) &&
          search.matchListing(record, now: DateTime.now()) ==
              CriteriaMatch.match,
    );
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final estimate = record.deadline == null ? record.deadlineEstimate : null;
    final shownDeadline = record.deadline ?? estimate;
    final days = deadlineDays(shownDeadline, now);
    final variedDeadlines = record.applicationPeriods.isNotEmpty;
    final positionCount = record.positions.length;
    final deadlineText = variedDeadlines
        ? 'Başvuru takvimini inceleyin'
        : shownDeadline != null
        ? '${estimate != null ? '≈ ' : ''}${_date(shownDeadline)} • ${countdownLabel(shownDeadline, now)}'
        : switch (record.noticeKind) {
            'amendment' => 'Düzeltme ilanı',
            'cancellation' => 'İptal ilanı',
            _ when record.detailOnSource => 'Tarih Kariyer Kapısı’nda',
            _ => 'Son tarih belirtilmemiş',
          };
    final facts = <Widget>[
      if (record.noticeKind == 'register')
        _factChip(Icons.how_to_reg_outlined, 'Liste başvurusu')
      else if (record.quota != null)
        _factChip(
          record.fieldFromAi('quota')
              ? Icons.auto_awesome_outlined
              : Icons.groups_outlined,
          '${record.quota} kişi',
        ),
      if (positionCount > 1)
        _factChip(Icons.work_outline_rounded, '$positionCount pozisyon'),
      if (record.places.isNotEmpty)
        _factChip(Icons.place_outlined, record.places.join(', ')),
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _showListing(record),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InstitutionAvatar(title: record.title),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          // Kurum adı kategoriden ("Personel Alımı") daha çok bilgi taşır.
                          child: Text(
                            turkishTitleCase(
                              record.institution ??
                                  (record.category.isEmpty
                                      ? 'Kamu ilanı'
                                      : record.category),
                            ),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16.5,
                                letterSpacing: -0.2,
                                height: 1.3,
                              ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: record.saved ? 'Kaydı kaldır' : 'Kaydet',
                    onPressed: () => _toggleSaved(record),
                    icon: Icon(
                      record.saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: record.saved ? scheme.primary : null,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 10),
                child: Text(
                  record.publishedAt == null
                      ? _sourceLabel(record.sourceId)
                      : '${_sourceLabel(record.sourceId)}  ·  Yayın ${_date(record.publishedAt)}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (unresolved)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: PremiumStatus.held(Theme.of(context).brightness),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Şartları kontrol et • bazı kriterler doğrulanamadı.',
                        ),
                      ),
                    ],
                  ),
                ),
              if (_tab == 1 &&
                  record.publishedAt != null &&
                  record.publishedAt!.isAfter(DateTime.now()))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Yayın tarihi bekleniyor',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.primary),
                  ),
                ),
              if (profileMatch)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '✓ Arama tercihlerinizle eşleşiyor',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.primary),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    DeadlinePill(
                      text: deadlineText,
                      daysLeft: variedDeadlines ? null : days,
                      expired: expired || (estimate != null && days == -1),
                    ),
                    ...facts,
                  ],
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => _showListing(record),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('İlanı incele'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      if (_assistantListing?.url != record.url) {
                        _chatMessages.clear();
                      }
                      _assistantListing = record;
                      _tab = 2;
                    }),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Asistana sor'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _factChip(IconData icon, String label, {bool urgent = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: urgent
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  void _showListing(ListingRecord record) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(sharedAxisRoute<void>(_listingPage(record)));
  }

  Widget _listingPage(ListingRecord record) => OfficialListingPage(
    listing: record,
    unavailable: record.criteriaListing?['active'] == false,
    onAskAssistant: () => _askAssistantAbout(record),
  );

  Widget _savedView() => _visibleRecords.isEmpty
      ? _emptyState(
          'Kaydedilen ilanlar burada görünecek. Kaynak ilanı kaldırsa da kaydınız korunur.',
          onPressed: () => setState(() => _tab = 0),
        )
      : ListView(children: [_intro(), ..._visibleRecords.map(_listingCard)]);

  late final AssistantClient _assistantClient = AssistantClient(
    store: widget.store,
  );
  final List<ChatMessage> _chatMessages = [];

  SavedSearch? _assistantSearch(Map<String, Object?> raw) {
    try {
      return SavedSearch(
        id: null,
        name: '',
        filters: const {},
        criteria: SearchCriteria.parse(raw),
        createdAt: DateTime.now(),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _applyAssistantCriteria(Map<String, Object?> raw) async {
    final seed = _assistantSearch(raw);
    if (seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önerilen kriterler doğrulanamadı.')),
      );
      return;
    }
    var saved = await _promptEditSearch(seed, creating: true);
    if (saved == null) return;
    saved = await _store.addSavedSearch(saved);
    await _loadLocal();
    if (!mounted) return;
    _applySearch(saved);
    setState(() => _tab = 0);
    await _maybeAskNotificationPermission();
  }

  Widget _assistantView() {
    final selected =
        _records.where((r) => r.url == _assistantListing?.url).firstOrNull ??
        _assistantListing;
    return AssistantChatView(
      key: ValueKey(selected?.url),
      client: _assistantClient,
      messages: _chatMessages,
      listingTitle: selected?.title,
      listingId: selected?.criteriaListing?['id'] as String?,
      listingRevision: selected?.criteriaListing?['revision'] as int?,
      loadListingText: selected == null
          ? null
          : () => _listingContext(selected),
      onClearListing: selected == null
          ? null
          : () => setState(() {
              _assistantListing = null;
              _chatMessages.clear();
            }),
      onOpenListing: selected == null ? null : () => _showListing(selected),
      criteriaSummary: (raw) {
        final search = _assistantSearch(raw);
        return search == null ? '' : _filterSummary(search);
      },
      onSaveCriteria: _applyAssistantCriteria,
      listingGuide: selected == null
          ? null
          : ListingGuideView(listing: selected),
      isPro: widget.pro.isPro,
      onUpgrade: _openPaywall,
      onNewChat: () => setState(() {
        _assistantListing = null;
        _chatMessages.clear();
      }),
      profile: _assistantProfile(),
    );
  }

  /// "Bana uygun mu?" için kullanıcının kayıtlı kriterleri (salt okunur):
  /// önce "Sizin için", yoksa etkin arama, yoksa ilk geçerli arama.
  Map<String, Object?>? _assistantProfile() {
    final candidates = [
      ..._searches.where((s) => s.name == 'Sizin için'),
      ..._searches.where((s) => s.id == _activeSearchId),
      ..._searches,
    ];
    for (final search in candidates) {
      if (search.hasInvalidCriteria) continue;
      try {
        final values = {...search.effectiveCriteria.values}
          ..remove('version')
          ..remove('keywordScope');
        if (values.isNotEmpty) return values;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// İlan ayrıntısından "Asistana sor": ayrıntıyı kapatıp seçili ilanla
  /// Asistan sekmesini açar.
  void _askAssistantAbout(ListingRecord record) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      if (_assistantListing?.url != record.url) _chatMessages.clear();
      _assistantListing = record;
      _tab = 2;
    });
  }

  /// Asistan yalnız indirilen sunucu metnini kullanır; resmî siteyi yeniden okumaz.
  Future<String?> _listingContext(ListingRecord record) async {
    final current =
        _records.where((r) => r.url == record.url).firstOrNull ?? record;
    if (current.noticeText.isEmpty) return null;
    return [
      current.title,
      if (current.category.isNotEmpty) 'Kategori: ${current.category}',
      if (current.deadline != null) 'Son başvuru: ${_date(current.deadline)}',
      if (current.quota != null) 'Kontenjan: ${current.quota}',
      if (current.places.isNotEmpty) 'Yerler: ${current.places.join(', ')}',
      current.noticeText,
    ].join('\n');
  }

  void _showServerPushInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sunucudan anlık bildirim'),
      content: const SingleChildScrollView(
        child: Text(
          'Açtığınızda kurulum kimliğiniz, bildirim jetonunuz ve bildirimi açık '
          'aramalarınızın adları, kriterleri ve tercihleri Cloudflare '
          'sunucusuna gönderilir; yeni ilan bu kriterlere uyunca bildirim '
          'gelir. Sessiz saatler 22:00–08:00.\n\nKapatınca yalnız sunucudaki '
          'bu bildirim kaydı silinir. Cihazınızdaki aramalarınız, '
          'kriterleriniz ve kaydettiğiniz ilanlar SİLİNMEZ; uygulama '
          'kapansa ya da günler geçse de yerinde kalır. Ayrıntı için '
          'gizlilik politikasına bakın.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );

  Widget _proCard() {
    final scheme = Theme.of(context).colorScheme;
    final trialDays = trialDaysLeft(widget.policy, DateTime.now());
    final isPro = widget.pro.isPro;
    final text = isPro
        ? 'Pro etkin. Teşekkürler; reklamlar kapalı.'
        : trialDays > 0
        ? '${trialDays == 1 ? 'Reklamsız deneme son gün. ' : 'Reklamsız deneme: $trialDays gün kaldı. '}'
              'Sonrasında küçük banner ve seyrek tam ekran reklamlar gelir; '
              'aylık Pro bunları kaldırır.'
        : 'Reklamsız deneyim ve Asistan’da günde 100 soru hakkı. '
              'Dilediğiniz zaman iptal edebilirsiniz.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(PremiumShape.barRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PremiumShape.barRadius),
          onTap: _openPaywall,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KamuBul Pro',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: TextStyle(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.9,
                          ),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsView() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _proCard(),
      SettingsGroup(
        title: 'Görünüm ve üyelik',
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Tema'),
            trailing: DropdownButton<ThemeMode>(
              value: widget.theme.mode,
              onChanged: (value) {
                if (value != null) widget.theme.setMode(value);
              },
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Sistem'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Açık')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Koyu')),
              ],
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Bildirimler',
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Bildirimler'),
            subtitle: const Text('Uygun ilanlar ve son başvuru hatırlatmaları'),
            onTap: () async {
              final granted = await requestAlertPermission(context);
              if (!mounted) return;
              if (granted) await runAlertCheckNow();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    granted
                        ? 'Bildirimler açık. Uygun yeni ilanlar ve son başvuru '
                              'hatırlatmaları gelecek.'
                        : 'Bildirim izni verilmedi; uygulama yine de çalışır.',
                  ),
                ),
              );
            },
          ),
          if (pushRegistrar != null)
            SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: const Text('Sunucudan anlık bildirim'),
              subtitle: Text.rich(
                TextSpan(
                  text: 'Uygulama kapalıyken de yeni ilan bildirimi. ',
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: InkWell(
                        onTap: _showServerPushInfo,
                        child: Text(
                          'Ayrıntılar',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              value: pushRegistrar!.enabled,
              onChanged: _setServerPush,
            ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Bildirim geçmişi'),
            subtitle: const Text('Gönderilen ve bekleyen uyarılar'),
            onTap: () => Navigator.of(context)
                .push(sharedAxisRoute<void>(const NotificationCenterPage())),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Kaynaklar',
        children: [
          if (_otherApps != null)
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Diğer uygulamalarımız'),
              subtitle: const Text('Uygulamalarımızı keşfedin.'),
              onTap: _openOtherApps,
            ),
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: const Text('Resmî kaynaklar'),
            onTap: () => Navigator.of(context).push(
              sharedAxisRoute<void>(
                _SourcesPage(
                  open: _open,
                  checkedAt: _remoteLastSuccess ?? _lastRefresh,
                  failedSources: _failedSources,
                  sourceStatuses: _sourceStatuses,
                ),
              ),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Veriler ve geri bildirim',
        children: [
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Uygulamayı paylaş'),
            onTap: _shareApp,
          ),
          ListTile(
            leading: const Icon(Icons.star_rate_outlined),
            title: const Text('Puan ver'),
            onTap: _openRatePage,
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Verileri dışa aktar'),
            subtitle: const Text(
              'Kayıtlı aramalar ve yer imleri JSON yedeği olur.',
            ),
            onTap: _exportData,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Verileri içe aktar'),
            subtitle: const Text(
              'Yedek yapıştırılır; mevcut kayıtlar korunur.',
            ),
            onTap: _importData,
          ),
        ],
      ),
      SettingsGroup(
        title: 'Hakkında',
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Hakkında ve lisanslar'),
            onTap: () => Navigator.of(
              context,
            ).push(sharedAxisRoute<void>(AboutPage(identity: widget.identity))),
          ),
        ],
      ),
    ],
  );

  /// Kesin eşleşme yokken şartları net olmayan (bilinmeyen) ilan sayısı.
  int get _uncertainCount => _includeUnknown
      ? 0
      : _records
            .where(
              (r) =>
                  (_tab != 1 || r.saved) &&
                  _matchVisible(r) == CriteriaMatch.unknown,
            )
            .length;

  Widget _emptyState(
    String message, {
    required VoidCallback onPressed,
    VoidCallback? uncertainAction,
  }) => Center(
    // 1.3x metinde bile taşma olmasın: içerik kırpılmak yerine kayar.
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (uncertainAction != null) ...[
            FilledButton(
              onPressed: uncertainAction,
              child: Text('$_uncertainCount ilanı göster'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: onPressed,
            child: const Text('Süzgeçleri temizle'),
          ),
        ],
      ),
    ),
  );

  String _sourceLabel(String sourceId) => switch (sourceId) {
    'sbb' || 'kamuilan_sbb' => 'Kamu İlanları (SBB)',
    'kariyerkapisi' => 'Kariyer Kapısı',
    'iskur' => 'İŞKUR',
    'ilangov' => 'ilan.gov.tr',
    'resmigazete' => 'Resmî Gazete',
    _ => 'Resmî kaynak',
  };

  String _date(DateTime? value) => value == null
      ? 'Yayın tarihi belirtilmemiş'
      : '${value.day}.${value.month}.${value.year}';
}

class _SourcesPage extends StatelessWidget {
  const _SourcesPage({
    required this.open,
    required this.checkedAt,
    required this.failedSources,
    this.sourceStatuses = const [],
  });
  final Future<void> Function(Uri) open;
  final DateTime? checkedAt;
  final List<String> failedSources;

  /// Sunucunun bildirdiği kaynak durumları (boşsa sunucu kapalı/okunamadı).
  final List<SourceStatus> sourceStatuses;

  SourceStatus? _serverStatus(String id) =>
      sourceStatuses.where((s) => s.id == id).firstOrNull ??
      (id == 'sbb'
          ? sourceStatuses.where((s) => s.id == 'kamuilan_sbb').firstOrNull
          : null);
  String? _serverNote(String id) => _serverStatus(id)?.note;
  String _serverLabel(String id) => switch (_serverStatus(id)?.state) {
    SourceState.ok => 'Listeye erişildi',
    SourceState.failed => 'Kaynak yenilenemedi',
    SourceState.blocked => 'Kaynağa erişim engellendi',
    SourceState.disabled => 'Kaynak kapalı',
    null => 'Kaynak henüz denetlenmedi',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Resmî kaynaklar')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.update_outlined),
          title: Text(
            sourceStatuses.isEmpty ? 'Son denetim' : 'Son başarılı eşitleme',
          ),
          subtitle: Text(
            checkedAt == null
                ? 'Bu oturumda henüz denetlenmedi'
                : '${checkedAt!.day}.${checkedAt!.month}.${checkedAt!.year} '
                      '${checkedAt!.hour.toString().padLeft(2, '0')}:${checkedAt!.minute.toString().padLeft(2, '0')}',
          ),
        ),
        for (final (name, id, description) in [
          (
            'Kariyer Kapısı',
            'kariyerkapisi',
            'Resmî liste ve ilan metinleri sunucuda okunur; ayrıntılar cihazda saklanır.',
          ),
          (
            'Kamu İlanları (SBB)',
            'sbb',
            'Güncel yıl listesi; asıl ilan resmî PDF belgedir.',
          ),
          (
            'ilan.gov.tr',
            kIlanGovSourceId,
            'Personel alımı ilanları (belediye, üniversite, Resmî Gazete) '
                'sunucuda resmî portaldan okunur.',
          ),
          (
            'İŞKUR',
            kIskurSourceId,
            'Yalnız kamu işçi alımları (belediye vb.); özel sektör ilanları '
                'alınmaz.',
          ),
        ])
          ListTile(
            leading: Icon(
              _serverStatus(id) != null
                  ? _serverStatus(id)!.state == SourceState.ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline
                  : Icons.help_outline,
            ),
            title: Text(name),
            subtitle: Text(
              _serverStatus(id) != null
                  ? '${_serverLabel(id)}. ${_serverNote(id) ?? description}'
                  : checkedAt != null && failedSources.contains(name)
                  ? 'Son denetim başarısız; önbellek korunuyor. $description'
                  : 'Kaynak henüz denetlenmedi. $description',
            ),
          ),
        const ListTile(
          leading: Icon(Icons.location_city_outlined),
          title: Text('Belediyeler'),
          subtitle: Text(
            'Belediye personel ilanları ilan.gov.tr (Basın İlan Kurumu) ve '
            'İŞKUR kamu ilanlarıyla gelir; "Belediye" süzgeciyle bulunur. '
            'İlanını yalnız kendi sitesinde yayımlayan belediyeler şimdilik '
            'kapsam dışıdır.',
          ),
        ),
      ],
    ),
  );
}

/// Yedek JSON'unun yapıştırıldığı içe aktarma penceresi; metin denetçisi
/// kendi ömründe tutulur.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verileri içe aktar'),
    content: TextField(
      controller: _controller,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: 'Yedek JSON',
        helperText: 'Yalnızca KamuBul yedek dosyası kabul edilir.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('İçe aktar'),
      ),
    ],
  );
}
