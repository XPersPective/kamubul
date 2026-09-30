/// Kaynaklar-arası ilan tekilleştirmesi için içerik parmak izi (PB-004).
///
/// Aynı ilan Kariyer Kapısı ve SBB'de farklı URL/başlıkla görünür. Parmak izi
/// = normalize edilmiş kurum adı + son başvuru günü. Yanlış birleştirme,
/// kopyadan daha zararlı olduğu için kurallar katıdır: kurum öneki eşleşmez
/// veya tarihler farklıysa parmak izleri eşleşmez.
String listingFingerprint({
  required String title,
  required String sourceId,
  DateTime? deadline,
}) {
  String kurum;
  if (sourceId == 'kariyerkapisi') {
    // Kariyer başlığı "KURUM - İlan başlığı" biçimindedir; kurum öneki alınır.
    kurum = title.split(' - ').first;
  } else {
    kurum = title;
  }
  final day = deadline == null
      ? '-'
      : '${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-'
            '${deadline.day.toString().padLeft(2, '0')}';
  return '${_normalizeKurum(kurum)}|$day';
}

const _suffixTokens = {
  'rektorlugu',
  'baskanligi',
  'mudurlugu',
  'genel',
  'mudurlugune',
  'rektorlugune',
  'baskanligina',
};

String _normalizeKurum(String value) {
  final folded = value
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
  final tokens = folded
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty && !_suffixTokens.contains(token))
      .toList();
  return tokens.join(' ');
}

/// Sunucu birleştirmesi için ÇAPRAZ KAYNAK anahtarı: yalnızca kurum adı +
/// son başvuru günü. [listingFingerprint]'ten farkı: SBB başlığı
/// `Kurum — İlan` biçiminde olduğundan kurum kısmı ayrıştırılır. Yalnızca
/// FARKLI kaynaklar arasında kopya sayılır; aynı kaynaktaki iki ilan
/// (aynı kurum ve son gün) ayrı kalır.
String crossSourceKey({
  required String title,
  required String sourceId,
  DateTime? deadline,
}) {
  final separator = sourceId == 'kariyerkapisi' ? ' - ' : ' — ';
  final kurum = title.split(separator).first;
  final day = deadline == null
      ? '-'
      : '${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-'
            '${deadline.day.toString().padLeft(2, '0')}';
  return '${_normalizeKurum(kurum)}|$day';
}
