import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'extract_conditions.dart';
import 'kariyer_detail.dart';
import 'kariyer_feed.dart';

/// Resmî ilanın ayrıntısı: Kariyer Kapısı'nın herkese açık okuma çağrılarından
/// kurum, kontenjan, yer, tarih ve şartlar; resmî başvuru bağlantısıyla.
class KariyerDetailPage extends StatefulWidget {
  const KariyerDetailPage({super.key, required this.listing, this.onLoaded});

  final PublicListing listing;

  /// Ayrıntı başarıyla okunduğunda çağrılır; katalog yapılandırılmış
  /// alanları (kontenjan, son başvuru, yerler) yerel kayda işler.
  final void Function(KariyerDetail detail)? onLoaded;

  @override
  State<KariyerDetailPage> createState() => _KariyerDetailPageState();
}

class _KariyerDetailPageState extends State<KariyerDetailPage> {
  late Future<KariyerDetail> _future;

  @override
  void initState() {
    super.initState();
    final loaded = widget.onLoaded;
    _future = loadKariyerDetail(widget.listing.url).then((detail) {
      loaded?.call(detail);
      return detail;
    });
  }

  void _retry() {
    final loaded = widget.onLoaded;
    setState(() {
      _future = loadKariyerDetail(widget.listing.url).then((detail) {
        loaded?.call(detail);
        return detail;
      });
    });
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('İlan ayrıntısı')),
      body: FutureBuilder<KariyerDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _errorView(scheme);
          }
          return _content(snapshot.data!);
        },
      ),
    );
  }

  Widget _errorView(ColorScheme scheme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          const Text(
            'İlan ayrıntısı okunamadı. Kaynak sayfayı doğrudan açabilirsiniz.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _retry,
                child: const Text('Yeniden dene'),
              ),
              FilledButton.tonal(
                onPressed: () => _open(widget.listing.url),
                child: const Text('Resmî ilana git'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _content(KariyerDetail detail) {
    final applyUrl = detail.applyUrl ?? widget.listing.url;
    final keyConditions = {
      for (final position in detail.positions) ...position.keyConditions,
    }.take(6).toList();
    final conditions = extractConditions(
      [
        detail.body,
        for (final position in detail.positions) position.conditions,
      ].join('\n'),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          detail.institution.isEmpty
              ? 'Kurum belirtilmemiş'
              : detail.institution,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          widget.listing.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
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
          Text('Kadrolar', style: Theme.of(context).textTheme.titleMedium),
          for (final position in detail.positions)
            Card(
              child: ListTile(
                title: Text(
                  position.profession.isEmpty
                      ? (position.title.isEmpty
                            ? 'Unvan belirtilmemiş'
                            : position.title)
                      : position.profession,
                ),
                subtitle: Text(
                  [
                    if (position.quota > 0) 'Kontenjan: ${position.quota}',
                    if (position.places.isNotEmpty) position.places.join(', '),
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
          Card(
            child: Padding(
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
                            child: Icon(Icons.check_circle_outline, size: 16),
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
        if (conditions.kpssType != null ||
            conditions.kpssScore != null ||
            conditions.maxAge != null ||
            conditions.education != null) ...[
          Text('Şart alanları', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Padding(
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (detail.body.isNotEmpty) ...[
          Text('İlan metni', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(detail.body),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: () => _open(applyUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Resmî sayfada başvur'),
        ),
        const SizedBox(height: 8),
        Text(
          'Kaynak: kariyerkapisi.gov.tr • Koşulların doğruluğu için resmî ilanı kontrol edin.',
          style: Theme.of(context).textTheme.bodySmall,
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
