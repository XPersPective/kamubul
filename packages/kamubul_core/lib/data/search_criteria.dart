import 'turkish_cities.dart';
import '../time/wall_clock.dart';

enum CriteriaMatch { match, noMatch, unknown }

/// V2 sözleşmesi: kayıtlı aramanın adı filtre değildir; alternatif kadrolar ayrıdır.
class SearchCriteria {
  SearchCriteria._(this.values);
  final Map<String, Object?> values;

  static SearchCriteria fromLegacy(Map<String, String> filters) {
    final result = <String, Object?>{'version': 2, 'keywordScope': 'title'};
    for (final pair in [('q', 'keyword'), ('kpss', 'kpssType')]) {
      if ((filters[pair.$1] ?? '').isNotEmpty) {
        result[pair.$2] = filters[pair.$1];
      }
    }
    for (final pair in [('sehir', 'cities'), ('egitim', 'education')]) {
      if ((filters[pair.$1] ?? '').isNotEmpty) {
        result[pair.$2] = [filters[pair.$1]!];
      }
    }
    if ((filters['yas'] ?? '').isNotEmpty) {
      result['age'] = num.parse(filters['yas']!);
      result['ageAsOf'] = filters['yasTarih'] ?? '1970-01-01';
    }
    if ((filters['kpssPuan'] ?? '').isNotEmpty) {
      result['kpssScore'] = num.parse(filters['kpssPuan']!);
    }
    final category = filters['kategori'];
    if (category != null && category.isNotEmpty && category != '0') {
      final label = {'1': 'işçi', '2': 'personel', '3': 'belediye'}[category];
      if (label == null) throw const FormatException('kategori');
      result['categories'] = [label];
    }
    if (filters['son30'] == '1') result['last30'] = true;
    return parse(result);
  }

