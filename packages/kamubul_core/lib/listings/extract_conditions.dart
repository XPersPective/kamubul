/// İlan metninden şart alanlarının deterministik çıkarımı (PB-007).
///
/// Sözleşme: bir alan yalnızca metnin tamamında TEK bir ayrık değer varsa
/// üretilir; birden çok farklı değer (farklı pozisyonların farklı şartları)
/// ya da destekleyen cümlesi olmayan değer üretilmez — arayüz "belirtilmemiş"
/// gösterir ve ham metne düşer. Her değer, metinde birebir bulunan bir
/// cümlenin alıntı kanıtıyla gelir. Tuzak cümleler (belge yükleme talimatı,
/// tercih/not ortalaması, ücret tavanı, fesih, liste imleri, adres blokları)
/// değer üretmez.
library;

/// Alıntılı çıkarılan alan değeri.
class ExtractedField<T extends Object> {
  const ExtractedField(this.value, this.quote);

  final T value;
  final String quote;
}

/// Çıkarılan şart alanları; değeri olmayan alan "belirtilmemiş"tir.
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

// "Kanunun 4. maddesinin" gibi nokta kısaltmalarında bölme; aksi halde
// şart cümleleri kanıt olarak kullanılamayacak parçalara ayrılıyor.
final _sentenceSplit = RegExp(r'(?<=[.;:])\s+(?!madde[a-zçğıöşü0-9_]*)|\n+');

const _foldMap = <String, String>{
  'İ': 'i',
  'I': 'ı',
  'Ş': 'ş',
  'Ğ': 'ğ',
  'Ü': 'ü',
  'Ö': 'ö',
  'Ç': 'ç',
  '’': "'",
  '‘': "'",
  '“': '"',
  '”': '"',
};

