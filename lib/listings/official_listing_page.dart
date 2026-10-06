import '../ui/premium.dart';
import '../ui/premium_widgets.dart';
import '../ui/turkish.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kamubul_core/kamubul_core.dart' show educationLabel, wallClock;

import '../data/listing_store.dart';
import 'listing_facts.dart';
import 'notice_text.dart';

/// İlan ayrıntısı: üstte kısa özet, ardından pozisyonlar, başvuru takvimi ve
/// düzenlenmiş resmî metin. Bütün bilgiler saklı sunucu kaydındandır;
/// çevrimdışı da okunur.
class OfficialListingPage extends StatefulWidget {
  const OfficialListingPage({
    super.key,
    required this.listing,
    this.unavailable = false,
    this.cacheNotice,
    this.onAskAssistant,
    this.now,
  });

  final ListingRecord listing;
  final bool unavailable;
  final String? cacheNotice;

  /// "Asistana sor": ilanı Asistan sekmesinde bağlam olarak açar.
  final VoidCallback? onAskAssistant;

  /// Geri sayım için saat; testler sabit tarih verir.
  final DateTime? now;

  @override
  State<OfficialListingPage> createState() => _OfficialListingPageState();
}

class _OfficialListingPageState extends State<OfficialListingPage> {
  static const _initialPositions = 12;
  bool _allPositions = false;
  late final List<NoticeBlock> _blocks = parseNotice(widget.listing.noticeText);

  ListingRecord get listing => widget.listing;

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _deadline(DateTime value) {
    final wall = listing.criteriaListing == null ? value : wallClock(value);
    final date = _date(wall);
    if ((wall.hour == 23 && wall.minute == 59) ||
        (wall.hour == 0 && wall.minute == 0)) {
      return date;
    }
    return '$date • ${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
  }

  String get _source => switch (listing.sourceId) {
    'sbb' || 'kamuilan_sbb' => 'Strateji ve Bütçe Başkanlığı',
    'iskur' => 'İŞKUR',
    'ilangov' => 'ilan.gov.tr',
    'kariyerkapisi' => 'Kariyer Kapısı',
    'resmigazete' => 'Resmî Gazete',
    _ => 'Resmî kaynak',
  };

