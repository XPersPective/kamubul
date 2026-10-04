import '../ui/premium_widgets.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/premium.dart';
import 'extract_conditions.dart';
import 'extraction_policy.dart';
import 'kariyer_detail.dart';
import 'kariyer_feed.dart';

/// Resmî ilanın ayrıntısı: Kariyer Kapısı'nın herkese açık okuma çağrılarından
/// kurum, kontenjan, yer, tarih ve şartlar; resmî başvuru bağlantısıyla.
///
/// PB-008: başlık kaydırmada çöken büyük başlık (SliverAppBar.large) ve
/// her zaman görünür yapışkan başvuru düğmesi.
class KariyerDetailPage extends StatefulWidget {
  const KariyerDetailPage({
    super.key,
    required this.listing,
    this.onLoaded,
    this.loader,
    this.summary = const [],
  });

  final PublicListing listing;

  /// Sunucunun yapay zekâ ile hazırladığı kısa özet maddeleri. Her madde
  /// ilan metnindeki doğrulanmış bir alıntıya dayanır; sayfada "Yapay zekâ
  /// özeti" olarak etiketlenir. Boşsa bölüm gösterilmez.
  final List<String> summary;

  /// Ayrıntı başarıyla okunduğunda çağrılır; katalog yapılandırılmış
  /// alanları (kontenjan, son başvuru, yerler) yerel kayda işler.
  final void Function(KariyerDetail detail)? onLoaded;

  /// Ayrıntı yükleyici; varsayılan resmî açık okuma çağrıları. Testler
  /// ağsız fikstürle besler.
  final Future<KariyerDetail> Function(Uri url)? loader;

  @override
  State<KariyerDetailPage> createState() => _KariyerDetailPageState();
}

class _KariyerDetailPageState extends State<KariyerDetailPage> {
  late Future<KariyerDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<KariyerDetail> _load() {
    final loaded = widget.onLoaded;
    final read = widget.loader ?? loadKariyerDetail;
    return read(widget.listing.url).then((detail) {
      loaded?.call(detail);
      return detail;
    });
  }

  void _retry() {
    setState(() => _future = _load());
  }

  Future<void> _open(Uri url) async {
    if (url.scheme != 'https') return;
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Aynı hata kullanıcıya tek bir anlaşılır mesajla bildirilir.
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resmî sayfa açılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<KariyerDetail>(
      future: _future,
      builder: (context, snapshot) {
        final detail = snapshot.data;
        final applyUrl = detail?.applyUrl ?? widget.listing.url;
        return Scaffold(
          // Yapışkan CTA: başvuru düğmesi içeriğin sonunda değil, her zaman
          // ekranın altındadır.
          bottomNavigationBar: _stickyApply(
            applyUrl,
            canApply: detail?.applyUrl != null,
          ),
          body: snapshot.connectionState != ConnectionState.done
              ? _loadingView()
              : snapshot.hasError
              ? _errorView(Theme.of(context).colorScheme)
              : _content(detail!),
        );
      },
    );
  }

  Widget _loadingView() => CustomScrollView(
    slivers: [
      const SliverAppBar(pinned: true, title: Text('İlan ayrıntısı')),
      SliverToBoxAdapter(
        child: Semantics(
          label: 'İlan ayrıntısı yükleniyor',
          child: listingSkeletons(),
        ),
      ),
    ],
  );

