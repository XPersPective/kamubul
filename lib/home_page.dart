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
import 'package:url_launcher/url_launcher.dart';

import 'data/catalogue_refresh.dart';
import 'data/listing_store.dart';
import 'data/remote_sync.dart';
import 'data/search_alerts.dart';
import 'data/turkish_cities.dart';
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

part 'ui/source_status_page.dart';
part 'ui/home_searches.dart';
part 'ui/home_listing_card.dart';
part 'ui/home_settings.dart';

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

  /// Kriterlere göre sıralama: kesin uyanlar önce, bilinmeyenler sonra;
  /// her grup içinde mevcut (yayın tarihi) sırası korunur.
  /// Her setState'te sıfırlanır: kaydırırken her kart için ~300 ilanı yeniden
  /// eşleştirmek (O(n²)) listeyi takılarak kaydırıyordu.
  List<ListingRecord>? _visibleCache;
  final _matchCache = <ListingRecord, CriteriaMatch>{};
  final _profileMatchCache = <ListingRecord, bool>{};

  /// Part dosyalarındaki uzantılar korumalı setState'i bununla çağırır.
  void _update(VoidCallback fn) => setState(fn);

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
    _matchCache.clear();
    _profileMatchCache.clear();
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

  CriteriaMatch _matchVisible(ListingRecord record) =>
      _matchCache.putIfAbsent(record, () => _computeVisibleMatch(record));

  CriteriaMatch _computeVisibleMatch(ListingRecord record) {
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
    return TextButton(
      onPressed: _openPaywall,
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
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
    // Kısa durum: simge + saat; yenileme aşağı çekerek yapılır.
    final day = DateUtils.isSameDay(t, DateTime.now()) ? 'Bugün' : _date(t);
    return '$day $hhmm';
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
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: const Text('Şehir'),
                  onPressed: _chooseCity,
                ),
              ),
            for (final (index, label) in _kategoriAdlari.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
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
                  label: Text('Yaş: $_ageFilter'),
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
                Tooltip(
                  message: 'Kayıtlı aramaları yönet',
                  child: TextButton.icon(
                    onPressed: _manageSearches,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Yönet'),
                  ),
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