  static SearchCriteria parse(Map<String, Object?> raw) {
    const arrays = [
      'cities',
      'categories',
      'occupations',
      'institutions',
      'education',
    ];
    const strings = ['keyword', 'ageAsOf', 'kpssType', 'keywordScope'];
    const numbers = {
      'age': [16, 80],
      'kpssScore': [0, 100],
      'kpssYear': [2000, 2100],
    };
    final allowed = {
      'version',
      ...arrays,
      ...strings,
      ...numbers.keys,
      'onlyKpss',
      'last30',
    };
    if (raw.keys.any((k) => !allowed.contains(k)) ||
        (raw.containsKey('version') && raw['version'] != 2)) {
      throw const FormatException('criteria version/field');
    }
    final result = <String, Object?>{'version': 2};
    for (final key in arrays) {
      if (!raw.containsKey(key)) continue;
      final value = raw[key];
      if (value is! List ||
          value.length > 10 ||
          value.any(
            (v) => v is! String || v.trim().isEmpty || v.length > 100,
          )) {
        throw FormatException(key);
      }
      result[key] = List<String>.unmodifiable(
        value.cast<String>().map((s) => s.trim()).toSet(),
      );
    }
    for (final key in strings) {
      if (!raw.containsKey(key)) continue;
      final value = raw[key];
      if (value is! String || value.length > 100) throw FormatException(key);
      result[key] = value;
    }
    for (final entry in numbers.entries) {
      if (!raw.containsKey(entry.key)) continue;
      final value = raw[entry.key];
      if (value is! num ||
          !value.isFinite ||
          value < entry.value[0] ||
          value > entry.value[1] ||
          (entry.key != 'kpssScore' && value != value.roundToDouble())) {
        throw FormatException(entry.key);
      }
      result[entry.key] = value;
    }
    final date = result['ageAsOf'] as String?;
    if (result['age'] != null && date == null) {
      throw const FormatException('ageAsOf');
    }
    if (date != null) {
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date) {
        throw const FormatException('ageAsOf');
      }
    }
    final type = result['kpssType'] as String?;
    if (type != null &&
        type.isNotEmpty &&
        !RegExp(r'^P\d{1,3}$').hasMatch(type)) {
      throw const FormatException('kpssType');
    }
    if (result['kpssScore'] != null && (type == null || type.isEmpty)) {
      throw const FormatException('kpssType');
    }
    if (result['keywordScope'] != null &&
        result['keywordScope'] != '' &&
        !['title', 'full'].contains(result['keywordScope'])) {
      throw const FormatException('keywordScope');
    }
    for (final key in ['onlyKpss', 'last30']) {
      if (!raw.containsKey(key)) continue;
      if (raw[key] is! bool) throw FormatException(key);
      result[key] = raw[key];
    }
    return SearchCriteria._(Map.unmodifiable(result));
  }

  CriteriaMatch match(
    Map<String, Object?> listing, {
    required DateTime now,
    bool forSaved = false,
  }) {
    final c = values;
    final deadline = DateTime.tryParse('${listing['deadline'] ?? ''}');
    final published = DateTime.tryParse('${listing['publishedAt'] ?? ''}');
    if (!forSaved &&
        (listing['active'] == false ||
            (deadline != null && deadline.isBefore(now)) ||
            (published != null && published.isAfter(now)))) {
      return CriteriaMatch.noMatch;
    }
    final words = c['keywordScope'] == 'title'
        ? listing['title']
        : [
            listing['title'],
            listing['institution'],
            ..._list(listing['occupations']),
          ].join(' ');
    if ('${c['keyword'] ?? ''}'.isNotEmpty &&
        !_fold(words).contains(_fold(c['keyword']))) {
      return CriteriaMatch.noMatch;
    }
    final categories = _list(c['categories']);
    if (categories.isNotEmpty &&
        !categories.any(
          (x) =>
              _fold('${listing['category'] ?? ''} ${listing['title'] ?? ''}')
                  .contains(_fold(x)),
        )) {
      return CriteriaMatch.noMatch;
    }
    if (!_oneOf(_list(c['institutions']), [listing['institution'] ?? ''])) {
      return CriteriaMatch.noMatch;
    }
    if (c['last30'] == true &&
        (published == null ||
            now.difference(published).inMilliseconds > 30 * 86400000)) {
      return CriteriaMatch.noMatch;
    }
    final supplied = _list(listing['requirementGroups']);
    final groups = supplied.isEmpty
        ? [
            {
              'cities': listing['places'],
              'occupations': listing['occupations'],
            },
          ]
        : supplied;
    var unknown = false;
    for (final raw in groups) {
      if (raw is! Map) {
        unknown = true;
        continue;
      }
      var status = CriteriaMatch.match;
      void uncertain() {
        if (status != CriteriaMatch.noMatch) status = CriteriaMatch.unknown;
      }

      for (final key in ['cities', 'occupations', 'education']) {
        final wanted = _list(c[key]);
        if (wanted.isEmpty) continue;
        final actual = key == 'cities' && _list(raw[key]).isEmpty
            ? (groups.length == 1 ? _list(listing['places']) : <Object?>[])
            : _list(raw[key]);
        if (actual.isEmpty) {
          uncertain();
        } else if ((key == 'education' || key == 'cities') &&
            !wanted.any(
              (w) =>
                  _knownCriterion(key, w) &&
                  actual.any(
                    (a) =>
                        _knownCriterion(key, a) &&
                        _criterionKey(key, a) == _criterionKey(key, w),
                  ),
            )) {
          if (wanted.any((w) => !_knownCriterion(key, w)) ||
              actual.any((a) => !_knownCriterion(key, a))) {
            uncertain();
          } else {
            status = CriteriaMatch.noMatch;
          }
        } else if (!_oneOf(wanted, actual, field: key)) {
          status = CriteriaMatch.noMatch;
        }
      }
      final age = c['age'] as num?;
      if (age != null) {
        final result = _matchAge(raw, c, now);
        if (result == CriteriaMatch.noMatch) {
          status = result;
        } else if (result == CriteriaMatch.unknown) {
          uncertain();
        }
      }
      if ('${c['kpssType'] ?? ''}'.isNotEmpty || c['onlyKpss'] == true) {
        final type = raw['kpssType'],
            score = raw['kpssScore'],
            year = raw['kpssYear'];
        final invalid =
            (raw['kpssStatus'] == 'not_required' &&
                [type, score, year].any((v) => v != null)) ||
            (type != null &&
                (type is! String || !RegExp(r'^P\d{1,3}$').hasMatch(type))) ||
            (score != null &&
                (score is! num ||
                    !score.isFinite ||
                    score < 0 ||
                    score > 100)) ||
            (year != null && (year is! int || year < 2000 || year > 2100));
        if (invalid) {
          uncertain();
        } else {
          if (raw['kpssStatus'] == 'not_required') {
            if (c['onlyKpss'] == true) status = CriteriaMatch.noMatch;
          } else if (raw['kpssStatus'] != 'required') {
            uncertain();
          } else if ('${c['kpssType'] ?? ''}'.isNotEmpty &&
              raw['kpssType'] == null) {
            uncertain();
          } else if ('${c['kpssType'] ?? ''}'.isNotEmpty &&
              raw['kpssType'] != c['kpssType']) {
            status = CriteriaMatch.noMatch;
          } else if (c['kpssScore'] != null) {
            if (raw['kpssScore'] is! num) {
              uncertain();
            } else if ((c['kpssScore'] as num) < (raw['kpssScore'] as num)) {
              status = CriteriaMatch.noMatch;
            }
          }
          if (raw['kpssYear'] != null) {
            if (c['kpssYear'] == null) {
              uncertain();
            } else if (raw['kpssYear'] != c['kpssYear']) {
              status = CriteriaMatch.noMatch;
            }
          }
        }
      }
      if (status == CriteriaMatch.match) return status;
      if (status == CriteriaMatch.unknown) unknown = true;
    }
    return unknown ? CriteriaMatch.unknown : CriteriaMatch.noMatch;
  }
}

