part of '../home_page.dart';

/// Liste kartı ve bilgi çipleri.
extension _HomeListingCard on _KamuHomePageState {
  Widget _listingCard(ListingRecord record) {
    final unresolved = _matchVisible(record) == CriteriaMatch.unknown;
    final expired = record.expired;
    final profileMatch = _profileMatchCache.putIfAbsent(
      record,
      () => _searches.any(
        (search) =>
            !search.hasInvalidCriteria &&
            search.name == 'Sizin için' &&
            ((search.criteria?.values.keys.any(
                      (key) => !['version', 'keywordScope'].contains(key),
                    ) ??
                    false) ||
                [
                  'sehir',
                  'yas',
                  'egitim',
                  'kpss',
                ].any((key) => (search.filters[key] ?? '').isNotEmpty)) &&
            search.matchListing(record, now: DateTime.now()) ==
                CriteriaMatch.match,
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final estimate = record.deadline == null ? record.deadlineEstimate : null;
    final shownDeadline = record.deadline ?? estimate;
    final days = deadlineDays(shownDeadline, now);
    final variedDeadlines = record.applicationPeriods.isNotEmpty;
    final positionCount = record.positions.length;
    final deadlineText = variedDeadlines
        ? 'Başvuru takvimini inceleyin'
        : shownDeadline != null
        ? '${estimate != null ? '≈ ' : ''}${_date(shownDeadline)} • ${countdownLabel(shownDeadline, now)}'
        : switch (record.noticeKind) {
            'amendment' => 'Düzeltme ilanı',
            'cancellation' => 'İptal ilanı',
            _ when record.detailOnSource => 'Tarih Kariyer Kapısı’nda',
            _ => 'Son tarih belirtilmemiş',
          };
    final facts = <Widget>[
      if (record.noticeKind == 'register')
        _factChip(Icons.how_to_reg_outlined, 'Liste başvurusu')
      else if (record.quota != null)
        _factChip(
          record.fieldFromAi('quota')
              ? Icons.auto_awesome_outlined
              : Icons.groups_outlined,
          '${record.quota} kişi',
        ),
      if (positionCount > 1)
        _factChip(Icons.work_outline_rounded, '$positionCount pozisyon'),
      if (record.places.isNotEmpty)
        _factChip(Icons.place_outlined, record.places.join(', ')),
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _showListing(record),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InstitutionAvatar(title: record.title),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          // Kurum adı kategoriden ("Personel Alımı") daha çok bilgi taşır.
                          child: Text(
                            turkishTitleCase(
                              record.institution ??
                                  (record.category.isEmpty
                                      ? 'Kamu ilanı'
                                      : record.category),
                            ),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16.5,
                                letterSpacing: -0.2,
                                height: 1.3,
                              ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: record.saved ? 'Kaydı kaldır' : 'Kaydet',
                    onPressed: () => _toggleSaved(record),
                    icon: Icon(
                      record.saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: record.saved ? scheme.primary : null,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 10),
                child: Text(
                  record.publishedAt == null
                      ? _sourceLabel(record.sourceId)
                      : '${_sourceLabel(record.sourceId)}  ·  Yayın ${_date(record.publishedAt)}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (unresolved)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: PremiumStatus.held(Theme.of(context).brightness),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Şartları kontrol et • bazı kriterler doğrulanamadı.',
                        ),
                      ),
                    ],
                  ),
                ),
              if (_tab == 1 &&
                  record.publishedAt != null &&
                  record.publishedAt!.isAfter(DateTime.now()))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Yayın tarihi bekleniyor',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.primary),
                  ),
                ),
              if (profileMatch)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '✓ Arama tercihlerinizle eşleşiyor',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.primary),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    DeadlinePill(
                      text: deadlineText,
                      daysLeft: variedDeadlines ? null : days,
                      expired: expired || (estimate != null && days == -1),
                    ),
                    ...facts,
                  ],
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => _showListing(record),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('İlanı incele'),
                  ),
                  TextButton.icon(
                    onPressed: () => _update(() {
                      if (_assistantListing?.url != record.url) {
                        _chatMessages.clear();
                      }
                      _assistantListing = record;
                      _tab = 2;
                    }),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Asistana sor'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _factChip(IconData icon, String label, {bool urgent = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: urgent
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
