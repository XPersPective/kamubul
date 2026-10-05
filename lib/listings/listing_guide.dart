import 'package:flutter/material.dart';

import '../data/listing_store.dart';
import 'official_listing_page.dart';

/// İlan Rehberi'nin deterministik çekirdeği: seçili ilanın şart
/// alanlarını saklı sunucu kaydından gösterir; ağ çağrısı yapmaz.
class ListingGuideView extends StatelessWidget {
  const ListingGuideView({super.key, required this.listing});

  final ListingRecord listing;

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
    return _localSummary(context);
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
        // Yalnız kaynakta bilinen alanlar; "belirtilmemiş" satırları kalabalık yapar.
        if (listing.quota != null)
          _GuideField(
            label: 'Kontenjan',
            value: '${listing.quota} kişi',
            quote: null,
          ),
        if (listing.deadline != null)
          _GuideField(
            label: 'Son başvuru',
            value:
                '${listing.deadline!.day}.${listing.deadline!.month}.${listing.deadline!.year}',
            quote: null,
          ),
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
                    style: Theme.of(context).textTheme.bodyLarge
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
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic, height: 1.45),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