CriteriaMatch _matchAge(
  Map group,
  Map<String, Object?> criteria,
  DateTime now,
) {
  DateTime? date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    return parsed != null && parsed.toIso8601String().substring(0, 10) == value
        ? parsed
        : null;
  }

  final asOf = date(criteria['ageAsOf']);
  // Same Istanbul pilot calendar as Worker; ageAsOf is a civil date.
  final local = now.toUtc().add(
    const Duration(minutes: kTurkeyUtcOffsetMinutes),
  );
  final today = DateTime.utc(local.year, local.month, local.day);
  if (asOf == null ||
      today.difference(asOf).inMilliseconds > 366 * 86400000 ||
      asOf.isAfter(today)) {
    return CriteriaMatch.unknown;
  }
  const fields = [
    'minAge',
    'maxAge',
    'ageReferenceDate',
    'bornOnOrAfter',
    'bornOnOrBefore',
  ];
  if (group['ageStatus'] == 'no_restriction') {
    return fields.any((k) => group[k] != null)
        ? CriteriaMatch.unknown
        : CriteriaMatch.match;
  }
  if (group['ageStatus'] != 'known' ||
      ![
        'minAge',
        'maxAge',
        'bornOnOrAfter',
        'bornOnOrBefore',
      ].any((k) => group[k] != null)) {
    return CriteriaMatch.unknown;
  }
  if (group['ageCalculation'] != null &&
      group['ageCalculation'] != 'completed_years') {
    return CriteriaMatch.unknown;
  }
  for (final k in ['minAge', 'maxAge']) {
    final value = group[k];
    if (value != null &&
        (value is! num ||
            !value.isFinite ||
            value != value.truncate() ||
            value < 0 ||
            value > 130)) {
      return CriteriaMatch.unknown;
    }
  }
  final reference = group['ageReferenceDate'] == null
      ? asOf
      : date(group['ageReferenceDate']);
  final lower = date(group['bornOnOrAfter']),
      upper = date(group['bornOnOrBefore']);
  if (reference == null ||
      (group['bornOnOrAfter'] != null && lower == null) ||
      (group['bornOnOrBefore'] != null && upper == null)) {
    return CriteriaMatch.unknown;
  }
  // Same inverse completed-year boundaries as the Worker; Feb29 rolls to March1.
  int yearsBack(DateTime day, int years) {
    final year = day.year - years,
        lastDay = DateTime.utc(year, day.month + 1, 0).day;
    return DateTime.utc(
      year,
      day.month,
      day.day > lastDay ? lastDay : day.day,
    ).millisecondsSinceEpoch;
  }

  final age = (criteria['age'] as num).toInt();
  final first = yearsBack(asOf, age + 1) + 86400000,
      last = yearsBack(asOf, age);
  num allowedFirst = lower?.millisecondsSinceEpoch ?? double.negativeInfinity;
  num allowedLast = upper?.millisecondsSinceEpoch ?? double.infinity;
  if (group['maxAge'] != null) {
    final bound =
        yearsBack(reference, (group['maxAge'] as num).toInt() + 1) + 86400000;
    if (bound > allowedFirst) allowedFirst = bound;
  }
  if (group['minAge'] != null) {
    final bound = yearsBack(reference, (group['minAge'] as num).toInt());
    if (bound < allowedLast) allowedLast = bound;
  }
  if (allowedFirst > allowedLast) return CriteriaMatch.unknown;
  if (last < allowedFirst || first > allowedLast) return CriteriaMatch.noMatch;
  return first >= allowedFirst && last <= allowedLast
      ? CriteriaMatch.match
      : CriteriaMatch.unknown;
}

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];
String _fold(Object? value) =>
    foldTurkish('${value ?? ''}')
        .replaceAll('Â', 'A')
        .replaceAll('Î', 'I')
        .replaceAll('Û', 'U')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
