import '../ui/premium.dart';
import '../ui/premium_widgets.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kamubul_core/kamubul_core.dart'
    show cityLabel, educationLabel, wallClock;

import '../data/listing_store.dart';

/// İndirilen sunucu ayrıntısı ve özgün metin; çevrimdışı da okunabilir.
class OfficialListingPage extends StatelessWidget {
  const OfficialListingPage({
    super.key,
    required this.listing,
    this.unavailable = false,
    this.cacheNotice,
    this.onAskAssistant,
  });

  final ListingRecord listing;
  final bool unavailable;
  final String? cacheNotice;

  /// "Asistana sor": ilanı Asistan sekmesinde bağlam olarak açar.
  final VoidCallback? onAskAssistant;

  String _date(DateTime? value) => value == null
      ? 'Belirtilmemiş'
      : '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _deadline(DateTime? value) {
    if (value == null) return _date(null);
    final wall = listing.criteriaListing == null ? value : wallClock(value);
    final date = _date(wall);
    if ((wall.hour == 23 && wall.minute == 59) ||
        (wall.hour == 0 && wall.minute == 0)) {
      return date;
    }
    return '$date • ${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
  }

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

  Widget _group(BuildContext context, Map group) {
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
    final rawLabel = group['label'];
    final label =
        rawLabel is String &&
            rawLabel.trim().isNotEmpty &&
            !RegExp(
              r'^Kadro\s*\d+$',
              caseSensitive: false,
            ).hasMatch(rawLabel.trim())
        ? rawLabel.trim()
        : 'Başvuru koşulları';
    final quota = group['quota'];
    final positionText = group['text'];
    final quotes =
        (group['quotes'] is Map ? (group['quotes'] as Map).values : const [])
            .whereType<String>()
            .where((q) => q.trim().isNotEmpty)
            .toSet();
    final theme = Theme.of(context);
    return Card(
      child: DefaultTextStyle.merge(
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (quota is int && quota > 0 && quota <= 1000000)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          PremiumShape.chipRadius,
                        ),
                      ),
                      child: Text(
                        '$quota kişi',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              if (occupations.isNotEmpty && occupations != label) ...[
                const SizedBox(height: 4),
                Text(occupations, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 12),
              Text('Yer: ${cities.isEmpty ? 'Belirtilmemiş' : cities}'),
              const SizedBox(height: 6),
              Text(
                'Eğitim: ${education.isEmpty
                    ? group['educationDescription'] is String
                          ? group['educationDescription']
                          : 'Belirtilmemiş'
                    : education}',
              ),
              const SizedBox(height: 6),
              Text(kpss),
              if (group['kpssYear'] is int &&
                  (group['kpssYear'] as int) >= 2000 &&
                  (group['kpssYear'] as int) <= 2100)
                Text('KPSS yılı: ${group['kpssYear']}'),
              const SizedBox(height: 6),
              Text(age),
              if (positionText is String && positionText.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('Pozisyonun tam koşulları'),
                  children: [
                    SelectableText(
                      positionText,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ],
              if (quotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('Kaynak alıntıları'),
                  children: [
                    for (final quote in quotes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText(
                          '“$quote”',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );

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
    // Eski yerel kayıtlar okunur; yeni sonuçların sahibi sunucu çıkarımıdır.
    final data =
        listing.criteriaListing ??
        (listing.aiGroups.isNotEmpty ? listing.matchingData : null);
    final rawGroups = data?['requirementGroups'];
    final groups = rawGroups is List ? rawGroups : const [];
    final rawPeriods = data?['applicationPeriods'];
    final periods = (rawPeriods is List ? rawPeriods : const [])
        .whereType<Map>()
        .where(
          (p) => p['text'] is String && (p['text'] as String).trim().isNotEmpty,
        )
        .toList();
    final extraction = data?['extraction'];
    final method = extraction is Map ? extraction['method'] : null;
    final aiUsed = method == 'ai' || method == 'hybrid';
    return Scaffold(
      appBar: AppBar(
        title: const Text('İlan ayrıntısı'),
        actions: const [ReadingScaleButton()],
      ),
      bottomNavigationBar: ListingActionBar(
        onOpenListing: () => _open(context),
        openLabel: 'Resmî belgeyi aç',
        onAskAssistant: onAskAssistant,
      ),
      body: ReadingScaleScope(
        child: ListView(
          padding: EdgeInsets.symmetric(
            vertical: 20,
            horizontal: MediaQuery.sizeOf(context).width > 800
                ? (MediaQuery.sizeOf(context).width - 760) / 2
                : 20,
          ),
          children: [
            Row(
              children: [
                InstitutionAvatar(title: listing.title, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    source,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              listing.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
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
                data?['aiProvenance'] is Map
                    ? 'Yapay zekâ özeti'
                    : 'İlan özeti',
                style: theme.textTheme.titleMedium,
              ),
            ],
            for (final text in listing.summary) ...[
              const SizedBox(height: 12),
              _summary(text),
            ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _fact(
                            context,
                            'Kontenjan',
                            listing.quota == null
                                ? 'Belirtilmemiş'
                                : '${listing.quota} kişi',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _fact(
                            context,
                            'Son başvuru',
                            periods.isNotEmpty
                                ? 'Başvuru takvimini inceleyin'
                                : _deadline(listing.deadline),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(),
                    ),
                    Text(
                      'Alım türü: ${listing.category.isEmpty ? 'Belirtilmemiş' : listing.category}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Yerler: ${listing.places.isEmpty ? 'Belirtilmemiş' : listing.places.join(', ')}',
                    ),
                    if (listing.publishedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Yayın: ${_date(listing.publishedAt)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (periods.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: ExpansionTile(
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  title: const Text('Başvuru takvimleri'),
                  children: [
                    for (final period in periods)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (period['deadline'] is String &&
                                DateTime.tryParse(
                                      period['deadline'] as String,
                                    ) !=
                                    null)
                              Text(
                                _deadline(
                                  DateTime.parse(period['deadline'] as String),
                                ),
                                style: theme.textTheme.titleSmall,
                              ),
                            SelectableText(
                              period['text'] as String,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Başvuru koşulları', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Koşullar aşağıdaki başlıklara göre ayrı değerlendirilir.',
              ),
              // ponytail: bound detail rendering to 100 source groups; larger
              // notices need a paginated position API, with the official link now.
              for (var i = 0; i < groups.length && i < 100; i++)
                if (groups[i] is Map)
                  _group(context, groups[i] as Map)
                else
                  const Text('Başvuru koşulları henüz belirlenemedi.'),
              if (groups.length > 100)
                const Text(
                  'İlk 100 koşul grubu gösteriliyor. Tamamı aşağıdaki ilan metninde yer alır.',
                ),
            ],
            if (aiUsed) ...[
              const SizedBox(height: 8),
              Text(
                'Yapay zekâ ile ayıklandı; hata olabilir.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (extraction is Map && extraction['status'] == 'partial') ...[
              const SizedBox(height: 8),
              const Text(
                'Bazı bilgiler henüz ayrıştırılamadı. İlanın tam metnini aşağıdan okuyabilirsiniz.',
              ),
            ],
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text('İlan metni', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            if (listing.noticeText.isNotEmpty)
              SelectableText(
                listing.noticeText,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
              )
            else
              const Text(
                'İlan metni henüz sunucuya alınamadı. Güncellendiğinde burada görünecek.',
              ),
            const SizedBox(height: 12),
            Text(
              groups.isEmpty
                  ? 'Başvuru koşulları resmî belgede yer alır; belgeyi açabilir '
                        'ya da "Bana uygun mu?" diye Asistan’a sorabilirsiniz.'
                  : 'Gösterilen koşullar başvuru uygunluğu garantisi değildir. Başvurmadan önce resmî belgeyi kontrol edin.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
