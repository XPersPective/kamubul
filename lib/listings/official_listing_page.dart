import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/listing_store.dart';

/// Kaynağında yapılandırılmış ayrıntı sunmayan ilanlar için yerel özet.
/// Boş alanlar tahmin edilmez; belgeye geçiş kullanıcıya bırakılır.
class OfficialListingPage extends StatelessWidget {
  const OfficialListingPage({
    super.key,
    required this.listing,
    this.unavailable = false,
    this.cacheNotice,
  });

  final ListingRecord listing;
  final bool unavailable;
  final String? cacheNotice;

  String _date(DateTime? value) => value == null
      ? 'Belirtilmemiş'
      : '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  Future<void> _open(BuildContext context) async {
    final url = Uri.tryParse(listing.url);
    if (url == null || url.scheme != 'https') return;
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Kullanıcıya tek ve anlaşılır hata gösterilir.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resmî belge açılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = switch (listing.sourceId) {
      'kamuilan_sbb' => 'Strateji ve Bütçe Başkanlığı',
      'kariyerkapisi' => 'Kariyer Kapısı',
      'resmigazete' => 'Resmî Gazete',
      _ => 'Resmî kaynak',
    };
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('İlan ayrıntısı')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Resmî belgeyi aç'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            source,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(listing.title, style: theme.textTheme.headlineSmall),
          if (cacheNotice != null) ...[
            const SizedBox(height: 12),
            Text(cacheNotice!),
          ],
          if (unavailable) ...[
            const SizedBox(height: 12),
            const Text(
              'Bu ilan artık yayında değil. Başvuru durumunu resmî kaynaktan kontrol edin.',
            ),
          ],
          for (final text in listing.summary) ...[
            const SizedBox(height: 12),
            Text(text),
          ],
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Alım türü'),
                  subtitle: Text(
                    listing.category.isEmpty
                        ? 'Belirtilmemiş'
                        : listing.category,
                  ),
                ),
                ListTile(
                  title: const Text('Kontenjan'),
                  subtitle: Text(
                    listing.quota == null
                        ? 'Belirtilmemiş'
                        : '${listing.quota} kişi',
                  ),
                ),
                ListTile(
                  title: const Text('Son başvuru'),
                  subtitle: Text(_date(listing.deadline)),
                ),
                ListTile(
                  title: const Text('Yayın tarihi'),
                  subtitle: Text(_date(listing.publishedAt)),
                ),
                ListTile(
                  title: const Text('Yerler'),
                  subtitle: Text(
                    listing.places.isEmpty
                        ? 'Belirtilmemiş'
                        : listing.places.join(', '),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Başvuru koşulları bu kaynakta henüz güvenilir biçimde ayıklanamadı. '
            'Başvurmadan önce resmî belgeyi kontrol edin.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