/// Eşleştirme için Türkçe harf katlama + boşluk sıkıştırma.
String _fold(String value) {
  var folded = value;
  for (final entry in _foldMap.entries) {
    folded = folded.replaceAll(entry.key, entry.value);
  }
  return folded.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Katlanmış metinde Türkçe sözcük parçası kalıpları `[a-zçğıöşü0-9_]*`
/// ile yazılır (Dart \w yalnızca ASCII'dir).

// ------------------------------------------------------------- KPSS puan türü
final _kpssCtx = RegExp(r'kpss|kamu personeli se[çc]me|puan\s+t[üu]r');
final _codeA = RegExp(r"kpss[\s\-–]*\(?\s*[’'`]?p[\s\-–]*(\d{1,2})(?!\d)");
final _codeB = RegExp(r'(?<![a-zçğıöşü0-9])p[\s\-–]*(\d{1,2})(?!\d)');

Set<String> _codesIn(String folded) {
  if (!_kpssCtx.hasMatch(folded)) return const {};
  final out = <String>{};
  for (final pattern in [_codeA, _codeB]) {
    for (final match in pattern.allMatches(folded)) {
      final value = int.parse(match.group(1)!);
      if (value >= 1 && value <= 99) out.add('P$value');
    }
  }
  return out;
}

// ------------------------------------------------------------ KPSS taban puanı
final _scoreCtx = RegExp(
  r'en az|en d[üu][şs][üu]k|asgari|taban|ve\s+[üu]zeri|daha\s+y[üu]ks'
  r'|ve\s+y[üu]ks',
);
final _scoreTrap = RegExp(
  r'puan[a-zçğıöşü0-9_]*\s+olmayan|değerlendir[a-zçğıöşü0-9_]*|a[ğg][ıi]rl[ıi]k|yds'
  r'|yabanc[ıi] dil|aritmetik'
  r'|s[öo]zl[üu] s[ıi]nav[a-zçğıöşü0-9_]*\s+(?:puan|not)'
  r'|yaz[ıi]l[ıi] s[ıi]nav[a-zçğıöşü0-9_]*\s+(?:puan|not)'
  r'|m[üu]lakat[a-zçğıöşü0-9_]*\s+(?:puan|not)|ba[şs]ar[ıi]\s+(?:notu|puan)'
  r'|yeterlilik s[ıi]nav|j[üu]ri|not\s+ortalamas[a-zçğıöşü0-9_]*'
  r'|puan[a-zçğıöşü0-9_]*\s+[üu]zerinden|hesaplan',
);
final _pCodeMask = RegExp(r'(?<![a-zçğıöşü0-9])p[\s\-–]*\(?\s*\d{1,2}(?!\d)');
final _dateMask = RegExp(r'\d{2}[./-]\d{2}[./-]\d{2,4}');
final _ageMask = RegExp(
  r"\d{2}\s*(?:\([^)]{2,30}\))?\s*[’']?(?:ıncı|inci|uncu|üncü|nci|ncü)?\s*yaş",
);
final _number23 = RegExp(r'\b(\d{2,3})\b');

Set<int> _scoresIn(String folded) {
  if (!(_kpssCtx.hasMatch(folded) &&
      _scoreCtx.hasMatch(folded) &&
      !_scoreTrap.hasMatch(folded))) {
    return const {};
  }
  // P-kodu / tarih / yaş sayısı pencerede puan sanılmasın; pencere sayıları
  // ortadan kesmesin diye maske uzunluk korunarak yapılır.
  var masked = folded;
  for (final pattern in [_pCodeMask, _dateMask, _ageMask]) {
    masked = masked.replaceAllMapped(
      pattern,
      (match) => ' ' * match.group(0)!.length,
    );
  }
  final out = <int>{};
  for (final match in _scoreCtx.allMatches(masked)) {
    final start = match.start - 35 < 0 ? 0 : match.start - 35;
    final end = match.end + 45 > masked.length ? masked.length : match.end + 45;
    for (final number in _number23.allMatches(masked.substring(start, end))) {
      final value = int.parse(number.group(1)!);
      if (value >= 30 && value <= 100) out.add(value);
    }
  }
  return out;
}

// ------------------------------------------------------------------- yaş sınırı
final _ageUpper = RegExp(
  r'g[üu]n\s+almam|doldurmam|bitirmemi|tamamlamam|b[üu]y[üu]k\s+olmam'
  r'|ge[çc]mi[şs]|a[şs]mam',
);
final _ageMin = RegExp(r'tamamlam|doldurmu');
final _ageWord = RegExp(r'yaş');
final _ageNum = RegExp(
  r"(\d{2})\s*(?:\([^)]{2,30}\))?\s*[’']?(?:ıncı|inci|uncu|üncü|nci|ncü)?\s*$",
);

Set<int> _agesIn(String folded) {
  final out = <int>{};
  for (final match in _ageWord.allMatches(folded)) {
    final preStart = match.start - 24 < 0 ? 0 : match.start - 24;
    final num = _ageNum.firstMatch(folded.substring(preStart, match.start));
    if (num == null) continue;
    final postEnd = match.end + 30 > folded.length
        ? folded.length
        : match.end + 30;
    final post = folded.substring(match.end, postEnd);
    if (_ageUpper.hasMatch(post) && !_ageMin.hasMatch(post)) {
      final value = int.parse(num.group(1)!);
      if (value >= 18 && value <= 65) out.add(value);
    }
  }
  return out;
}

// ------------------------------------------------------------------ eğitim düzeyi
final _eduValueCtx = RegExp(
  r'mezun[a-zçğıöşü0-9_]*|d[üu]zeyinde|yıllık|öğrenim\s+dal[a-zçğıöşü0-9_]*'
  r'|öğrenim\s+program[a-zçğıöşü0-9_]*|öğrenim\s+b[öo]l[üu]m[a-zçğıöşü0-9_]*'
  r'|öğrenim\s+[şs]art|öğrenim\s+d[üu]zey',
);
final _eduValueTrap = RegExp(
  r'tercih|e[şs]it[a-zçğıöşü0-9_]*|beraberlik|[öo]ncelik|puan\s+t[üu]r|kpss\s*\(?\s*b'
  r'|mezun[a-zçğıöşü0-9_]*\s+i[çc]in|mezunlar[a-zçğıöşü0-9_]*\s+aras[ıi]ndan'
  r'|kay[ıi]t|de[ğg]erlendir|s[ıi]nav|gönderil[a-zçğıöşü0-9_]*|yeti[şs]til[a-zçğıöşü0-9_]*'
  r'|ba[şs]vuru|deneyim|tecr[üu]be|hizmet\s+s[üu]re'
  r'|k[ıi]dem|ya[şs]|[üu]cret'
  r'|belge[a-zçğıöşü0-9_]*|yükle[a-zçğıöşü0-9_]*|pdf|format|mezuniyet\s+not'
  r'|not\s+ortalamas[a-zçğıöşü0-9_]*|yoksa',
);
final _eduLevels = <(RegExp, String)>[
  (
    RegExp(r'y[üu]ksek\s?lisans|y[üu]kseklisans|lisans[üu]st[üu]'),
    'Yüksek lisans',
  ),
  (RegExp(r'doktora'), 'Doktora'),
  (
    RegExp(
      r'[öo]n\s?lisans|[öo]nlisans|meslek\s+y[üu]ksekokul[a-zçğıöşü0-9_]*'
      r'|iki\s+y[ıi]ll[ıi]k|2\s+y[ıi]ll[ıi]k',
    ),
    'Ön lisans',
  ),
  (
    RegExp(
      r'd[öo]rt\s+y[ıi]ll[ıi]k|4\s+y[ıi]ll[ıi]k'
      r'|4\s*\(\s*d[öo]rt\s*\)\s+y[ıi]ll[ıi]k|d[öo]rt\s*\(\s*4\s*\)\s+y[ıi]ll[ıi]k',
    ),
    'Lisans',
  ),
  (
    RegExp(
      r'orta[öo][ğg]retim|orta\s+[öo][ğg]retim|meslek\s+lise[a-zçğıöşü0-9_]*'
      r'|\blise[a-zçğıöşü0-9_]*',
    ),
    'Lise',
  ),
  (RegExp(r'\blisans[a-zçğıöşü0-9_]*|lisans\s+d[üu]zey'), 'Lisans'),
];

Set<String> _levels(String folded) {
  var masked = folded;
  final out = <String>{};
  for (final (pattern, value) in _eduLevels) {
    if (pattern.hasMatch(masked)) {
      out.add(value);
      masked = masked.replaceAll(pattern, ' # ');
    }
  }
  return out;
}

Set<String> _educationIn(String folded) {
  if (!_eduValueCtx.hasMatch(folded) || _eduValueTrap.hasMatch(folded)) {
    return const {};
  }
  return _levels(folded);
}

// --------------------------------------------------------------- kota / statü tipi
final _qExperienceTrap = RegExp(
  r'stat[üu]deki\s+hizmet|stat[üu]s[üu]ndeki\s+hizmet|hizmet\s+s[üu]releri'
  r'|olarak\s+(?:en\s+az\s+)?\d+\s+y[ıi]l'
  r'|en\s+az\s+\d+\s+y[ıi]l[^.]{0,30}(?:deneyim|tecr[üu]be|çal[ıi][şs])'
  r'|deneyim|tecr[üu]be|ge[çc]irmi[şs]\s+olmak|çal[ıi][şs]m[ıi][şs]\s+ol(?:mak|malar)'
  r'|g[öo]rev\s+yapm[ıi][şs]|[şs]artlar[ıi]n[ıi]\s+ta[şs][ıi]mak'
  r'|stat[üu]s[üu]nde\s+g[öo]rev\s+ya[pm][a-zçğıöşü0-9_]*|çal[ıi][şs]m[ıi]kta\s+iken'
  r'|istifaen|g[öo]revinden\s+ayr[ıi]'
  r'|[üu]cret[a-zçğıöşü0-9_]*\s+(?:tavan|[öo]den|miktar)|tavan|fazla\s+mesai'
  r'|ek\s+[öo]deme|hari[çc]\s+olmak'
  r'|kadro[a-zçğıöşü0-9_]*\s+ba[şs]vur|ba[şs]vurulan\s+(?:kadro|pozisyon|[üu]nvan)',
);
final _qKadroTrap = RegExp(
  r'ilan\s+edilen\s+kadro|kadro\s+say[ıi]s[ıi]n[ıi]\s+kar[şs][ıi]layacak'
  r'|kadro\s+veya\s+pozisyon|pozisyonlara\s+yerle[şs]'
  r'|[şs]ube|@|no\s*:|adres|posta|telefon|ileti[şs]im|http|mail|web\s+servis',
);
final _q4b = RegExp(
  r"(?<![0-9])4\s*[/’'`.\-]\s*b(?![a-zçğıöşü])"
  r"|(?<![0-9])4\s*[’'`\.]?\s*(?:[üu]n?c?[üu]?)?\s*maddes?[^0-9]{0,40}\(\s*b\s*\)"
  r"|ek\s*2[’'`\.]?\s*nc?i?\.?\s*maddes?[^0-9]{0,40}\(\s*b\s*\)",
);
final _q375 = RegExp(
  r"(?<![0-9])375\s*[/’'`.]\s*b(?![a-zçğıöşü])"
  r"|375\s+say[ıi]l[ıi][^.]{0,90}(?:ek\s*28|ge[çc]ici\s*4)"
  r"|ek\s*28[^.]{0,60}375\s+say[ıi]l[ıi]",
);
final _qSoz = RegExp(
  r's[öo]zle[şs]meli\s+(?:personel|bili[şs]im|stat[üu]de|stat[üu]s[üu]nde'
  r'|olarak|unvan|uzman|memur|m[üu]hendis|avukat|hem[şs]ire|tekniker'
  r'|teknisyen|psikolog|muhasebe)'
  r'|belirsiz\s+s[üu]reli\s+(?:i[şs]\s+)?(?:s[öo]zle[şs]me|akd)'
  r'|belirsiz\s+s[üu]reli\s+hizmet\s+akd',
);
final _qIsci = RegExp(
  r'i[şs][çc]i\s+al[ıi]n|i[şs][çc]i\s+stat[üu]s[üu]nde[şs]?\s+(?:istihdam|al[ıi]n)'
  r'|daimi\s+i[şs][çc]i|ge[çc]ici\s+i[şs][çc]i|s[üu]rekli\s+i[şs][çc]i'
  r'|i[şs][çc]i\s+(?:kadro|ilan|ba[şs]vuru|olarak\s+istihdam|olarak\s+al[ıi]n)'
  r'|olarak\s+istihdam\s+edilecek\s+i[şs][çc]i|i[şs][çc]i\s+al[ıi]nacakt[ıi]r',
);
final _qKadro = RegExp(r'kadro[a-zçğıöşü0-9_]*');
final _qKadroPos = RegExp(
  r'atan|atamak|atama|s[ıi]n[ıi]f|unvan|derece|adet|b[üu]lunan|memur'
  r'|istihdam\s+edilecek|giri[şs]\s+s[ıi]nav',
);
final _qHuk = RegExp(r'eski\s+h[üu]k[üu]ml[üu]');
final _qEngTrap = RegExp(
  r'engelli\s+olmam|engelli\s+olmaya|bedensel\s+engelli|[öo]z[üu]r|rapor',
);
final _qEng = RegExp(r'engelli\s+(?:kadro|kontenjan|pozisyon|ilan)');

Set<String> _quotaTypesIn(String folded) {
  if (_qExperienceTrap.hasMatch(folded)) return const {};
  final out = <String>{};
  if (_q4b.hasMatch(folded)) out.add('4/B');
  if (_q375.hasMatch(folded)) out.add('375/B');
  if (_qIsci.hasMatch(folded)) out.add('İşçi');
  if (_qKadro.hasMatch(folded) &&
      _qKadroPos.hasMatch(folded) &&
      !_qKadroTrap.hasMatch(folded)) {
    out.add('Kadro');
  }
  if (_qHuk.hasMatch(folded)) out.add('Eski hükümlü');
  if (_qSoz.hasMatch(folded)) out.add('Sözleşmeli');
  if (_qEng.hasMatch(folded) && !_qEngTrap.hasMatch(folded)) out.add('Engelli');
  return out;
}

const _quotaPriority = [
  '4/B',
  '375/B',
  'İşçi',
  'Kadro',
  'Engelli',
  'Eski hükümlü',
  'Sözleşmeli',
];

const _eduOrder = ['Lise', 'Ön lisans', 'Lisans', 'Yüksek lisans', 'Doktora'];

/// Yalnızca bu kademeler 'veya' zinciriyle asgari düzeye katlanabilir.
const _eduGradTiers = {'Yüksek lisans', 'Doktora'};

// ------------------------------------------------------------------ yardımcılar
ExtractedField<T>? _single<T extends Object>(
  Map<T, List<String>> evidence, {
  List<String> pickKeywords = const [],
}) {
  if (evidence.length != 1) return null;
  final entry = evidence.entries.single;
  return ExtractedField<T>(entry.key, _pick(entry.value, pickKeywords));
}

/// En kısa destekleyici cümle; anahtar verilirse önce onu içerenler.
String _pick(List<String> sentences, [List<String> keywords = const []]) {
  var pool = sentences;
  if (keywords.isNotEmpty) {
    final keyed = [
      for (final sentence in sentences)
        if (keywords.every((k) => _fold(sentence).contains(k))) sentence,
    ];
    if (keyed.isNotEmpty) pool = keyed;
  }
  var best = pool.first;
  for (final sentence in pool.skip(1)) {
    if (sentence.length < best.length) best = sentence;
  }
  return best;
}

/// Tek düzey ya da 'veya' ile sunulan yalnızca LİSANSÜSTÜ alternatifi zincir
/// ise ASGARİ düzey ("mezun veya lisansüstü eğitim yapmış olmak" → Lisans).
/// Lise/Ön lisans gibi paralel pozisyon şartları birleştirilemez (null).
String? _educationEffective(Map<String, List<String>> evidence) {
  if (evidence.isEmpty) return null;
  if (evidence.length == 1) return evidence.keys.single;
  final tiers = evidence.keys.toList()
    ..sort((a, b) => _eduOrder.indexOf(a).compareTo(_eduOrder.indexOf(b)));
  for (final tier in tiers.skip(1)) {
    if (!_eduGradTiers.contains(tier)) return null;
    for (final sentence in evidence[tier]!) {
      if (!_fold(sentence).contains('veya')) return null;
    }
  }
  return tiers.first;
}

/// KPSS puan türü, taban puan, yaş sınırı, eğitim düzeyi ve kota tipini
/// çıkarır. Alıntısı bulunmayan ya da metinde çelişen alan "belirtilmemiş"
/// kalır.
ConditionFields extractConditions(String text) {
  final codes = <String, List<String>>{};
  final scores = <int, List<String>>{};
  final ages = <int, List<String>>{};
  final edus = <String, List<String>>{};
  final quotas = <String, List<String>>{};

  for (final raw in text.split(_sentenceSplit)) {
    final sentence = raw.trim();
    if (sentence.isEmpty) continue;
    final folded = _fold(sentence);
    for (final value in _codesIn(folded)) {
      codes.putIfAbsent(value, () => []).add(sentence);
    }
    for (final value in _scoresIn(folded)) {
      scores.putIfAbsent(value, () => []).add(sentence);
    }
    for (final value in _agesIn(folded)) {
      ages.putIfAbsent(value, () => []).add(sentence);
    }
    final eduTiers = _educationIn(folded);
    for (final value in eduTiers) {
      edus.putIfAbsent(value, () => []).add(sentence);
    }
    // Paralel pozisyon blokları ("KPSS (B) Ön Lisans ... asgari 70") da kademe
    // kanıtıdır; şart cümlesi farklı kademeleri gösteriyorsa değer üretilmez.
    if (eduTiers.isEmpty &&
        _kpssCtx.hasMatch(folded) &&
        _scoreCtx.hasMatch(folded)) {
      for (final value in _levels(folded)) {
        edus.putIfAbsent(value, () => []).add(sentence);
      }
    }
    for (final value in _quotaTypesIn(folded)) {
      quotas.putIfAbsent(value, () => []).add(sentence);
    }
  }

  final education = _educationEffective(edus);
  String? quotaType;
  for (final value in _quotaPriority) {
    if (quotas.containsKey(value)) {
      quotaType = value;
      break;
    }
  }

  return ConditionFields(
    kpssType: _single(codes, pickKeywords: const ['kpss']),
    kpssScore: _single(scores, pickKeywords: const ['kpss']),
    maxAge: _single(ages),
    education: education == null
        ? null
        : ExtractedField<String>(
            education,
            _pick(edus[education]!, const ['mezun']),
          ),
    quotaType: quotaType == null
        ? null
        : ExtractedField<String>(quotaType, _pick(quotas[quotaType]!)),
  );
}
