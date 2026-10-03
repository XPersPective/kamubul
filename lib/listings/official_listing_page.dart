import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kamubul_core/kamubul_core.dart' show cityLabel, educationLabel;

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

  Widget _summary(String text) {
    final entries = listing.criteriaListing?['summary'];
    if (entries is List) {
      for (final entry in entries.take(5).whereType<Map>()) {
        final original = entry['text'], quote = entry['quote'];
        final label = entry['scopeLabel'];
        if (original is! String ||
            quote is! String ||
            quote.length < 30 ||
            quote.length > 600 ||
            !quote.contains(original) ||
            (label != null &&
                (label is! String ||
                    label.trim().isEmpty ||
                    label.length > 50))) {
          continue;
        }
        if (text != (label == null ? original : '$label: $original')) continue;
        return Card(
          child: ExpansionTile(
            title: Text(text),
            subtitle: const Text('Kaynak alıntısını göster'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [SelectableText('“$quote”')],
          ),
        );
      }
    }
    return Text(text);
  }

  Widget _group(BuildContext context, Map group, int index) {
    String values(String key, String Function(String) label) =>
        (group[key] is List ? group[key] as List : const [])
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .map(label)
            .join(', ');
    final occupations = values('occupations', (s) => s);
    final cities = values('cities', cityLabel);
    final education = values('education', educationLabel);
    final score = group['kpssScore'];
    final type = group['kpssType'];
    final kpss = switch (group['kpssStatus']) {
      'not_required'
          when group['kpssType'] == null &&
              score == null &&
              group['kpssYear'] == null =>
        'KPSS şartı yok',
      'required' =>
        'KPSS gerekli${type is String && ['P3', 'P93', 'P94'].contains(type) ? ' · $type' : ' · puan türü belirtilmemiş'}'
            '${score is num && score.isFinite && score >= 0 && score <= 100 ? ' · en az $score puan' : ' · taban puan belirtilmemiş'}',
      _ => 'KPSS şartı: henüz belirlenemedi',
    };
    final ageFields = <String>[];
    for (final (key, label) in [('minAge', 'En az'), ('maxAge', 'En fazla')]) {
      final value = group[key];
      if (value is int && value >= 0 && value <= 130) {
        ageFields.add('$label $value yaş');
      }
    }
    for (final (key, label) in [
      ('ageReferenceDate', 'Yaş hesabı tarihi'),
      ('bornOnOrAfter', 'Doğum tarihi en erken'),
      ('bornOnOrBefore', 'Doğum tarihi en geç'),
    ]) {
      final value = group[key];
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed != null &&
          value == parsed.toIso8601String().substring(0, 10)) {
        ageFields.add('$label: ${_date(parsed)}');
      }
    }
    final age = group['ageStatus'] == 'known' && ageFields.isNotEmpty
        ? ageFields.join(' · ')
        : group['ageStatus'] == 'no_restriction' &&
              [
                'minAge',
                'maxAge',
                'ageReferenceDate',
                'bornOnOrAfter',
                'bornOnOrBefore',
              ].every((key) => group[key] == null)
        ? 'Yaş sınırı yok'
        : 'Yaş şartı: henüz belirlenemedi';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kadro ${index + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (occupations.isNotEmpty) Text(occupations),
            const SizedBox(height: 12),
            Text('Yer: ${cities.isEmpty ? 'Belirtilmemiş' : cities}'),
            Text('Eğitim: ${education.isEmpty ? 'Belirtilmemiş' : education}'),
            Text(kpss),
            Text(age),
            if (group['kpssYear'] is int &&
                (group['kpssYear'] as int) >= 2000 &&
                (group['kpssYear'] as int) <= 2100)
              Text('KPSS yılı: ${group['kpssYear']}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = switch (listing.sourceId) {
      'sbb' || 'kamuilan_sbb' => 'Strateji ve Bütçe Başkanlığı',
      'iskur' => 'İŞKUR',
      'ilangov' => 'ilan.gov.tr',
      'kariyerkapisi' => 'Kariyer Kapısı',
      'resmigazete' => 'Resmî Gazete',
      _ => 'Resmî kaynak',
    };
    final theme = Theme.of(context);
    final data = listing.criteriaListing;
    final rawGroups = data?['requirementGroups'];
    final groups = rawGroups is List ? rawGroups : const [];
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
        padding: EdgeInsets.symmetric(
          vertical: 20,
          horizontal: MediaQuery.sizeOf(context).width > 800
              ? (MediaQuery.sizeOf(context).width - 760) / 2
              : 20,
        ),
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
          if (listing.summary.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              data?['aiProvenance'] is Map ? 'Yapay zekâ özeti' : 'İlan özeti',
              style: theme.textTheme.titleMedium,
            ),
          ],
          for (final text in listing.summary) ...[
            const SizedBox(height: 12),
            _summary(text),
          ],
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Alım türü'),
                  subtitle: Text(
                    listing.category.isEmpty
                        ? 'Belirtilmemiş'
                        : listing.category,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Kontenjan'),
                  subtitle: Text(
                    listing.quota == null
                        ? 'Belirtilmemiş'
                        : '${listing.quota} kişi',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Son başvuru'),
                  subtitle: Text(_date(listing.deadline)),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Yayın tarihi'),
                  subtitle: Text(_date(listing.publishedAt)),
                ),
                ListTile(
                  leading: const Icon(Icons.place_outlined),
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
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Kadro koşulları', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Her kadronun koşulları ayrı değerlendirilir. Eksik bilgi uygunluk anlamına gelmez.',
            ),
            // ponytail: bound detail rendering to 100 source groups; larger
            // notices need a paginated position API, with the official link now.
            for (var i = 0; i < groups.length && i < 100; i++)
              if (groups[i] is Map)
                _group(context, groups[i] as Map, i)
              else
                Text('Kadro ${i + 1}: koşullar henüz belirlenemedi'),
            if (groups.length > 100)
              const Text(
                'İlk 100 kadro gösteriliyor. Tüm kadrolar için resmî belgeyi açın.',
              ),
          ],
          const SizedBox(height: 12),
          Text(
            groups.isEmpty
                ? 'Başvuru koşulları bu kaynakta henüz güvenilir biçimde ayıklanamadı. '
                      'Başvurmadan önce resmî belgeyi kontrol edin.'
                : 'Gösterilen koşullar başvuru uygunluğu garantisi değildir. Başvurmadan önce resmî belgeyi kontrol edin.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
