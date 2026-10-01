import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kamubul_core/kamubul_core.dart'
    show
        SourceStatus,
        SourceState,
        CatalogueMetadata,
        SearchCriteria,
        CriteriaMatch;
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/catalogue_refresh.dart';
import 'data/listing_store.dart';
import 'data/search_alerts.dart';
import 'data/turkish_cities.dart';
import 'data/user_data.dart';
import 'notifications/alert_service.dart';
import 'notifications/notification_center_page.dart';
import 'notifications/push_registration.dart';
import 'notifications/push_setup.dart';
import 'listings/kariyer_detail.dart';
import 'listings/kariyer_detail_page.dart';
import 'listings/extract_conditions.dart';
import 'listings/kariyer_feed.dart';
import 'listings/listing_guide.dart';
import 'listings/official_listing_page.dart';
import 'rate_prompt_state.dart';
import 'ui/premium.dart';
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
  String? _educationFilter;
  String? _kpssFilter;
  int? _activeSearchId;
  bool _includeUnknown = false;

  SavedSearch? get _activeSearch =>
      _searches.where((s) => s.id == _activeSearchId).firstOrNull;
  bool _loading = false;
  bool _cityLoading = false;
  String? _cityError;
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

  /// Bildirim dokunuşu hedefi: yerel kayıt uygulama içinde açılır; kayıt
  /// budanmışsa resmî sayfa dışarıda açılır.
  Future<void> _openAlertFromNotification() async {
    final url = alertTapUrl.value;
    if (url == null) return;
    alertTapUrl.value = null;
    await _loadLocal();
    if (!mounted) return;
    ListingRecord? record;
    for (final candidate in _records) {
      if (candidate.url == url) record = candidate;
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
    _showListing(record);
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
          ? 'Sunucu bildirimleri kapatıldı; kaydınız silindi.'
          : registrar.enabled
          ? 'Kapatma işlemi kaydedilemedi; yeniden deneyin.'
          : 'Kapatıldı; kaydınız bağlantı gelince silinecek.';
    }
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
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

  Future<void> _cacheDetail(String url, KariyerDetail detail) async {
    await _store.applyDetail(
      url,
      deadline: detail.deadline,
      quota: detail.quota > 0 ? detail.quota : null,
      places: detail.places,
    );
    final conditionText = [
      detail.body,
      for (final position in detail.positions) position.conditions,
    ].join('\n');
    await _store.applyConditions(url, extractConditions(conditionText));
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

  List<ListingRecord> get _visibleRecords {
    final filters = _currentFilters;
    final active = _activeSearch;
    if (_tab == 1) filters['kategori'] = '0';
    return _records.where((record) {
      if (_tab == 1 && !record.saved) return false;
      if (active != null) {
        final match = active.matchListing(record, now: DateTime.now());
        return match == CriteriaMatch.match ||
            (_includeUnknown && match == CriteriaMatch.unknown);
      }
      return matchesFilters(record, filters, forSaved: _tab == 1);
    }).toList();
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
    final city = search.filters['sehir'];
    setState(() {
      _search = search.filters['q'] ?? '';
      _category = int.tryParse(search.filters['kategori'] ?? '') ?? 0;
      _last30 = search.filters['son30'] == '1';
      _place = (search.filters['sehir'] ?? '').isEmpty
          ? null
          : search.filters['sehir'];
      _ageFilter = int.tryParse(search.filters['yas'] ?? '');
      _educationFilter = (search.filters['egitim'] ?? '').isEmpty
          ? null
          : search.filters['egitim'];
      _kpssFilter = (search.filters['kpss'] ?? '').isEmpty
          ? null
          : search.filters['kpss'];
      _activeSearchId = search.id;
      _includeUnknown = false;
    });
    if (city != null && city.isNotEmpty) _refreshCity(city);
  }

  Future<void> _refreshCity(String city) async {
    setState(() {
      _cityLoading = true;
      _cityError = null;
    });
    try {
      await refreshKariyerCity(_store, city);
      await _loadLocal();
    } on Exception {
      if (mounted && _place == city) {
        setState(
          () => _cityError = 'Şehir kaynağına ulaşılamadı; yalnızca önceden doğrulanmış yerler gösteriliyor.',
        );
      }
    } finally {
      if (mounted && _place == city) setState(() => _cityLoading = false);
    }
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
                      ? 'Şehir yazın; resmî kaynakta doğrulayalım.'
                      : canonical == null
                      ? '81 ilden birini yazın.'
                      : '$canonical • önbellekte $known doğrulanmış ilan; kaynak sorgusuyla tamamlanır',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canonical == null
                        ? null
                        : () => Navigator.pop(sheetContext, canonical),
                    child: const Text('Resmî kaynakta ara'),
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
      _activeSearchId = null;
      _includeUnknown = false;
    });
    await _refreshCity(chosen);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _category = 0;
      _last30 = false;
      _place = null;
      _ageFilter = null;
      _educationFilter = null;
      _kpssFilter = null;
      _activeSearchId = null;
      _includeUnknown = false;
      _cityError = null;
      _cityLoading = false;
    });
  }

  Map<String, String> get _currentFilters => {
    'q': _search,
    'kategori': '$_category',
    'son30': _last30 ? '1' : '0',
    'sehir': ?_place,
    'yas': ?_ageFilter?.toString(),
    'egitim': ?_educationFilter,
    'kpss': ?_kpssFilter,
  };

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
    if (mounted) setState(() => _activeSearchId = saved!.id);
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
                      if (_activeSearchId == search.id) {
                        _activeSearchId = null;
                        _includeUnknown = false;
                      }
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
    final ageDate = TextEditingController(
      text:
          '${values['ageAsOf'] ?? DateTime.now().toIso8601String().substring(0, 10)}',
    );
    final educationValues =
        (values['education'] as List?)?.cast<String>() ?? <String>[];
    var education = educationValues.length == 1 ? educationValues.single : null;
    var educationChanged = false;
    String? error;
    try {
      return await showDialog<SavedSearch>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text(creating ? 'Aramayı kaydet' : 'Aramayı düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    ),
                  ),
                  TextField(
                    controller: ageDate,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Yaş bilgisi tarihi (YYYY-AA-GG)',
                    ),
                  ),
                  TextButton(
                    onPressed: () => ageDate.text = DateTime.now()
                        .toIso8601String()
                        .substring(0, 10),
                    child: const Text('Yaşımı bugün doğrula'),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: education,
                    decoration: const InputDecoration(
                      labelText: 'Eğitim düzeyi (isteğe bağlı)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Eğitim filtresi yok'),
                      ),
                      for (final value in {
                        'Lise',
                        'Ön lisans',
                        'Lisans',
                        'Yüksek lisans',
                        'Doktora',
                        ...educationValues,
                      })
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) => update(() {
                      education = value;
                      educationChanged = true;
                    }),
                  ),
                  if (educationValues.length > 1)
                    Text(
                      'Kayıtlı eğitimler: ${educationValues.join(', ')}. Yeni seçim yapmazsanız hepsi korunur.',
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
                    ),
                  ),
                  TextField(
                    controller: year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'KPSS sınav yılı (isteğe bağlı)',
                    ),
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
                  try {
                    if (name.text.trim().isEmpty ||
                        name.text.trim().length > 80) {
                      throw const FormatException(
                        'Arama adı 1–80 karakter olmalı.',
                      );
                    }
                    final criteria = <String, Object?>{...values};
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
                    if (educationChanged) {
                      criteria.remove('education');
                      if (education != null) {
                        criteria['education'] = [education!];
                      }
                    }
                    final validated = SearchCriteria.parse(criteria);
                    final filters = <String, String>{...search.filters};
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
                    if (education != null) filters['egitim'] = education!;
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
      for (final controller in [name, age, ageDate, type, score, year]) {
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
    final q = search.filters['q'];
    if (q != null && q.isNotEmpty) parts.add('"$q"');
    final kategori = int.tryParse(search.filters['kategori'] ?? '') ?? 0;
    if (kategori > 0 && kategori < _kategoriAdlari.length) {
      parts.add(_kategoriAdlari[kategori]);
    }
    if (search.filters['son30'] == '1') parts.add('son 30 gün');
    final sehir = search.filters['sehir'];
    if (sehir != null && sehir.isNotEmpty) parts.add(sehir);
    final yas = search.filters['yas'];
    if (yas != null && yas.isNotEmpty) parts.add('yaş $yas');
    final egitim = search.filters['egitim'];
    if (egitim != null && egitim.isNotEmpty) parts.add(egitim);
    final kpss = search.filters['kpss'];
    if (kpss != null && kpss.isNotEmpty) parts.add('KPSS $kpss');
    final score = search.criteria?.values['kpssScore'];
    final year = search.criteria?.values['kpssYear'];
    if (score != null) parts.add('$score puan');
    if (year != null) parts.add('$year sınavı');
    return parts.isEmpty ? 'Süzgeç yok' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.account_balance_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            const Text('KamuBul'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bildirimler',
            onPressed: () => Navigator.of(context)
                .push(sharedAxisRoute<void>(const NotificationCenterPage())),
            icon: const Icon(Icons.notifications_outlined),
          ),
          if (_tab == 0)
            IconButton(
              tooltip: 'Yenile',
              onPressed: _loading ? null : _refresh,
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
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.view_list_outlined),
                label: 'İlanlar',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmark_outline),
                label: 'Kaydedilen',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                label: 'Rehber',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                label: 'Ayarlar',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listingView() => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(child: _intro()),
      SliverToBoxAdapter(child: _filters()),
      if (_loading && _records.isEmpty)
        SliverToBoxAdapter(child: listingSkeletons())
      else if (_visibleRecords.isEmpty)
        SliverFillRemaining(
          child: _emptyState(
            _error ??
                (_category == 1
                    ? 'Bu seçimde doğrulanmış işçi ilanı yok. İŞKUR otomatik bağlantısı henüz hazır değil.'
                    : 'Bu seçimde henüz doğrulanmış ilan yok.'),
            onPressed: _clearFilters,
          ),
        )
      else
        SliverList.builder(
          itemCount: _visibleRecords.length,
          itemBuilder: (_, index) => _listingCard(_visibleRecords[index]),
        ),
    ],
  );

  Widget _intro() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(PremiumShape.barRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tab == 1 ? 'KİŞİSEL LİSTE' : 'RESMÎ KAYNAKLAR',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tab == 1 ? 'Kaydettiğiniz ilanlar' : 'Güncel kamu ilanları',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tab == 1
                ? '${_visibleRecords.length} kayıt • çevrimdışı erişim'
                : _remoteLastSuccess != null
                ? 'Son eşitleme ${_date(_remoteLastSuccess)} ${_remoteLastSuccess!.hour.toString().padLeft(2, '0')}:${_remoteLastSuccess!.minute.toString().padLeft(2, '0')} • ${_records.where((record) => matchesFilters(record, const {})).length} ilan${_remoteFailed || DateTime.now().difference(_remoteLastSuccess!) > remoteSnapshotMaxAge ? ' • Önbellek' : ''}'
                : _lastRefresh == null
                ? _records.isEmpty
                      ? 'Katalog cihazdan yükleniyor.'
                      : 'Kaydedilmiş katalog gösteriliyor • kaynaklar kontrol ediliyor'
                : 'Son kontrol ${_lastRefresh!.hour.toString().padLeft(2, '0')}:${_lastRefresh!.minute.toString().padLeft(2, '0')} • ${_records.where((record) => matchesFilters(record, const {})).length} ilan',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          if (_tab == 0 && _error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _filters() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Kurum veya meslek ara',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            filled: true,
          ),
          onChanged: (value) => setState(() {
            _search = value;
            _activeSearchId = null;
            _includeUnknown = false;
          }),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (_place != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text(_place!),
                    onDeleted: () => setState(() {
                      _place = null;
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
              if (_activeSearch != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Şartları kontrol et'),
                    selected: _includeUnknown,
                    onSelected: (value) =>
                        setState(() => _includeUnknown = value),
                  ),
                ),
              for (final (index, label) in _kategoriAdlari.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _category == index,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _category = index;
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
                    label: Text('Yaş uyarı: $_ageFilter'),
                    onDeleted: () => setState(() {
                      _ageFilter = null;
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
                      _activeSearchId = null;
                      _includeUnknown = false;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (_cityLoading) const LinearProgressIndicator(),
        if (_cityError != null)
          Text(
            _cityError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '${_visibleRecords.length} ilan',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Row(
          children: [
            Expanded(child: _savedSearchChips()),
            IconButton(
              tooltip: 'Bu aramayı kaydet',
              onPressed: _saveCurrentSearch,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            IconButton(
              tooltip: 'Kayıtlı aramaları yönet',
              onPressed: _manageSearches,
              icon: const Icon(Icons.manage_search),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _savedSearchChips() {
    if (_searches.isEmpty) {
      return Text(
        'Süzgeçleri kaydedip tek dokunuşla uygulayın.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final search in _searches)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(search.name),
                selected: _activeSearchId == search.id,
                onSelected: (_) => _applySearch(search),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listingCard(ListingRecord record) {
    final unresolved =
        _activeSearch?.matchListing(record, now: DateTime.now()) ==
        CriteriaMatch.unknown;
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _showListing(record),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unresolved)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Şartları kontrol et • bazı kriterler doğrulanamadı.',
                  ),
                ),
              Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.category.isEmpty ? 'Kamu ilanı' : record.category,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: record.saved ? 'Kaydı kaldır' : 'Kaydet',
                    onPressed: () => _toggleSaved(record),
                    icon: Icon(
                      record.saved ? Icons.bookmark : Icons.bookmark_outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                record.title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Text(
                '${_sourceLabel(record.sourceId)} • Yayın ${_date(record.publishedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_tab == 1 &&
                  record.publishedAt != null &&
                  record.publishedAt!.isAfter(DateTime.now()))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Yayın tarihi bekleniyor',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (profileMatch)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '✓ Arama tercihlerinizle eşleşiyor',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _factChip(
                    Icons.event_outlined,
                    record.deadline == null
                        ? 'Son tarih belirtilmemiş'
                        : '${_date(record.deadline)} • ${countdownLabel(record.deadline, DateTime.now())}',
                    urgent: expired,
                  ),
                  if (record.quota != null)
                    _factChip(Icons.groups_outlined, '${record.quota} kişi'),
                  if (record.places.isNotEmpty)
                    _factChip(Icons.place_outlined, record.places.join(', ')),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _showListing(record),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('İlanı incele'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _assistantListing = record;
                      _tab = 2;
                    }),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Rehbere sor'),
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
            Icon(icon, size: 16),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  void _showListing(ListingRecord record) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      sharedAxisRoute<void>(
        record.sourceId == 'kariyerkapisi'
            ? KariyerDetailPage(
                listing: _asPublicListing(record),
                summary: record.summary,
                onLoaded: (detail) => _cacheDetail(record.url, detail),
              )
            : OfficialListingPage(listing: record),
      ),
    );
  }

  PublicListing _asPublicListing(ListingRecord record) => PublicListing(
    title: record.title,
    category: record.category,
    url: Uri.parse(record.url),
    publishedAt: record.publishedAt,
  );

  Widget _savedView() => _visibleRecords.isEmpty
      ? _emptyState(
          'Kaydedilen ilanlar burada görünecek. Kaynak ilanı kaldırsa da kaydınız korunur.',
          onPressed: () => setState(() => _tab = 0),
        )
      : ListView(children: [_intro(), ..._visibleRecords.map(_listingCard)]);

  Widget _assistantView() {
    final selected = _assistantListing;
    SavedSearch? profile;
    for (final search in _searches) {
      if (search.name == 'Sizin için') profile = search;
    }
    if (selected != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (profile != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Arama tercihleriniz'),
                subtitle: Text(_filterSummary(profile)),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {
                  _applySearch(profile!);
                  setState(() => _tab = 0);
                },
              ),
            ),
          Text('Seçili ilan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            child: ListTile(
              title: Text(selected.title),
              trailing: const Icon(Icons.article_outlined),
              onTap: () => _showListing(selected),
            ),
          ),
          const SizedBox(height: 8),
          ListingGuideView(listing: selected),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.auto_awesome,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('İlan Rehberi', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Bir ilanın yanındaki "Rehbere sor" düğmesine dokunun; yaş, eğitim, '
          'KPSS gibi koşulları kaynak cümlesiyle yanıtlayalım. Serbest soru '
          'sorma (yapay zekâ sohbeti) hazırlanıyor.',
        ),
        if (profile != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_search_outlined),
              title: const Text('Sizin için arama'),
              subtitle: Text(_filterSummary(profile)),
              onTap: () {
                _applySearch(profile!);
                setState(() => _tab = 0);
              },
            ),
          ),
      ],
    );
  }

  Widget _settingsView() => ListView(
    children: [
      const ListTile(
        title: Text('Görünüm ve üyelik'),
        subtitle: Text('Tercihler bu cihazda tutulur.'),
      ),
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Tema'),
        trailing: DropdownButton<ThemeMode>(
          value: widget.theme.mode,
          onChanged: (value) {
            if (value != null) widget.theme.setMode(value);
          },
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('Sistem')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Açık')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Koyu')),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.workspace_premium_outlined),
        title: const Text('Ömür boyu Pro'),
        subtitle: Text(widget.pro.isPro ? 'Etkin' : 'Reklamsız kullanım'),
        onTap: () => Navigator.of(context).push(
          sharedAxisRoute<void>(
            PaywallPage(
              identity: widget.identity,
              controller: widget.pro,
              repository: widget.purchase,
              benefits: const ['Reklamsız ilan takibi'],
            ),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: const Text('Bildirimler'),
        subtitle: const Text(
          'Kayıtlı aramalarınıza uyan ilanlar ve son başvuru hatırlatıcıları. '
          'Sessiz saatler: 22:00-08:00.',
        ),
        onTap: () async {
          final granted = await requestAlertPermission(context);
          if (!mounted) return;
          final checked = granted ? await runAlertCheckNow() : 0;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                granted
                    ? (checked == 0
                          ? 'Bildirimler açık. Yeni ilan geldiğinde haber verilir.'
                          : 'Bildirimler açık. $checked uyarı gönderildi.')
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
          subtitle: const Text(
            'Uygulama kapalıyken de yeni ilanlar için haber alın. Sunucuya '
            'yalnızca bildirim jetonunuz ve kayıtlı arama süzgeçleriniz gider; '
            'hesap yoktur. Kapatınca kaydınız silinir.',
          ),
          value: pushRegistrar!.enabled,
          onChanged: _setServerPush,
        ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Bildirim geçmişi'),
        subtitle: const Text(
          'Gönderilen, bekleyen ve gönderilmeyen tüm uyarılar. '
          'Veriler yalnızca bu cihazda tutulur.',
        ),
        onTap: () =>
            Navigator.of(context)
                .push(sharedAxisRoute<void>(const NotificationCenterPage())),
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
      const ListTile(
        title: Text('Veriler ve geri bildirim'),
        subtitle: Text(
          'Yedek dosyası yalnızca sizin paylaştığınız yere gider.',
        ),
      ),
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
        subtitle: const Text('Yedek yapıştırılır; mevcut kayıtlar korunur.'),
        onTap: _importData,
      ),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Hakkında ve lisanslar'),
        onTap: () => Navigator.of(context)
            .push(sharedAxisRoute<void>(AboutPage(identity: widget.identity))),
      ),
    ],
  );

  Widget _emptyState(String message, {required VoidCallback onPressed}) =>
      Center(
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
              OutlinedButton(
                onPressed: onPressed,
                child: const Text('Süzgeçleri temizle'),
              ),
            ],
          ),
        ),
      );

  String _sourceLabel(String sourceId) => switch (sourceId) {
    'kamuilan_sbb' => 'Kamu İlanları (SBB)',
    'resmigazete' => 'Resmî Gazete',
    _ => 'Kariyer Kapısı',
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
      sourceStatuses.where((s) => s.id == id).firstOrNull;
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
            'Resmî liste ve RSS; ayrıntılar ilan açılınca okunur.',
          ),
          (
            'Kamu İlanları (SBB)',
            'sbb',
            'Güncel yıl listesi; asıl ilan resmî PDF belgedir.',
          ),
        ])
          ListTile(
            leading: Icon(
              _serverStatus(id) != null
                  ? _serverStatus(id)!.state == SourceState.ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline
                  : checkedAt == null
                  ? Icons.help_outline
                  : failedSources.contains(name)
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
            ),
            title: Text(name),
            subtitle: Text(
              _serverStatus(id) != null
                  ? '${_serverLabel(id)}. ${_serverNote(id) ?? description}'
                  : checkedAt != null && failedSources.contains(name)
                  ? 'Son denetim başarısız; önbellek korunuyor. $description'
                  : description,
            ),
          ),
        for (final (name, id, status, url) in [
          (
            'İŞKUR',
            'iskur',
            'Herkese açık arayüz oturum akışına bağlı; otomatik tarama için çalışma sürüyor.',
            'https://esube.iskur.gov.tr/',
          ),
          (
            'ilan.gov.tr',
            'ilangov',
            'Arama arayüzü dokümanlanmamış bir ağ geçidi ardında; otomatik tarama hazırlanıyor.',
            'https://www.ilan.gov.tr/',
          ),
        ])
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(name),
            subtitle: Text(
              _serverNote(id) == null
                  ? status
                  : 'Sunucu denetimi: ${_serverNote(id)}',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => open(Uri.parse(url)),
          ),
        const ListTile(
          leading: Icon(Icons.location_city_outlined),
          title: Text('Belediyeler'),
          subtitle: Text('Kurum bazında resmî duyuru kaynakları eklenecek.'),
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
