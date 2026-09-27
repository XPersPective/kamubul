/// İlan metninden şart alanlarının deterministik çıkarımı (PB-007).
///
/// Kural: bir alan yalnızca kaynak metindeki bir cümlenin İÇİNDE desene
/// eşleşip doğrulamadan geçerse üretilir; o cümle alanın alıntı kanıtıdır.
/// Değeri çıkarılamayan cümle kanıt sayılmaz ve tarama devam eder.
class ExtractedField<T extends Object> {
  const ExtractedField(this.value, this.quote);

  final T value;
  final String quote;
}

class ConditionFields {
  const ConditionFields({
    this.kpssType,
    this.kpssScore,
    this.maxAge,
    this.education,
    this.quotaType,
  });

  final ExtractedField<String>? kpssType;
  final ExtractedField<int>? kpssScore;
  final ExtractedField<int>? maxAge;
  final ExtractedField<String>? education;
  final ExtractedField<String>? quotaType;
}

const _egitimDuzeyleri = ['lise', 'önlisans', 'lisans', 'yükseklisans', 'doktora'];

final _sentenceSplit = RegExp(r'(?<=[.;:])\s+|\n+');

ExtractedField<T>? _scan<T extends Object>(
  String text,
  RegExp finder,
  T? Function(String sentence) parse,
) {
  for (final sentence in text.split(_sentenceSplit)) {
    final candidate = sentence.trim();
    if (candidate.isEmpty || !finder.hasMatch(candidate)) continue;
    final value = parse(candidate);
    if (value != null) return ExtractedField<T>(value, candidate);
  }
  return null;
}

/// KPSS puan türü (P3, P93...), taban puan, yaş sınırı, eğitim düzeyi ve
/// kota tipini çıkarır. Alıntısı bulunamayan alan "belirtilmemiş" kalır.
ConditionFields extractConditions(String text) {
  final kpssType = _scan<String>(
    text,
    RegExp(r'KPSS\s*\(?\s*P\s*(\d{1,2})(?!\d)', caseSensitive: false),
    (sentence) {
      final match = RegExp(
        r'KPSS\s*\(?\s*P\s*(\d{1,2})(?!\d)',
        caseSensitive: false,
      ).firstMatch(sentence);
      final index = int.parse(match!.group(1)!);
      // Gerçek KPSS puan türleri tek/çift haneli kodlardır (P3, P93...);
      // eşik geniştir çünkü kanıt cümlesi her durumda gösterilir.
      return index >= 1 && index <= 99 ? 'P$index' : null;
    },
  );

  final kpssScore = _scan<int>(
    text,
    // Yalnızca KPSS içeren cümleler: sınav oturumu eşikleri yanlış etiketlenmez.
    RegExp(r'KPSS', caseSensitive: false),
    (sentence) {
      final match = RegExp(
        r'(?:en az|en düşük)\s*(\d{2,3})\s*(?:\([^)]+\)\s*)?(?:ve\s+üzeri\s+)?puan'
        r'|\b(\d{2,3})\s*(?:\([^)]+\)\s*)?ve\s+üzeri\s+puan',
        caseSensitive: false,
      ).firstMatch(sentence);
      if (match == null) return null;
      final raw = match.group(1) ?? match.group(2);
      if (raw == null) return null;
      final score = int.parse(raw);
      return score >= 30 && score <= 100 ? score : null;
    },
  );

  final maxAge = _scan<int>(
    text,
    RegExp(
      r'yaş[ıi]n[ıi]\s*doldurmamış|yaşından\s*gün\s*almamış|yaş[ıi]ndan\s*b[üu]y[üu]k',
      caseSensitive: false,
    ),
    (sentence) {
      final match = RegExp(r'(\d{2})\s*yaş', caseSensitive: false)
          .firstMatch(sentence);
      if (match == null) return null;
      final age = int.parse(match.group(1)!);
      return age >= 18 && age <= 65 ? age : null;
    },
  );

  final education = _scan<String>(
    text,
    RegExp(
      r'(?:en az|minimum)\s*(lise|ön\s?lisans|lisans|yüksek\s?lisans|doktora)|'
      r'(lise|ön\s?lisans|lisans|yüksek\s?lisans|doktora)[^.]{0,40}?(?:mezun|düzeyinde)',
      caseSensitive: false,
    ),
    (sentence) {
      final match = RegExp(
        r'(lise|ön\s?lisans|lisans|yüksek\s?lisans|doktora)',
        caseSensitive: false,
      ).firstMatch(sentence);
      if (match == null) return null;
      final raw = match.group(1)!.toLowerCase().replaceAll(' ', '');
      if (!_egitimDuzeyleri.contains(raw)) return null;
      return <String, String>{
        'lise': 'Lise',
        'önlisans': 'Ön lisans',
        'lisans': 'Lisans',
        'yükseklisans': 'Yüksek lisans',
        'doktora': 'Doktora',
      }[raw];
    },
  );

  final quotaType = _scan<String>(
    text,
    RegExp(
      r'4\s*/\s*B|375\s*/\s*B|sözleşmeli|kadro|işçi|engelli|eski hükümlü',
      caseSensitive: false,
    ),
    (sentence) {
      final lower = sentence.toLowerCase();
      if (RegExp(r'4\s*/\s*b').hasMatch(lower)) return '4/B';
      if (RegExp(r'375\s*/\s*b').hasMatch(lower)) return '375/B';
      if (lower.contains('eski hükümlü')) return 'Eski hükümlü';
      if (lower.contains('engelli')) return 'Engelli';
      if (lower.contains('sözleşmeli')) return 'Sözleşmeli';
      if (lower.contains('işçi')) return 'İşçi';
      if (lower.contains('kadro')) return 'Kadro';
      return null;
    },
  );

  return ConditionFields(
    kpssType: kpssType,
    kpssScore: kpssScore,
    maxAge: maxAge,
    education: education,
    quotaType: quotaType,
  );
}
