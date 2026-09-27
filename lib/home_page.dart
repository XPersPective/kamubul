import 'package:flutter/material.dart';
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _savedKey = 'kamubul.saved_urls';
  int _tab = 0;
  int _category = 0;
  String _search = '';
  bool _loading = false;
  String? _error;
  DateTime? _lastRefresh;
  List<PublicListing> _items = const [];
  late final Set<String> _saved =
      widget.store.getStringList(_savedKey)?.toSet() ?? <String>{};
  PublicListing? _assistantListing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await loadKariyerFeed();
      if (!mounted) return;
      setState(() {
        _items = items;
        _lastRefresh = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'İlanlar yenilenemedi. Son görülen liste korunuyor.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSaved(PublicListing item) {
    setState(() {
      if (!_saved.add(item.url.toString())) {
        _saved.remove(item.url.toString());
      }
      widget.store.setStringList(_savedKey, _saved.toList());
    });
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

  List<PublicListing> get _visibleItems => _items.where((item) {
    if (_tab == 1 && !_saved.contains(item.url.toString())) return false;
    if (_tab == 0 && _category == 1) {
      // İŞKUR kaynağı PB-003'te eklenene kadar bu sekme bilinçli olarak boş;
      // kaynak kimliğiyle filtreleme o görevde gelir.
      return false;
    }
    if (_tab == 0 &&
        _category == 2 &&
        !item.category.toLowerCase().contains('personel')) {
      return false;
    }
    if (_tab == 0 &&
        _category == 3 &&
        !item.title.toLowerCase().contains('belediye')) {
      return false;
    }
    return item.title.toLowerCase().contains(_search.toLowerCase());
  }).toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.account_balance_outlined,
                size: 18,
                color: scheme.onPrimaryContainer,
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
      if (_loading && _items.isEmpty)
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_visibleItems.isEmpty)
        SliverFillRemaining(
          child: _emptyState(
            _error ??
                (_category == 1
                    ? 'İŞKUR otomatik bağlantısı hazırlanıyor. Resmî siteye Kaynaklar ekranından ulaşabilirsiniz.'
                    : 'Bu seçimde henüz doğrulanmış ilan yok.'),
            onPressed: _refresh,
          ),
        )
      else
        SliverList.builder(
          itemCount: _visibleItems.length,
          itemBuilder: (_, index) => _listingCard(_visibleItems[index]),
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
              ? 'Kariyer Kapısı akışı yükleniyor.'
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
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, label) in [
                'Tümü',
                'İŞKUR / İşçi',
                'Personel',
                'Belediye',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _category == index,
                    onSelected: (_) => setState(() => _category = index),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _listingCard(PublicListing item) {
    final saved = _saved.contains(item.url.toString());
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => KariyerDetailPage(listing: item),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.category.isEmpty ? 'Kamu ilanı' : item.category,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Kariyer Kapısı • ${_date(item.publishedAt)}'),
              const Text('Son başvuru tarihi: kaynakta kontrol edin'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _open(item.url),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Resmî ilana git'),
                  ),
                  IconButton(
                    tooltip: saved ? 'Kaydı kaldır' : 'Kaydet',
                    onPressed: () => _toggleSaved(item),
                    icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _assistantListing = item;
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

  Widget _savedView() => _visibleItems.isEmpty
      ? _emptyState(
          'Kaydedilen ilanlar burada görünecek.',
          onPressed: () => setState(() => _tab = 0),
        )
      : ListView(children: [_intro(), ..._visibleItems.map(_listingCard)]);

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
            onTap: () => _open(_assistantListing!.url),
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
                child: const Text('İlanlara bak'),
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
