import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/listing_store.dart';
import 'data/search_alerts.dart';
import 'notifications/alert_service.dart';
import 'notifications/notification_center_page.dart';
import 'listings/kariyer_detail.dart';
import 'listings/kariyer_detail_page.dart';
import 'listings/extract_conditions.dart';
import 'listings/kariyer_feed.dart';
import 'listings/listing_guide.dart';
import 'listings/rg_feed.dart';
import 'listings/sbb_feed.dart';
import 'ui/premium.dart';

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
  State<KamuHomePage> createState() => _KamuHomePageState();
}

class _KamuHomePageState extends State<KamuHomePage> {
  static const _legacySavedKey = 'kamubul.saved_urls';
  static const _pruneAfter = Duration(days: 45);
  static const _kategoriAdlari = [
    'Tümü',
    'İŞKUR / İşçi',
    'Personel',
    'Belediye',
  ];

  int _tab = 0;
  int _category = 0;
  String _search = '';
  bool _last30 = false;
  String? _place;
  int? _ageFilter;
  String? _educationFilter;
  String? _kpssFilter;
  String? _activeSearchName;
  bool _loading = false;
  String? _error;
  DateTime? _lastRefresh;
  List<ListingRecord> _records = const [];
  List<SavedSearch> _searches = const [];
  ListingRecord? _assistantListing;
  final ListingStore _store = ListingStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _migrateLegacyBookmarks();
      await _loadLocal();
      await _refresh();
    });
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
      if (!mounted) return;
      setState(() {
        _records = records;
        _searches = searches;
      });
    } on Exception {
      // Yerel okuma hatası: boş katalogla çevrimiçi yenileme denenir.
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final incoming = <ListingRecord>[];
    final failed = <String>[];
    final now = DateTime.now();
    try {
      final items = await loadKariyerFeed();
      incoming.addAll([
        for (final item in items)
          ListingRecord(
            url: item.url.toString(),
            sourceId: 'kariyerkapisi',
            title: item.title,
            category: item.category,
            publishedAt: item.publishedAt,
            fetchedAt: now,
          ),
      ]);
    } on Exception {
      failed.add('Kariyer Kapısı');
    }
    try {
      final sbbItems = await loadSbbListings();
      incoming.addAll([
        for (final item in sbbItems)
          ListingRecord(
            url: item.url.toString(),
            sourceId: 'kamuilan_sbb',
            title: item.institution,
            category: item.category,
            publishedAt: item.publishedAt,
            deadline: item.deadline,
            quota: item.quota,
            fetchedAt: now,
          ),
      ]);
    } on Exception {
      failed.add('Kamu İlanları (SBB)');
    }
    try {
      // Dünün Resmî Gazete'si; ilanlar gecikmeli yayımlandığı için dün taranır.
      final rgItems = await loadRgPersonnelNotices();
      incoming.addAll([
        for (final item in rgItems)
          ListingRecord(
            url: item.url.toString(),
            sourceId: 'resmigazete',
            title: item.title,
            category: 'Resmî Gazete',
            publishedAt: item.publishedAt,
            fetchedAt: now,
          ),
      ]);
    } on Exception {
      failed.add('Resmî Gazete');
    }
    try {
      await _store.mergeFeed(incoming, pruneBefore: now.subtract(_pruneAfter));
    } on Exception {
      failed.add('Yerel katalog');
    }
    await _loadLocal();
    if (!mounted) return;
    setState(() {
      _lastRefresh = now;
      _error = failed.isEmpty
          ? null
          : '${failed.join(' ve ')} yenilenemedi. Son görülen liste korunuyor.';
    });
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

  List<ListingRecord> get _visibleRecords => _records.where((record) {
    if (_tab == 1 && !record.saved) return false;
    if (_tab == 0 && _category == 1) {
      // İŞKUR kaynağı PB-003'te eklenene kadar bu sekme bilinçli olarak boş;
      // kaynak kimliğiyle filtreleme o görevde gelir.
      return false;
    }
    if (_tab == 0 &&
        _category == 2 &&
        !record.category.toLowerCase().contains('personel')) {
      return false;
    }
    if (_tab == 0 &&
        _category == 3 &&
        !record.title.toLowerCase().contains('belediye')) {
      return false;
    }
    if (_last30) {
      final published = record.publishedAt;
      if (published == null ||
          published.isBefore(
            DateTime.now().subtract(const Duration(days: 30)),
          )) {
        return false;
      }
    }
    if (_place != null &&
        !record.places.any(
          (place) => place.toLowerCase().contains(_place!.toLowerCase()),
        ) &&
        !record.title.toLowerCase().contains(_place!.toLowerCase())) {
      return false;
    }
    // Yaş/eğitim/KPSS süzgeçleri yalnızca alıntı kanıtlı çıkarılmış alanlarda
    // uygulanır; bilinmeyen değerli ilan bu etikette gösterilmez.
    if (_ageFilter != null &&
        (record.maxAge == null || record.maxAge! < _ageFilter!)) {
      return false;
    }
    if (_educationFilter != null && record.education != _educationFilter) {
      return false;
    }
    if (_kpssFilter != null && record.kpss != _kpssFilter) {
      return false;
    }
    return record.title.toLowerCase().contains(_search.toLowerCase());
  }).toList();

  void _applySearch(SavedSearch search) {
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
      _activeSearchName = search.name;
    });
  }

  void _clearFilters() {
    setState(() {
      _search = '';
      _category = 0;
      _last30 = false;
      _place = null;
      _ageFilter = null;
      _educationFilter = null;
      _kpssFilter = null;
      _activeSearchName = null;
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

  Future<void> _saveCurrentSearch() async {
    final saved = await _promptSearchFilters();
    if (saved == null) return;
    final (name, yas, egitim, kpss) = saved;
    if (name.trim().isEmpty) return;
    final filters = <String, String>{..._currentFilters};
    if (yas != null) filters['yas'] = '$yas';
    if (egitim != null) filters['egitim'] = egitim;
    if (kpss != null) filters['kpss'] = kpss;
    if (_activeSearchName != null) {
      SavedSearch? existing;
      for (final search in _searches) {
        if (search.name == _activeSearchName) existing = search;
      }
      if (existing != null) {
        await _store.updateSavedSearch(
          existing.copyWith(name: name.trim(), filters: filters),
        );
        await _loadLocal();
        if (mounted) setState(() => _activeSearchName = name.trim());
        return;
      }
    }
    final created = await _store.addSavedSearch(
      SavedSearch(
        id: null,
        name: name.trim(),
        filters: filters,
        createdAt: DateTime.now(),
      ),
    );
    await _loadLocal();
    if (mounted) setState(() => _activeSearchName = created.name);
    await _maybeAskNotificationPermission();
  }

  /// İlk kayıtlı aramadan sonra yumuşak izin açıklaması gösterilir;
  /// reddedilirse uygulama aynen çalışır.
  Future<void> _maybeAskNotificationPermission() async {
    if (widget.store.getInt('kamubul.alerts.asked') != null) return;
    widget.store.setInt('kamubul.alerts.asked', 1);
    if (_searches.length > 1 || !mounted) return;
    await requestAlertPermission(context);
  }

  /// Kayıtlı arama formu: ad + profil eşleşmesi için yaş/eğitim/KPSS.
  Future<(String, int?, String?, String?)?> _promptSearchFilters() {
    final nameController = TextEditingController(text: _activeSearchName);
    final ageController = TextEditingController(
      text: _ageFilter?.toString() ?? '',
    );
    final kpssController = TextEditingController(text: _kpssFilter ?? '');
    var education = _educationFilter;
    return showDialog<(String, int?, String?, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Aramayı kaydet'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Arama adı'),
                ),
                TextField(
                  controller: ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Yaşınız (uyum için, isteğe bağlı)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: education,
                  decoration: const InputDecoration(
                    labelText: 'Eğitim düzeyi (isteğe bağlı)',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Lise', child: Text('Lise')),
                    DropdownMenuItem(
                      value: 'Ön lisans',
                      child: Text('Ön lisans'),
                    ),
                    DropdownMenuItem(value: 'Lisans', child: Text('Lisans')),
                    DropdownMenuItem(
                      value: 'Yüksek lisans',
                      child: Text('Yüksek lisans'),
                    ),
                    DropdownMenuItem(value: 'Doktora', child: Text('Doktora')),
                  ],
                  onChanged: (value) => setDialogState(() => education = value),
                ),
                TextField(
                  controller: kpssController,
                  decoration: const InputDecoration(
                    labelText: 'KPSS puan türü (örn. P3, P93)',
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
              onPressed: () => Navigator.pop(dialogContext, (
                nameController.text,
                int.tryParse(ageController.text.trim()),
                education,
                kpssController.text.trim().isEmpty
                    ? null
                    : kpssController.text.trim().toUpperCase(),
              )),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
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
                  tooltip: 'Bildirim modu',
                  icon: const Icon(Icons.notifications_outlined),
                  onSelected: (value) async {
                    final filters = <String, String>{...search.filters};
                    filters['bildirim'] = value;
                    await _store.updateSavedSearch(
                      search.copyWith(filters: filters),
                    );
                    await _loadLocal();
                  },
                  itemBuilder: (menuContext) => const [
                    PopupMenuItem(
                      value: 'instant',
                      child: Text('Anlık bildirim'),
                    ),
                    PopupMenuItem(value: 'digest', child: Text('Günlük özet')),
                    PopupMenuItem(value: 'off', child: Text('Kapalı')),
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
    if (changed == true && _activeSearchName != null && mounted) {
      final stillExists = _searches.any((s) => s.name == _activeSearchName);
      if (!stillExists) setState(() => _activeSearchName = null);
    }
  }

  String _modeLabel(SearchAlertMode mode) => switch (mode) {
    SearchAlertMode.instant => 'Anlık',
    SearchAlertMode.digest => 'Günlük özet',
    SearchAlertMode.off => 'Kapalı',
  };

  String _filterSummary(SavedSearch search) {
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
            onPressed: () => Navigator.of(context).push(
              sharedAxisRoute<void>(const NotificationCenterPage()),
            ),
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
                    ? 'İŞKUR otomatik bağlantısı hazırlanıyor. Resmî siteye Kaynaklar ekranından ulaşabilirsiniz.'
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fırsatları resmî kaynağında bulun',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          _lastRefresh == null
              ? 'Katalog cihazdan yükleniyor.'
              : 'Son kontrol: ${_lastRefresh!.hour.toString().padLeft(2, '0')}:${_lastRefresh!.minute.toString().padLeft(2, '0')} • Resmî kaynaklar',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );

  Widget _filters() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Kurum veya meslek ara',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() {
            _search = value;
            _activeSearchName = null;
          }),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
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
                        _activeSearchName = null;
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
                      _activeSearchName = null;
                    });
                  },
                ),
              ),
              if (_place != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text(_place!),
                    onDeleted: () => setState(() {
                      _place = null;
                      _activeSearchName = null;
                    }),
                  ),
                ),
              if (_ageFilter != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text('Yaş uyarı: $_ageFilter'),
                    onDeleted: () => setState(() {
                      _ageFilter = null;
                      _activeSearchName = null;
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
                      _activeSearchName = null;
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
                      _activeSearchName = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
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
                selected: _activeSearchName == search.name,
                onSelected: (_) => _applySearch(search),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listingCard(ListingRecord record) {
    final expired = record.expired;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          if (record.sourceId == 'kamuilan_sbb' ||
              record.sourceId == 'resmigazete') {
            // SBB ve RG kayıtları doğrudan resmî belgeyi açar.
            _open(Uri.parse(record.url));
            return;
          }
          Navigator.of(context).push(
            sharedAxisRoute<void>(
              KariyerDetailPage(
                listing: _asPublicListing(record),
                onLoaded: (detail) => _cacheDetail(record.url, detail),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.category.isEmpty ? 'Kamu ilanı' : record.category,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(
                record.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${_sourceLabel(record.sourceId)} • ${_date(record.publishedAt)}',
              ),
              Text(
                record.deadline == null
                    ? 'Son başvuru tarihi: kaynakta kontrol edin'
                    : 'Son başvuru: ${_date(record.deadline)}',
                style: expired
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              if (record.quota != null) Text('Kontenjan: ${record.quota} kişi'),
              if (record.places.isNotEmpty)
                Text('Yerler: ${record.places.join(', ')}'),
              if (expired)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Son başvuru geçti',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _open(Uri.parse(record.url)),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Resmî ilana git'),
                  ),
                  IconButton(
                    tooltip: record.saved ? 'Kaydı kaldır' : 'Kaydet',
                    onPressed: () => _toggleSaved(record),
                    icon: Icon(
                      record.saved ? Icons.bookmark : Icons.bookmark_outline,
                    ),
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
    if (selected != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Seçili ilan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            child: ListTile(
              title: Text(selected.title),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open(Uri.parse(selected.url)),
            ),
          ),
          const SizedBox(height: 8),
          ListingGuideView(listingUrl: selected.url),
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
          MaterialPageRoute<void>(
            builder: (_) => PaywallPage(
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
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Bildirim geçmişi'),
        subtitle: const Text(
          'Gönderilen, bekleyen ve gönderilmeyen tüm uyarılar. '
          'Veriler yalnızca bu cihazda tutulur.',
        ),
        onTap: () => Navigator.of(context).push(
          sharedAxisRoute<void>(const NotificationCenterPage()),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.source_outlined),
        title: const Text('Resmî kaynaklar'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _SourcesPage(open: _open)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Hakkında ve lisanslar'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AboutPage(identity: widget.identity),
          ),
        ),
      ),
    ],
  );

  Widget _emptyState(String message, {required VoidCallback onPressed}) =>
      Center(
        child: Padding(
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
  const _SourcesPage({required this.open});
  final Future<void> Function(Uri) open;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Resmî kaynaklar')),
    body: ListView(
      children: [
        const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('Kariyer Kapısı'),
          subtitle: Text(
            'Resmî RSS akışı ve ilan ayrıntı okuması kullanılıyor.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('Kamu İlanları (SBB)'),
          subtitle: Text(
            'Strateji ve Bütçe Başkanlığı güncel yıl listesi okunuyor; ilan kaydı resmî PDF belgeyi açar.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('Resmî Gazete'),
          subtitle: Text(
            'Dünkü sayıda personel alımı duyuruları taranıyor; kayıt resmî belgeyi açar.',
          ),
        ),
        for (final (name, status, url) in [
          (
            'İŞKUR',
            'Herkese açık arayüz oturum akışına bağlı; otomatik tarama için çalışma sürüyor.',
            'https://esube.iskur.gov.tr/',
          ),
          (
            'ilan.gov.tr',
            'Arama arayüzü dokümanlanmamış bir ağ geçidi ardında; otomatik tarama hazırlanıyor.',
            'https://www.ilan.gov.tr/',
          ),
        ])
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(name),
            subtitle: Text(status),
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