  Future<void> _open(String raw) async {
    final url = Uri.tryParse(raw);
    if (url == null || url.scheme != 'https') return;
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Kullanıcıya tek ve anlaşılır hata gösterilir.
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resmî sayfa açılamadı.')));
    }
  }

  /// Birkaç cümlelik özet: kim, kaç kişi, hangi pozisyonlar, ne zamana kadar.
  String _summarySentence() {
    // Kaynak sitesi işveren değildir: kurum adı yoksa cümle edilgen kurulur.
    final institution = listing.institution;
    final who = institution == null ? null : turkishTitleCase(institution);
    final positions = listing.positions;
    final count = positions.length;
    final quota = listing.quota;
    final spread = count > 1 ? ' ($count farklı pozisyon)' : '';
    final first = switch (listing.noticeKind) {
      'register' =>
        '${who == null ? 'Bu ilan' : '$who ilanı'} bir liste başvurusudur. Kişi sayısı belirtilmez; uygun bulunan başvurular listeye kaydedilir.',
      'amendment' => 'Bu, daha önce yayımlanan bir ilanın düzeltmesidir. Değişen kadrolar aşağıda listelenir.',
      'cancellation' => 'Bu, daha önce yayımlanan bir ilanın iptalidir.',
      'exam' => 'Bu bir sınav duyurusudur.',
      _ =>
        quota != null
            ? who == null
                  ? 'Bu ilanla toplam $quota kişi alınacak$spread.'
                  : '$who, toplam $quota kişi alacak$spread.'
            : count > 1
            ? who == null
                  ? 'Bu ilanda $count farklı pozisyon için alım yapılacak.'
                  : '$who, $count farklı pozisyon için alım yapacak.'
            : who == null
            ? 'Bu ilanla personel alımı yapılacak.'
            : '$who, personel alımı yapacak.',
    };
    final deadline = listing.deadline, estimate = listing.deadlineEstimate;
    final when = deadline != null
        ? ' Son başvuru: ${_deadline(deadline)}.'
        : estimate != null
        ? ' Başvuru süresi yayından itibaren sayılıyor; tahmini son gün ${_date(wallClock(estimate))}.'
        : listing.applicationPeriods.isNotEmpty
        ? ' Pozisyonlara göre farklı başvuru tarihleri var.'
        : '';
    return first + when;
  }

  Widget _stat(String label, String value, {Widget? footer}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // Dar ekran ve büyük yazıda rakam satırı kırılmaz, ölçeklenir.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            // Kartlardaki "5 kişi" çipleriyle uyumlu: okunur, ama başlıktan büyük değil.
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 6), footer],
      ],
    );
  }

  Widget _factRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text, {Color? color}) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tone,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = widget.now ?? DateTime.now();
    final deadline = listing.deadline, estimate = listing.deadlineEstimate;
    final periods = listing.applicationPeriods;
    final positions = listing.positions;
    final quotaText = listing.noticeKind == 'register'
        ? 'Liste'
        : listing.quota == null
        ? '—'
        : '${listing.quota} kişi';
    final Widget deadlineStat;
    if (deadline != null) {
      deadlineStat = _stat(
        'Son başvuru',
        _deadline(deadline),
        footer: DeadlinePill(
          text: countdownLabel(deadline, now)!,
          daysLeft: deadlineDays(deadline, now),
          expired: !deadline.isAfter(now),
        ),
      );
    } else if (estimate != null) {
      deadlineStat = _stat(
        'Son başvuru (tahmini)',
        '≈ ${_date(wallClock(estimate))}',
        footer: DeadlinePill(
          text: countdownLabel(estimate, now)!,
          daysLeft: deadlineDays(estimate, now),
          expired: !estimate.isAfter(now),
        ),
      );
    } else {
      deadlineStat = _stat(
        'Son başvuru',
        periods.isNotEmpty ? 'Takvime bakın' : '—',
      );
    }
    final cities = listing.cityNames;
    final education = listing.educationLevels;
    final kpss = listing.kpssSummaries;
    final ages = listing.ageSummaries;
    final twin = listing.twin;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Özet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (listing.aiExtracted) const _AiBadge(),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final quotaStat = _stat(
                listing.fieldFromAi('quota') ? 'Kontenjan (YZ)' : 'Kontenjan',
                quotaText,
              );
              final positionStat = positions.length > 1
                  ? _stat('Pozisyon', '${positions.length}')
                  : null;
              // Dar ekran/büyük yazı: kutular sıkışmak yerine iki satıra dağılır.
              final roomy =
                  constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) >=
                  300;
              if (!roomy) {
                return Wrap(
                  spacing: 28,
                  runSpacing: 14,
                  children: [quotaStat, deadlineStat, ?positionStat],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: quotaStat),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: positionStat == null ? 6 : 5,
                    child: deadlineStat,
                  ),
                  if (positionStat != null) ...[
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: positionStat),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            _summarySentence(),
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          if (cities.isNotEmpty)
            _factRow(Icons.place_outlined, 'Yer', turkishList(cities)),
          if (education.isNotEmpty)
            _factRow(Icons.school_outlined, 'Eğitim', turkishList(education)),
          if (kpss.isNotEmpty)
            _factRow(Icons.fact_check_outlined, 'KPSS', turkishList(kpss)),
          if (ages.isNotEmpty)
            _factRow(Icons.cake_outlined, 'Yaş', turkishList(ages)),
          if (estimate != null && listing.deadlineRule != null)
            _note(
              Icons.info_outline_rounded,
              'Tahmini tarih ilandaki kurala göre hesaplandı: '
              '“${listing.deadlineRule}” Kesin tarihi resmî ilandan doğrulayın.',
            ),
          if (twin != null)
            _note(
              Icons.link_rounded,
              'Bu ilanın metni ilan.gov.tr’de yayımlanan aynı ilandan alındı.',
            ),
          if (listing.aiExtracted)
            _note(
              Icons.auto_awesome_outlined,
              'Yapay zekâ ile ayıklandı; hata olabilir.',
              color: _AiBadge.tone(theme.brightness),
            ),
        ],
      ),
    );
  }

  Widget _positionCard(Map<Object?, Object?> group) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rawLabel = group['label'];
    final occupations = [
      for (final value
          in group['occupations'] is List
              ? group['occupations'] as List
              : const [])
        if (value is String && value.trim().isNotEmpty) value.trim(),
    ];
    final label =
        rawLabel is String &&
            rawLabel.trim().isNotEmpty &&
            !RegExp(
              r'^Kadro\s*\d+$',
              caseSensitive: false,
            ).hasMatch(rawLabel.trim())
        ? rawLabel.trim()
        : occupations.isNotEmpty
        ? occupations.join(', ')
        : 'Başvuru koşulları';
    final quota = group['quota'];
    final validQuota = quota is int && quota > 0 && quota <= 1000000
        ? quota
        : null;
    final chips = <(IconData, String)>[
      for (final value in [
        for (final e
            in group['education'] is List
                ? group['education'] as List
                : const [])
          if (e is String) educationLabel(e),
      ].take(3))
        (Icons.school_outlined, value),
      if (group['educationDescription'] is String &&
          (group['education'] is! List || (group['education'] as List).isEmpty))
        (Icons.school_outlined, 'Eğitim şartı aşağıda'),
      if (kpssLabel(group) case final String kpss)
        (Icons.fact_check_outlined, kpss),
      if (ageLabel(group) case final String age) (Icons.cake_outlined, age),
    ];
    final text = group['text'];
    final requirements = text is String
        ? positionRequirements(text, label, validQuota)
        : const <String>[];
    final description = group['educationDescription'];
    final origins = group['fieldOrigins'];
    final ai = origins is Map && origins.values.contains('ai');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              if (validQuota != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(
                      PremiumShape.chipRadius,
                    ),
                  ),
                  child: Text(
                    '$validQuota kişi',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (icon, value) in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                        PremiumShape.chipRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: scheme.primary),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            value,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (description is String && description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
          if (requirements.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Aranan nitelikler',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final line in requirements)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (ai) ...[
            const SizedBox(height: 10),
            Text(
              'Bu pozisyonun bazı bilgileri yapay zekâ ile ayıklandı; hata olabilir.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _AiBadge.tone(theme.brightness),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {String? trailing}) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final positions = listing.positions;
    final periods = listing.applicationPeriods;
    final shown = _allPositions
        ? positions
        : positions.take(_initialPositions).toList();
    final institution = listing.institution;
    final published = listing.publishedAt;
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('İlan ayrıntısı'),
        actions: const [ReadingScaleButton()],
      ),
      bottomNavigationBar: ListingActionBar(
        onOpenListing: () => _open(listing.url),
        openLabel: listing.sourceId == 'kariyerkapisi'
            ? 'Kariyer Kapısı’nda aç'
            : 'Resmî ilanı aç',
        onAskAssistant: widget.onAskAssistant,
      ),
      body: ReadingScaleScope(
        child: SelectionArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              width > 800 ? (width - 760) / 2 : 20,
              16,
              width > 800 ? (width - 760) / 2 : 20,
              28,
            ),
            children: [
              Row(
                children: [
                  InstitutionAvatar(title: listing.title, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          turkishTitleCase(institution ?? _source),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (institution != null || published != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (institution != null) _source,
                              if (published != null)
                                'Yayın ${_date(published)}',
                            ].join(' · '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
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
              if (widget.cacheNotice != null) ...[
                const SizedBox(height: 10),
                _note(Icons.cloud_off_rounded, widget.cacheNotice!),
              ],
              if (widget.unavailable) ...[
                const SizedBox(height: 4),
                _note(
                  Icons.event_busy_rounded,
                  'Bu ilan artık yayında değil. Başvuru durumunu resmî kaynaktan kontrol edin.',
                  color: scheme.error,
                ),
              ],
              const SizedBox(height: 18),
              if (listing.detailOnSource)
                _SourceOnlyCard(onOpen: () => _open(listing.url))
              else
                _summaryCard(),
              if (listing.summary.isNotEmpty) ...[
                _sectionTitle(
                  listing.criteriaListing?['aiProvenance'] is Map
                      ? 'Yapay zekâ özeti'
                      : 'İlan özeti',
                ),
                for (final text in listing.summary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(text, style: theme.textTheme.bodyLarge),
                  ),
              ],
              if (periods.isNotEmpty) ...[
                _sectionTitle('Başvuru takvimi'),
                for (final period in periods)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (period['deadline'] is String &&
                            DateTime.tryParse(period['deadline'] as String) !=
                                null) ...[
                          Text(
                            _deadline(
                              DateTime.parse(period['deadline'] as String),
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          period['text'] as String,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (positions.isNotEmpty) ...[
                _sectionTitle(
                  positions.length > 1 ? 'Pozisyonlar' : 'Başvuru koşulları',
                  trailing: positions.length > 1 ? '${positions.length}' : null,
                ),
                for (final group in shown) _positionCard(group),
                if (shown.length < positions.length)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _allPositions = true),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(
                        'Tüm pozisyonları göster (${positions.length})',
                      ),
                    ),
                  ),
              ],
              _sectionTitle('İlan metni'),
              if (_blocks.isEmpty)
                Text(
                  listing.detailOnSource
                      ? 'Bu ilanın tam metni Kariyer Kapısı’nda yayımlanıyor.'
                      : 'İlan metni henüz sunucuya alınamadı. Güncellendiğinde burada görünecek.',
                  style: theme.textTheme.bodyLarge,
                )
              else
                for (final block in _blocks) NoticeBlockView(block),
              const SizedBox(height: 16),
              Text(
                'Gösterilen bilgiler başvuru uygunluğu garantisi değildir. '
                'Başvurmadan önce resmî ilanı kontrol edin.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yapay zekâ katkısı rozeti: mor tonda, kısa ve dürüst.
class _AiBadge extends StatelessWidget {
  const _AiBadge();

  static Color tone(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFB9ADFF)
      : const Color(0xFF5B3FD9);

  @override
  Widget build(BuildContext context) {
    final color = tone(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Yapay zekâ',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Metni sunucuya alınamayan Kariyer Kapısı ilanı: boş sayfa yerine açık
/// bir yönlendirme.
class _SourceOnlyCard extends StatelessWidget {
  const _SourceOnlyCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ayrıntılar Kariyer Kapısı’nda',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bu ilanın şartları, kontenjanı ve başvuru tarihleri Kariyer '
            'Kapısı’nda yayımlanıyor. Başvuru da oradan yapılır.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Kariyer Kapısı’nda aç'),
          ),
        ],
      ),
    );
  }
}