const _educationAliases = {
  'ILKOKUL': 'primary',
  'EDUCATION:PRIMARY': 'primary',
  'ORTAOKUL': 'middle',
  'ILKOGRETIM': 'middle',
  'EDUCATION:MIDDLE': 'middle',
  'LISE': 'secondary',
  'EDUCATION:SECONDARY': 'secondary',
  'ON LISANS': 'associate',
  'ONLISANS': 'associate',
  'EDUCATION:ASSOCIATE': 'associate',
  'LISANS': 'bachelor',
  'EDUCATION:BACHELOR': 'bachelor',
  'YUKSEK LISANS': 'master',
  'YUKSEKLISANS': 'master',
  'EDUCATION:MASTER': 'master',
  'DOKTORA': 'doctorate',
  'EDUCATION:DOCTORATE': 'doctorate',
};
String _criterionKey(String? field, Object? value) {
  final key = _fold(value);
  if (field == 'cities') return _fold(canonicalCity('$value') ?? value);
  return field == 'education' ? _educationAliases[key] ?? key : key;
}

bool _knownCriterion(String field, Object? value) => field == 'cities'
    ? canonicalCity('$value') != null
    : _educationAliases.containsKey(_fold(value));

String educationLabel(String value) =>
    const {
      'primary': 'İlkokul',
      'middle': 'Ortaokul',
      'secondary': 'Lise',
      'associate': 'Ön lisans',
      'bachelor': 'Lisans',
      'master': 'Yüksek lisans',
      'doctorate': 'Doktora',
    }[_educationAliases[_fold(value)]] ??
    value;

bool _oneOf(List<Object?> wanted, List<Object?> actual, {String? field}) =>
    wanted.isEmpty ||
    wanted.any(
      (w) =>
          actual.any((a) => _criterionKey(field, a) == _criterionKey(field, w)),
    );