  Widget _errorView(ColorScheme scheme) => CustomScrollView(
    slivers: [
      const SliverAppBar(pinned: true, title: Text('İlan ayrıntısı')),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                const Text(
                  'İlan ayrıntısı okunamadı. Kaynak sayfayı doğrudan '
                  'aşağıdaki düğmeden açabilirsiniz.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _retry,
                  child: const Text('Yeniden dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _stickyApply(Uri url, {required bool canApply}) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Row(
      children: [
        if (canApply) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _open(widget.listing.url),
              icon: const Icon(Icons.article_outlined),
              label: const Text(
                'İlanı aç',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    PremiumShape.buttonRadius,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: () => _open(url),
            icon: const Icon(Icons.open_in_new),
            label: Text(
              canApply ? 'Başvuru sayfasını aç' : 'Resmî ilanı aç',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PremiumShape.buttonRadius),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
    ),
    child: child,
  );

  Widget _content(KariyerDetail detail) {
    final institutionPrefix = '${detail.institution} - ';
    final title =
        detail.institution.isNotEmpty &&
            widget.listing.title.startsWith(institutionPrefix)
        ? widget.listing.title.substring(institutionPrefix.length)
        : widget.listing.title;
    final keyConditions = {
      for (final position in detail.positions) ...position.keyConditions,
    }.take(6).toList();
    final conditions = applyExtractionPolicy(
      extractConditions(
        [
          detail.body,
          for (final position in detail.positions) position.conditions,
        ].join('\n'),
      ),
    );
    return CustomScrollView(
      slivers: [
        // Büyük başlık kaydırmada çöker; ilan başlığı sayfanın öznesidir.
        const SliverAppBar(pinned: true, title: Text('İlan ayrıntısı')),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  InstitutionAvatar(
                    title: detail.institution.isEmpty
                        ? widget.listing.title
                        : detail.institution,
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      detail.institution.isEmpty
                          ? 'Kurum belirtilmemiş'
                          : detail.institution,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              _card(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fact(
                        'Toplam kontenjan',
                        detail.quota > 0 ? '${detail.quota} kişi' : null,
                      ),
                      _fact(
                        'Son başvuru',
                        detail.deadline == null ? null : _date(detail.deadline),
                      ),
                      _fact(
                        'Yerler',
                        detail.places.isEmpty ? null : detail.places.join(', '),
                      ),
                      _fact(
                        'Yayın',
                        detail.start == null ? null : _date(detail.start),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (detail.positions.isNotEmpty) ...[
                Text(
                  'Kadrolar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final position in detail.positions)
                  _card(
                    ListTile(
                      title: Text(
                        position.profession.isEmpty
                            ? (position.title.isEmpty
                                  ? 'Unvan belirtilmemiş'
                                  : position.title)
                            : position.profession,
                      ),
                      subtitle: Text(
                        [
                          if (position.quota > 0)
                            'Kontenjan: ${position.quota}',
                          if (position.places.isNotEmpty)
                            position.places.join(', '),
                        ].join(' • '),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (keyConditions.isNotEmpty) ...[
                Text(
                  'Öne çıkan şartlar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _card(
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in keyConditions)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 3, right: 8),
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                  ),
                                ),
                                Expanded(child: Text(line)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.summary.isNotEmpty) ...[
                Text(
                  'Yapay zekâ özeti',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _card(
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in widget.summary)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 3, right: 8),
                                  child: Icon(Icons.auto_awesome, size: 16),
                                ),
                                Expanded(child: Text(line)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Yapay zekâ ile hazırlandı; her madde ilan '
                          'metnindeki bir cümleye dayanır. Kesin koşullar '
                          'için resmî ilana bakın.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (conditions.kpssType != null ||
                  conditions.kpssScore != null ||
                  conditions.maxAge != null ||
                  conditions.education != null ||
                  conditions.quotaType != null) ...[
                Text(
                  'Şart alanları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _card(
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (conditions.kpssType != null)
                          _evidenceField(
                            'KPSS puan türü',
                            conditions.kpssType!.value,
                            conditions.kpssType!.quote,
                          ),
                        if (conditions.kpssScore != null)
                          _evidenceField(
                            'KPSS taban puan',
                            conditions.kpssScore!.value.toString(),
                            conditions.kpssScore!.quote,
                          ),
                        if (conditions.maxAge != null)
                          _evidenceField(
                            'Yaş sınırı',
                            '${conditions.maxAge!.value} yaş',
                            conditions.maxAge!.quote,
                          ),
                        if (conditions.education != null)
                          _evidenceField(
                            'Eğitim',
                            conditions.education!.value,
                            conditions.education!.quote,
                          ),
                        if (conditions.quotaType != null)
                          _evidenceField(
                            'Kadro/kota tipi',
                            conditions.quotaType!.value,
                            conditions.quotaType!.quote,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (detail.body.isNotEmpty) ...[
                Text(
                  'İlan metni',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(detail.body),
                const SizedBox(height: 12),
              ],
              Text(
                'Kaynak: kariyerkapisi.gov.tr • Koşulların doğruluğu için '
                'resmî ilanı kontrol edin.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _evidenceField(String label, String value, String quote) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: $value',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          '"$quote"',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    ),
  );

  Widget _fact(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value ?? 'Belirtilmemiş',
            style: value == null
                ? Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic)
                : Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  String _date(DateTime? value) => value == null
      ? 'Kaynakta belirtilmemiş'
      : '${value.day}.${value.month}.${value.year}';
}
