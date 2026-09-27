import 'package:flutter/material.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/listing_store.dart';
import 'listings/kariyer_detail.dart';
import 'listings/kariyer_detail_page.dart';
import 'listings/kariyer_feed.dart';

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
    try {
      final items = await loadKariyerFeed();
      final now = DateTime.now();
      await _store.mergeFeed([
        for (final item in items)
          ListingRecord(
            url: item.url.toString(),
            sourceId: 'kariyerkapisi',
            title: item.title,
            category: item.category,
            publishedAt: item.publishedAt,
            fetchedAt: now,
          ),
      ], pruneBefore: now.subtract(_pruneAfter));
      await _loadLocal();
      if (!mounted) return;
      setState(() => _lastRefresh = now);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'İlanlar yenilenemedi. Son görülen liste korunuyor.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleSaved(ListingRecord record) async {
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
      _activeSearchName = search.name;
    });
  }

  void _clearFilters() {
    setState(() {
      _search = '';
      _category = 0;
      _last30 = false;
      _place = null;
      _activeSearchName = null;
    });
  }

  Map<String, String> get _currentFilters => {
    'q': _search,
    'kategori': '$_category',
    'son30': _last30 ? '1' : '0',
    'sehir': ?_place,
  };

  Future<void> _saveCurrentSearch() async {
    final name = await _promptText(
      title: 'Aramayı kaydet',
      label: 'Kayıtlı arama adı',
      initial: _activeSearchName,
    );
    if (name == null || name.trim().isEmpty) return;
    if (_activeSearchName != null) {
      SavedSearch? existing;
      for (final search in _searches) {
        if (search.name == _activeSearchName) existing = search;
      }
      if (existing != null) {
        await _store.updateSavedSearch(
          existing.copyWith(name: name.trim(), filters: _currentFilters),
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
        filters: _currentFilters,
        createdAt: DateTime.now(),
      ),
    );
    await _loadLocal();
    if (mounted) setState(() => _activeSearchName = created.name);
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
                subtitle: Text(_filterSummary(search)),
                trailing: IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _store.deleteSavedSearch(search.id!);
                    if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                  },
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
    return parts.isEmpty ? 'Süzgeç yok' : parts.join(' • ');
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
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
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        )
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
              : 'Kariyer Kapısı • Son kontrol: ${_lastRefresh!.hour.toString().padLeft(2, '0')}:${_lastRefresh!.minute.toString().padLeft(2, '0')}',
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
                    onSelected: (_) => setState(() {
                      _category = index;
                      _activeSearchName = null;
                    }),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('Son 30 gün'),
                  selected: _last30,
                  onSelected: (value) => setState(() {
                    _last30 = value;
                    _activeSearchName = null;
                  }),
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
            ],
          ),
        ),
        const SizedBox(height: 4),
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => KariyerDetailPage(
              listing: _asPublicListing(record),
              onLoaded: (detail) => _cacheDetail(record.url, detail),
            ),
          ),
        ),
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
              Text('Kariyer Kapısı • ${_date(record.publishedAt)}'),
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

  Widget _assistantView() => ListView(
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
        'İlan koşullarını anlamanız ve size uygun ilanları bulmanız için hazırlanıyor.',
      ),
      if (_assistantListing != null) ...[
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: Text(_assistantListing!.title),
            subtitle: const Text('Resmî ilan bağlantısı hazır'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(Uri.parse(_assistantListing!.url)),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const TextField(
        enabled: false,
        decoration: InputDecoration(
          labelText: 'İlan hakkında sorun',
          helperText: 'API bağlantısı ve kaynaklı yanıtlar hazırlanıyor.',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );

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
          subtitle: Text('Resmî RSS akışından ilanlar gösteriliyor.'),
        ),
        for (final (name, url) in [
          ('İŞKUR', 'https://esube.iskur.gov.tr/'),
          ('ilan.gov.tr', 'https://www.ilan.gov.tr/'),
          ('Resmî Gazete', 'https://resmigazete.gov.tr/fihrist'),
        ])
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(name),
            subtitle: const Text(
              'Otomatik tarama hazırlanıyor; resmî siteyi aç.',
            ),
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
