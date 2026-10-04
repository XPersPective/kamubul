import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/listing_store.dart';
import '../listings/extract_conditions.dart';
import '../listings/extraction_policy.dart';
import '../listings/kariyer_detail.dart';
import 'official_listing_page.dart';

/// İlan Rehberi'nin deterministik çekirdeği: seçili ilanın şart
/// alanlarını kaynak cümleleriyle yanıtlar. Serbest AI sohbeti ileri aşamadır;
/// bu ekran hiçbir koşulda uydurma yanıt üretemez — yalnızca kanıtlı alan.
class ListingGuideView extends StatelessWidget {
  const ListingGuideView({super.key, required this.listing});

  final ListingRecord listing;

  Future<void> _openOfficial(BuildContext context, Uri url) async {
    if (url.scheme != 'https') return;
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Başvuru bağlantısı açılamazsa anlaşılır bir hata gösterilir.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resmî sayfa açılamadı.')));
    }
  }

  Future<KariyerDetail?> _loadDetail() async {
    try {
      return await loadKariyerDetail(Uri.parse(listing.url));
    } on Exception {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (listing.criteriaListing != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'İlan rehberi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sunucudan alınan ilan bilgileri kullanılıyor. Her kadronun koşullarını ilan ayrıntısında ayrı inceleyebilirsiniz.',
            ),
            for (final text in listing.summary) ...[
              const SizedBox(height: 12),
              Text(text),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OfficialListingPage(
                    listing: listing,
                    unavailable: listing.criteriaListing?['active'] == false,
                  ),
                ),
              ),
              icon: const Icon(Icons.article_outlined),
              label: const Text('Kadro koşullarını incele'),
            ),
          ],
        ),
      );
    }
    if (listing.sourceId != 'kariyerkapisi') {
      return _localSummary(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<KariyerDetail?>(
      future: _loadDetail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const _GuideMessage(
            icon: Icons.cloud_off_outlined,
            text: 'İlan ayrıntısı şu an okunamadı. Resmî sayfadan doğrulayın.',
          );
        }
        final text = [
          detail.body,
          for (final position in detail.positions) position.conditions,
        ].join('\n');
        final fields = applyExtractionPolicy(extractConditions(text));
        // Ana ListView içinde gömülü; kendi kaydırmasını devre dışı bırakır.
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'İlan özeti',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Bu yanıtlar ilan metnindeki cümlelerden çıkar; kaynak cümle '
              'görünmüyorsa koşul ilanda belirtilmemiştir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _GuideField(
              label: 'KPSS puan türü',
              value: fields.kpssType?.value,
              quote: fields.kpssType?.quote,
            ),
            _GuideField(
              label: 'KPSS taban puanı',
              value: fields.kpssScore == null
                  ? null
                  : '${fields.kpssScore!.value} puan',
              quote: fields.kpssScore?.quote,
            ),
            _GuideField(
              label: 'Yaş sınırı',
              value: fields.maxAge == null
                  ? null
                  : '${fields.maxAge!.value} yaş',
              quote: fields.maxAge?.quote,
            ),
            _GuideField(
              label: 'Eğitim şartı',
              value: fields.education?.value,
              quote: fields.education?.quote,
            ),
            _GuideField(
              label: 'Kadro/kota tipi',
              value: fields.quotaType?.value,
              quote: fields.quotaType?.quote,
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(Icons.open_in_new, color: scheme.primary),
                title: const Text('Resmî ilanı aç'),
                subtitle: Text(
                  detail.institution.isEmpty
                      ? 'Kaynak: kariyerkapisi.gov.tr'
                      : detail.institution,
                ),
                onTap: () => _openOfficial(
                  context,
                  detail.applyUrl ?? Uri.parse(listing.url),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _GuideMessage(
              icon: Icons.auto_awesome_outlined,
              text:
                  'Serbest soru sorma (yapay zekâ sohbeti) hazırlanıyor. '
                  'Bu ekrandaki yanıtlar yalnızca ilan metninden gelir.',
            ),
          ],
        );
      },
    );
  }

  Widget _localSummary(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('İlan özeti', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Kaynakta doğrulanan bilgiler. Yaş, eğitim ve KPSS şartlarını '
          'Asistan’a sorabilirsiniz; ilan metnini okuyarak yanıtlar.',
        ),
        _GuideField(
          label: 'Kontenjan',
          value: listing.quota == null ? null : '${listing.quota} kişi',
          quote: null,
        ),
        _GuideField(
          label: 'Son başvuru',
          value: listing.deadline == null
              ? null
              : '${listing.deadline!.day}.${listing.deadline!.month}.${listing.deadline!.year}',
          quote: null,
        ),
        const _GuideField(label: 'Yaş sınırı', value: null, quote: null),
        const _GuideField(label: 'Eğitim şartı', value: null, quote: null),
        const _GuideField(label: 'KPSS şartı', value: null, quote: null),
      ],
    ),
  );
}

class _GuideField extends StatelessWidget {
  const _GuideField({
    required this.label,
    required this.value,
    required this.quote,
  });

  final String label;
  final String? value;
  final String? quote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  value == null
                      ? Icons.help_outline
                      : Icons.check_circle_outline,
                  size: 18,
                  color: value == null ? scheme.outline : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? '$label: belirtilmemiş' : '$label: $value',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (quote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 26),
                child: Text(
                  '"$quote"',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideMessage extends StatelessWidget {
  const _GuideMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}
