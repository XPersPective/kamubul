part of '../home_page.dart';

/// Kayıtlı aramaları yönetme, düzenleme ve özetleme.
extension _HomeSearches on _KamuHomePageState {
  Future<void> _manageSearches() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            Text(
              'Kayıtlı aramalar',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            if (_searches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Henüz kayıtlı arama yok. Süzgeçleri seçip kaydedin.',
                ),
              ),
            for (final search in _searches)
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(search.name),
                subtitle: Text(
                  '${_filterSummary(search)}\nBildirim: ${_modeLabel(alertModeOf(search.filters))}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  tooltip: 'Arama işlemleri',
                  icon: const Icon(Icons.notifications_outlined),
                  onSelected: (value) async {
                    if (value == 'rename') {
                      final name = await _promptRename(search);
                      final trimmed = name?.trim();
                      if (trimmed == null || trimmed.isEmpty) return;
                      await _store.updateSavedSearch(
                        search.copyWith(name: trimmed),
                      );
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                      return;
                    }
                    if (value == 'delete') {
                      final ok = await _confirmDeleteSearch(search);
                      if (ok != true) return;
                      final id = search.id;
                      if (id != null) await _store.deleteSavedSearch(id);
                      // Silinen arama seçiliyse kriterleri de ekranda kalmasın.
                      if (_activeSearchId == search.id) _clearFilters();
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                      return;
                    }
                    if (value == 'edit') {
                      final updated = await _promptEditSearch(search);
                      if (updated == null) return;
                      await _store.updateSavedSearch(updated);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                      return;
                    }
                    final filters = <String, String>{...search.filters};
                    filters['bildirim'] = value;
                    await _store.updateSavedSearch(
                      search.copyWith(filters: filters),
                    );
                    await _loadLocal();
                  },
                  itemBuilder: (menuContext) => [
                    PopupMenuItem(
                      value: 'instant',
                      enabled: !search.hasInvalidCriteria,
                      child: Text('Anlık bildirim'),
                    ),
                    PopupMenuItem(
                      value: 'digest',
                      enabled: !search.hasInvalidCriteria,
                      child: const Text('Günlük özet'),
                    ),
                    PopupMenuItem(
                      value: 'off',
                      enabled: !search.hasInvalidCriteria,
                      child: const Text('Kapalı'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    PopupMenuItem(
                      value: 'rename',
                      enabled: !search.hasInvalidCriteria,
                      child: Text('Yeniden adlandır'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Sil')),
                  ],
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _applySearch(search);
                },
              ),
          ],
        ),
      ),
    );
    await _loadLocal();
    if (changed == true && _activeSearchId != null && mounted) {
      final stillExists = _searches.any((s) => s.id == _activeSearchId);
      if (!stillExists) {
        _update(() {
          _activeSearchId = null;
          _includeUnknown = false;
        });
      }
    }
  }

  /// Tek form yeni/düzenlenen aramanın profilini doğrular; ileri kriterleri korur.
  Future<SavedSearch?> _promptEditSearch(
    SavedSearch search, {
    bool creating = false,
  }) async {
    var values = <String, Object?>{};
    try {
      values = {...search.effectiveCriteria.values};
      if (values['education'] case final List education) {
        values['education'] = education
            .cast<String>()
            .map(educationLabel)
            .toSet()
            .toList();
      }
      if (values['cities'] case final List cities) {
        values['cities'] = cities
            .cast<String>()
            .map(cityLabel)
            .toSet()
            .toList();
      }
    } on FormatException {
      /* Kullanıcı aşağıdaki uyarıyla onarabilir. */
    }
    final name = TextEditingController(text: search.name);
    final age = TextEditingController(
      text: '${values['age'] ?? search.filters['yas'] ?? ''}',
    );
    final type = TextEditingController(
      text: '${values['kpssType'] ?? search.filters['kpss'] ?? ''}',
    );
    final score = TextEditingController(text: '${values['kpssScore'] ?? ''}');
    final year = TextEditingController(text: '${values['kpssYear'] ?? ''}');
    final keyword = TextEditingController(text: '${values['keyword'] ?? ''}');
    var keywordScope = values['keywordScope'] == 'title' ? 'title' : 'full';
    final ageDate = TextEditingController(
      text: '${values['ageAsOf'] ?? dayKey(wallClock(DateTime.now()))}',
    );
    String? error;
    final pendingChoices = <String, TextEditingController>{};
    final occupations = <String>{}, institutions = <String>{};
    for (final record in _records) {
      final listing = record.criteriaListing;
      if (listing == null || listing['active'] == false) continue;
      if (listing['institution'] case final String institution) {
        if (institution.trim().isNotEmpty && institution.length <= 100) {
          institutions.add(institution.trim());
        }
      }
      final groups = listing['requirementGroups'];
      for (final source in [
        listing,
        if (groups is List) ...groups.whereType<Map>(),
      ]) {
        final raw = source['occupations'];
        if (raw is List) {
          occupations.addAll(
            raw
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty && s.length <= 100)
                .map((s) => s.trim()),
          );
        }
      }
    }
    Widget criteriaSelector(
      String key,
      String label,
      Iterable<String> options,
      StateSetter update,
    ) {
      final selected = (values[key] as List?)?.cast<String>() ?? <String>[];
      final available = {...options, ...selected}.toList()
        ..sort((a, b) => foldTurkish(a).compareTo(foldTurkish(b)));
      TextEditingController? editor;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Autocomplete<String>(
            optionsBuilder: (text) => text.text.trim().isEmpty
                ? const Iterable<String>.empty()
                : available
                      .where(
                        (option) =>
                            foldTurkish(option)
                                .contains(foldTurkish(text.text)) &&
                            !selected.any(
                              (s) => foldTurkish(s) == foldTurkish(option),
                            ),
                      )
                      .take(20),
            fieldViewBuilder: (context, controller, focus, submit) {
              editor = controller;
              pendingChoices[key] = controller;
              return TextFormField(
                key: ValueKey('criteria-$key'),
                controller: controller,
                focusNode: focus,
                onFieldSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: label,
                  hintText: 'Seçmek için yazın',
                  helperText: available.isEmpty
                      ? 'Katalogda henüz seçenek yok.'
                      : 'En çok 10 seçim; boş bırakmak filtreyi kaldırır.',
                  helperMaxLines: 3,
                ),
              );
            },
            onSelected: (option) {
              update(() {
                if (selected.length >= 10) {
                  error = '$label için en çok 10 seçim yapabilirsiniz.';
                } else {
                  values[key] = [...selected, option];
                  error = null;
                }
              });
              editor?.clear();
            },
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final option in selected)
                InputChip(
                  deleteButtonTooltipMessage: '$label: $option seçimini kaldır',
                  label: Text(
                    option,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: () => update(
                    () => values[key] = selected
                        .where((s) => s != option)
                        .toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      );
    }

    try {
      return await showDialog<SavedSearch>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text(creating ? 'Aramayı kaydet' : 'Aramayı düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  if (search.hasInvalidCriteria)
                    const Text(
                      'Bu aramanın kriterleri okunamadı. Kaydetmeden önce tüm kriterleri yeniden kontrol edin.',
                    ),
                  TextField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Arama adı'),
                  ),
                  TextField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Yaşınız (uyum için, isteğe bağlı)',
                      helperText:
                          '16–80; boş bırakırsanız yaş filtresi uygulanmaz.',
                      helperMaxLines: 3,
                    ),
                  ),
                  TextField(
                    controller: ageDate,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Yaş bilgisi tarihi (YYYY-AA-GG)',
                      helperText: 'Yaşınız değiştiğinde güncelleyin. 366 günden eski veya gelecekteki bilgiyle yaş uygunluğu doğrulanmaz; kesin uygunluk bildirimi gönderilmez.',
                      helperMaxLines: 6,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ageDate.text = dayKey(wallClock(DateTime.now())),
                    child: const Text('Yaşımı bugün doğrula'),
                  ),
                  TextField(
                    controller: type,
                    maxLength: 4,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'KPSS puan türü (örn. P3, P93)',
                    ),
                  ),
                  TextField(
                    controller: score,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'KPSS puanınız (0–100)',
                      helperText: 'İlanın taban puanıyla karşılaştırılır.',
                      helperMaxLines: 3,
                    ),
                  ),
                  TextField(
                    controller: year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'KPSS sınav yılı (isteğe bağlı)',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('criteria-keyword'),
                    controller: keyword,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Anahtar kelime (isteğe bağlı)',
                      helperText: 'Arama adınız kişisel etikettir; ilanı bu kelimeyle süzebilirsiniz.',
                      helperMaxLines: 3,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: keywordScope,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kelimenin aranacağı alan',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'title',
                        child: Text('İlan başlığı'),
                      ),
                      DropdownMenuItem(
                        value: 'full',
                        child: Text('Başlık, kurum ve meslek'),
                      ),
                    ],
                    onChanged: (value) => update(() => keywordScope = value!),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aynı alandaki seçimler alternatiftir. Farklı alanların koşulları birlikte aranır.',
                  ),
                  criteriaSelector('cities', 'Şehirler', turkishCities, update),
                  criteriaSelector('education', 'Eğitim düzeyleri', const [
                    'Lise',
                    'Ön lisans',
                    'Lisans',
                    'Yüksek lisans',
                    'Doktora',
                  ], update),
                  criteriaSelector('categories', 'İlan türleri', const [
                    'işçi',
                    'personel',
                    'belediye',
                  ], update),
                  criteriaSelector(
                    'occupations',
                    'Meslekler',
                    occupations,
                    update,
                  ),
                  criteriaSelector(
                    'institutions',
                    'Kurumlar',
                    institutions,
                    update,
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  if (pendingChoices.values.any(
                    (c) => c.text.trim().isNotEmpty,
                  )) {
                    update(
                      () => error = 'Listeden bir seçenek seçin veya yazdığınız seçim metnini temizleyin. Serbest metin için Anahtar kelime alanını kullanın.',
                    );
                    return;
                  }
                  try {
                    if (name.text.trim().isEmpty ||
                        name.text.trim().length > 80) {
                      throw const FormatException(
                        'Arama adı 1–80 karakter olmalı.',
                      );
                    }
                    final criteria = <String, Object?>{...values};
                    criteria.remove('keyword');
                    criteria.remove('keywordScope');
                    if (keyword.text.trim().isNotEmpty) {
                      criteria['keyword'] = keyword.text.trim();
                      criteria['keywordScope'] = keywordScope;
                    }
                    criteria.remove('age');
                    criteria.remove('ageAsOf');
                    criteria.remove('kpssType');
                    criteria.remove('kpssScore');
                    criteria.remove('kpssYear');
                    if (age.text.trim().isNotEmpty) {
                      criteria['age'] = int.parse(age.text.trim());
                      criteria['ageAsOf'] = ageDate.text.trim();
                    }
                    if (type.text.trim().isNotEmpty) {
                      criteria['kpssType'] = type.text.trim().toUpperCase();
                    }
                    if (score.text.trim().isNotEmpty) {
                      criteria['kpssScore'] = double.parse(
                        score.text.trim().replaceAll(',', '.'),
                      );
                    }
                    if (year.text.trim().isNotEmpty) {
                      criteria['kpssYear'] = int.parse(year.text.trim());
                    }
                    final validated = SearchCriteria.parse(criteria);
                    final filters = <String, String>{...search.filters};
                    filters.remove('q');
                    filters.remove('sehir');
                    filters.remove('kategori');
                    if (keyword.text.trim().isNotEmpty) {
                      filters['q'] = keyword.text.trim();
                    }
                    final cities = validated.values['cities'] as List?;
                    if (cities?.length == 1) {
                      filters['sehir'] = cities!.single as String;
                    }
                    final categories = validated.values['categories'] as List?;
                    if (categories?.length == 1) {
                      final index = const [
                        'işçi',
                        'personel',
                        'belediye',
                      ].indexOf(categories!.single as String);
                      if (index >= 0) filters['kategori'] = '${index + 1}';
                    }
                    for (final key in [
                      'yas',
                      'yasTarih',
                      'egitim',
                      'kpss',
                      'kpssPuan',
                    ]) {
                      filters.remove(key);
                    }
                    if (validated.values['age'] != null) {
                      filters['yas'] = '${validated.values['age']}';
                      filters['yasTarih'] = ageDate.text.trim();
                    }
                    final education = validated.values['education'] as List?;
                    if (education?.length == 1) {
                      filters['egitim'] = education!.single as String;
                    }
                    if (validated.values['kpssType'] != null) {
                      filters['kpss'] = '${validated.values['kpssType']}';
                    }
                    if (validated.values['kpssScore'] != null) {
                      filters['kpssPuan'] = '${validated.values['kpssScore']}';
                    }
                    Navigator.pop(
                      dialogContext,
                      search.copyWith(
                        name: name.text.trim(),
                        filters: filters,
                        criteria: validated,
                      ),
                    );
                  } on FormatException {
                    update(
                      () => error = 'Kriterleri kontrol edin: yaş 16–80, tarih YYYY-AA-GG, KPSS türü P3/P93/P94 gibi, puan 0–100 ve yıl 2000–2100 olmalı. Puan için tür seçin.',
                    );
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Dialog route çıkış animasyonu bitmeden TextField controller'ını dispose etme.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final controller in [
        name,
        age,
        ageDate,
        type,
        score,
        year,
        keyword,
      ]) {
        controller.dispose();
      }
    }
  }

  /// Kayıtlı aramayı yeniden adlandırır; vazgeçilirse null döner.
  Future<String?> _promptRename(SavedSearch search) {
    final controller = TextEditingController(text: search.name);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aramayı yeniden adlandır'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Arama adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  /// Kayıtlı aramayı silmek için onay ister (C-021: kullanıcı verisi
  /// her zaman silinebilir).
  Future<bool?> _confirmDeleteSearch(SavedSearch search) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Arama silinsin mi?'),
      content: Text(
        '"${search.name}" ve bildirim tercihi bu cihazdan silinir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );

  String _modeLabel(SearchAlertMode mode) => switch (mode) {
    SearchAlertMode.instant => 'Anlık',
    SearchAlertMode.digest => 'Günlük özet',
    SearchAlertMode.off => 'Kapalı',
  };

  String _filterSummary(SavedSearch search) {
    if (search.hasInvalidCriteria) {
      return 'Kriterler okunamadı • Düzenle ile onarın';
    }
    final parts = <String>[];
    final criteria = search.effectiveCriteria.values;
    final q = criteria['keyword'] as String?;
    if (q != null && q.isNotEmpty) parts.add('"$q"');
    for (final key in [
      'categories',
      'cities',
      'occupations',
      'institutions',
      'education',
    ]) {
      final selected = criteria[key] as List?;
      if (selected != null && selected.isNotEmpty) {
        parts.add(
          selected
              .cast<String>()
              .map(
                (value) => key == 'education'
                    ? educationLabel(value)
                    : key == 'cities'
                    ? cityLabel(value)
                    : value,
              )
              .join(', '),
        );
      }
    }
    if (criteria['last30'] == true) parts.add('son 30 gün');
    final yas = criteria['age'];
    if (yas != null) {
      parts.add('yaş $yas (${criteria['ageAsOf']})');
    }
    final kpss = criteria['kpssType'] as String?;
    if (kpss != null && kpss.isNotEmpty) parts.add('KPSS $kpss');
    final score = criteria['kpssScore'];
    final year = criteria['kpssYear'];
    if (score != null) parts.add('$score puan');
    if (year != null) parts.add('$year sınavı');
    return parts.isEmpty ? 'Süzgeç yok' : parts.join(' • ');
  }
}
