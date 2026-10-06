import 'package:kamubul_core/kamubul_core.dart' show cityLabel, educationLabel;

import '../data/listing_store.dart';

/// Kart, özet ve ayrıntının ortak okuduğu sunucu ilan bilgileri. Hepsi saklı
/// sunucu kaydından türetilir; model çağrısı ya da ağ isteği yapılmaz.
extension ListingFacts on ListingRecord {
  Map<String, Object?> get _data => criteriaListing ?? const {};

  Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : const <Object?, Object?>{};

  Map<Object?, Object?> _evidence(String key) =>
      _map(_map(_data['fieldEvidence'])[key]);

  /// vacancy, register (tercüman/bilirkişi listesi), amendment (düzeltme),
  /// cancellation ya da exam.
  String get noticeKind {
    final kind = _map(_data['extraction'])['kind'];
    return kind is String ? kind : 'vacancy';
  }

  String? get institution {
    final value = _data['institution'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// "Resmî Gazete'de yayımından itibaren 15 gün" kuralından hesaplanan son gün.
  DateTime? get deadlineEstimate {
    final value = _data['deadlineEstimate'];
    return value is String ? DateTime.tryParse(value) : null;
  }

  /// Tahmini son günün dayandığı ilan cümlesi.
  String? get deadlineRule {
    final quote = _evidence('deadlineEstimate')['quote'];
    return quote is String && quote.trim().isNotEmpty ? quote.trim() : null;
  }

  /// Pozisyona göre değişen başvuru takvimleri (tek bir son tarih yok).
  List<Map<Object?, Object?>> get applicationPeriods {
    final raw = _data['applicationPeriods'];
    return [
      for (final period in raw is List ? raw : const [])
        if (period is Map &&
            period['text'] is String &&
            (period['text'] as String).trim().isNotEmpty)
          period,
    ];
  }

  List<Map<Object?, Object?>> get positions {
    final raw = _data['requirementGroups'];
    return [
      for (final group in raw is List ? raw : const [])
        if (group is Map) group,
    ];
  }

  /// Aynı ilan ilan.gov.tr'de bulunduğunda metnin alındığı kayıt.
  ({String id, String url, String title})? get twin {
    final twin = _map(_data['twin']);
    final id = twin['id'], url = twin['url'], title = twin['title'];
    return id is String && url is String && title is String
        ? (id: id, url: url, title: title)
        : null;
  }

  /// Kontenjan ya da tarih yapay zekâ tarafından mı ayıklandı?
  bool fieldFromAi(String key) => _evidence(key)['origin'] == 'ai';

  /// İlanın herhangi bir bilgisi yapay zekâ katkısıyla mı ayıklandı?
  bool get aiExtracted {
    final method = _map(_data['extraction'])['method'];
    return method == 'ai' || method == 'hybrid';
  }

  /// Kaynak metni hiç alınamamış Kariyer Kapısı ilanı.
  bool get detailOnSource => sourceId == 'kariyerkapisi' && noticeText.isEmpty;

  /// Bütün pozisyonlarda bilinen değerler: özet kartının satırları.
  List<String> get educationLevels => _union(
    (group) => [
      for (final value
          in group['education'] is List ? group['education'] as List : const [])
        if (value is String) educationLabel(value),
    ],
  );

  List<String> get cityNames => _union(
    (group) => [
      for (final value
          in group['cities'] is List ? group['cities'] as List : const [])
        if (value is String && value.trim().isNotEmpty) cityLabel(value),
    ],
    fallback: places,
  );

  /// "KPSS P3 en az 70", "KPSS şartı yok" ya da karma durumlar.
  /// Özet satırı "KPSS" etiketinin yanında: "P3, en az 70 puan", "Aranmıyor".
  List<String> get kpssSummaries => _union((group) {
    final label = kpssLabel(group);
    if (label == null) return const [];
    if (label == 'KPSS şartı yok') return const ['Aranmıyor'];
    final type = kpssTypeText(group), score = group['kpssScore'];
    final parts = [
      ?type,
      if (score is num && score > 0 && score <= 100)
        'en az ${score % 1 == 0 ? score.toInt() : score} puan',
    ];
    return [parts.isEmpty ? 'Gerekli' : parts.join(', ')];
  });

  List<String> get ageSummaries => _union((group) {
    final label = ageLabel(group);
    return label == null ? const [] : [label];
  });

  List<String> _union(
    List<String> Function(Map<Object?, Object?>) read, {
    List<String> fallback = const [],
  }) {
    final seen = <String>{};
    for (final group in positions) {
      seen.addAll(read(group));
    }
    if (seen.isEmpty) seen.addAll(fallback);
    return seen.toList();
  }
}

/// "P3" ya da alternatif türler için "P3/P44/P45" (kpssTypes); geçersizse null.
String? kpssTypeText(Map<Object?, Object?> group) {
  bool valid(Object? t) => t is String && RegExp(r'^P\d{1,3}$').hasMatch(t);
  final alternatives = group['kpssTypes'], type = group['kpssType'];
  if (alternatives is List && alternatives.isNotEmpty) {
    return alternatives.every(valid) ? alternatives.join('/') : null;
  }
  return valid(type) ? type as String : null;
}

/// Bir pozisyonun KPSS şartı; bilinmiyorsa null. Çelişkili kayıtta
/// ("şart yok" ama puan dolu) yokluk iddia edilmez.
String? kpssLabel(Map<Object?, Object?> group) {
  final type = group['kpssType'], score = group['kpssScore'];
  switch (group['kpssStatus']) {
    case 'not_required'
        when type == null && score == null && group['kpssYear'] == null:
      return 'KPSS şartı yok';
    case 'required':
      final types = kpssTypeText(group);
      final parts = [
        'KPSS',
        ?types,
        if (score is num && score > 0 && score <= 100)
          'en az ${score % 1 == 0 ? score.toInt() : score}',
      ];
      return parts.join(' ');
  }
  return null;
}

/// Bir pozisyonun yaş sınırı; bilinmiyorsa null. Referans/doğum tarihi
/// varsa etikette korunur (yaş bugüne göre değil o tarihe göre hesaplanır).
String? ageLabel(Map<Object?, Object?> group) {
  const dated = ['ageReferenceDate', 'bornOnOrAfter', 'bornOnOrBefore'];
  final min = group['minAge'], max = group['maxAge'];
  if (group['ageStatus'] == 'no_restriction') {
    return ['minAge', 'maxAge', ...dated].every((key) => group[key] == null)
        ? 'Yaş sınırı yok'
        : null;
  }
  if (group['ageStatus'] != 'known') return null;
  final limit = min is int && max is int
      ? '$min–$max yaş'
      : max is int
      ? 'En fazla $max yaş'
      : min is int
      ? 'En az $min yaş'
      : null;
  String? date(String key) {
    final value = group[key];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return parsed == null
        ? null
        : '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}';
  }

  final notes = [
    if (date('ageReferenceDate') case final String d) '$d itibarıyla',
    if (date('bornOnOrAfter') case final String d) '$d ve sonrası doğumlu',
    if (date('bornOnOrBefore') case final String d) '$d ve öncesi doğumlu',
  ];
  if (limit == null) return notes.isEmpty ? null : notes.join(', ');
  return notes.isEmpty ? limit : '$limit (${notes.join(', ')})';
}

/// Büyük harfli resmî adları okunur başlık biçimine çevirir:
/// "KIRŞEHİR AHİ EVRAN ÜNİVERSİTESİ" → "Kırşehir Ahi Evran Üniversitesi".
String turkishTitleCase(String value) {
  if (value != value.toUpperCase()) return value;
  const lower = {'VE', 'İLE', 'İÇİN', 'DE', 'DA'};
  return value
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) return word;
        if (lower.contains(word)) return _turkishLower(word);
        if (word.length <= 4 && !RegExp(r'[AEIİOÖUÜ]').hasMatch(word)) {
          return word; // Kısaltmalar (TBMM, SGK) aynen kalır.
        }
        return word[0] + _turkishLower(word.substring(1));
      })
      .join(' ');
}

String _turkishLower(String value) =>
    value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
