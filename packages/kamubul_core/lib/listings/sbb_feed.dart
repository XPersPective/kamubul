import 'dart:convert';

import 'package:http/http.dart' as http;

const sbbHost = 'kamuilan.sbb.gov.tr';
const sbbHomeUrl = 'https://kamuilan.sbb.gov.tr/';

/// Strateji ve Bütçe Başkanlığı "Kamu Personeli Alım İlanları" portalı.
/// Sunucu tarafında işlenen ASP.NET sayfası: yıl formu POST edilerek tam
/// liste alınır; ilan ayrıntı bağlantısı resmî PDF belgeyi döndürür.
class SbbListing {
  const SbbListing({
    required this.institution,
    required this.title,
    required this.url,
    required this.category,
    required this.start,
    required this.deadline,
    required this.quota,
  });

  final String institution;
  final String title;
  final Uri url;
  final String category;

  /// Başvuru penceresi (ilan satırındaki tek tarih verisi).
  final DateTime? start;
  final DateTime? deadline;
  final int? quota;
}

Future<List<SbbListing>> loadSbbListings({
  http.Client? client,
  int? year,
}) async {
  final owned = client == null;
  client ??= http.Client();
  try {
    return parseSbbListings(await loadSbbListPage(client: client, year: year));
  } finally {
    if (owned) client.close();
  }
}

/// Yıl formunun POST edildiği ham liste sayfasını verir (PB-007 korpusu).
Future<String> loadSbbListPage({http.Client? client, int? year}) async {
  final owned = client == null;
  client ??= http.Client();
  final targetYear = year ?? DateTime.now().year;
  try {
    final home = await client
        .get(Uri.parse(sbbHomeUrl))
        .timeout(const Duration(seconds: 30));
    if (home.statusCode != 200 || home.bodyBytes.length > 3 * 1024 * 1024) {
      throw const FormatException('SBB ana sayfası okunamadı');
    }
    final homeHtml = utf8.decode(home.bodyBytes);
    final viewState = _hiddenField(homeHtml, '__VIEWSTATE');
    if (viewState.isEmpty) {
      throw const FormatException('SBB sayfa düzeni değişti');
    }
    // WebForms üçlüsü eksiksiz gönderilmezse sunucu zaman zaman 500 verir.
    final form = <String, String>{
      '__VIEWSTATE': viewState,
      '__EVENTTARGET': 'ddl_yil',
      'ddl_yil': '$targetYear',
    };
    final generator = _hiddenField(homeHtml, '__VIEWSTATEGENERATOR');
    if (generator.isNotEmpty) form['__VIEWSTATEGENERATOR'] = generator;
    final validation = _hiddenField(homeHtml, '__EVENTVALIDATION');
    if (validation.isNotEmpty) form['__EVENTVALIDATION'] = validation;
    final listed = await client
        .post(Uri.parse(sbbHomeUrl), body: form)
        .timeout(const Duration(seconds: 30));
    if (listed.statusCode != 200 || listed.bodyBytes.length > 3 * 1024 * 1024) {
      throw FormatException(
        'SBB listesi okunamadı (HTTP ${listed.statusCode}, '
        '${listed.bodyBytes.length} bayt)',
      );
    }
    return utf8.decode(listed.bodyBytes);
  } finally {
    if (owned) client.close();
  }
}

String _hiddenField(String html, String name) {
  final match = RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(html);
  return match?.group(1) ?? '';
}

const _aylar = [
  'ocak',
  'şubat',
  'mart',
  'nisan',
  'mayıs',
  'haziran',
  'temmuz',
  'ağustos',
  'eylül',
  'ekim',
  'kasım',
  'aralık',
];

final _itemRegex = RegExp(
  "<a href='(ilanDetay\\.aspx\\?kod=[^']+)'[^>]*>(.*?)</a>",
  dotAll: true,
);
final _spanRegex = RegExp(
  "<span[^>]*class\\s*=\\s*['\"]?([a-zA-Z0-9]+)['\"]?[^>]*>(.*?)</span>",
  dotAll: true,
);
final _tagRegex = RegExp(r'<[^>]+>');

final _altP1Regex = RegExp(
  "<p[^>]*class\\s*=\\s*['\"]?alt_p1['\"]?[^>]*>(.*?)</p>",
  dotAll: true,
);
final _altP2Regex = RegExp(
  "<p[^>]*class\\s*=\\s*['\"]?alt_p2['\"]?[^>]*>(.*?)</p>",
  dotAll: true,
);
final _emRegex = RegExp(r'<em[^>]*>(.*?)</em>', dotAll: true);

/// (kurum, başlık, tarih aralığı) üçlüsü; iki satır şablonunu da okur.
///
/// Şablon A: `black`/`patrol`/`h5date` span'ları. Şablon B: `alt_p1`/`alt_p2`
/// paragrafları, tarih aralığı `<em>` içinde parantezli. Logo URL'sindeki
/// `#gün.ay.yıl` eki sunucu anlık damgasıdır (tüm satırlarda aynı gün),
/// yayın tarihi SANILMAMALIDIR; bu yüzden yayınlanma tarihi yoktur.
(String, String, String)? _parseRow(String block) {
  final spans = <String, String>{};
  for (final span in _spanRegex.allMatches(block)) {
    spans[span.group(1)!] = _clean(span.group(2)!);
  }
  final institution = spans['black'] ?? '';
  final patrol = spans['patrol'] ?? '';
  if (institution.isNotEmpty && patrol.isNotEmpty) {
    return (institution, patrol, spans['h5date'] ?? '');
  }
  final instMatch = _altP1Regex.firstMatch(block);
  final bodyMatch = _altP2Regex.firstMatch(block);
  if (instMatch == null || bodyMatch == null) return null;
  final body = bodyMatch.group(1)!;
  final em = _emRegex.firstMatch(body);
  final titleRaw = em == null ? body : body.substring(0, em.start);
  final dateRaw = em == null ? '' : em.group(1)!;
  final altInstitution = _clean(instMatch.group(1)!);
  final altTitle = _clean(titleRaw);
  if (altInstitution.isEmpty || altTitle.isEmpty) return null;
  final dateRange = _clean(dateRaw)
      .replaceAll(RegExp(r'^\s*\(|\)\s*$'), '')
      .trim();
  return (altInstitution, altTitle, dateRange);
}

/// Kontenjan: başlıktaki 1-999 arası sayıların toplamı ("3 UZMAN, 2 DESTEK
/// PERSONEL" = 5). Yıl gibi büyük sayılar kontenjan değildir ("2026 YILI").
int? _parseQuota(String title) {
  final values = RegExp(r'\d+')
      .allMatches(title)
      .map((match) => int.parse(match.group(0)!))
      .where((value) => value >= 1 && value <= 999);
  var total = 0;
  var found = false;
  for (final value in values) {
    total += value;
    found = true;
  }
  return found ? total : null;
}

String _parseCategory(String title) {
  final upper = title.toUpperCase();
  return upper.contains('SÖZLEŞMELİ')
      ? 'Sözleşmeli Personel'
      : upper.contains('İŞÇİ')
      ? 'İşçi'
      : 'Kamu Personeli';
}

/// Liste HTML'inden ilanları çıkarır; düzen değişirse FormatException verir.
///
/// [referenceYear]: satır tarihlerindeki yıl bağlamı (yıl seçimi dekoratif
/// olduğu ve satırda yıl yazılmadığı için). Üretimde bırakılır; PB-007
/// değerlendirmesi sabit yıl ile deterministik çalışır.
List<SbbListing> parseSbbListings(String raw, {int? referenceYear}) {
  final year = referenceYear ?? DateTime.now().year;
  final items = <SbbListing>[];
  for (final match in _itemRegex.allMatches(raw).take(500)) {
    final href = match.group(1)!;
    final kod = Uri.decodeComponent(
      href.replaceFirst('ilanDetay.aspx?kod=', ''),
    );
    if (kod.isEmpty) continue;
    final block = match.group(2)!;
    final row = _parseRow(block);
    if (row == null) continue;
    final (institution, title, dateRange) = row;
    final range = _parseDateRange(dateRange, year);
    items.add(
      SbbListing(
        institution: institution,
        title: title,
        url: Uri.https(sbbHost, '/ilanDetay.aspx', {'kod': kod}),
        category: _parseCategory(title),
        start: range.$1,
        deadline: range.$2,
        quota: _parseQuota(title),
      ),
    );
  }
  if (items.isEmpty) {
    throw const FormatException('SBB listesinde ilan bulunamadı');
  }
  return items;
}

String _clean(String value) => _tagRegex
    .allMatches(value)
    .fold(value, (current, tag) => current.replaceFirst(tag.group(0)!, ''))
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

(DateTime?, DateTime?) _parseDateRange(String value, int year) {
  final parts = value.split(RegExp(r'[-–]'));
  if (parts.length != 2) return (null, null);
  final start = _parseTrDate(parts[0], year);
  var deadline = _parseTrDate(parts[1], year);
  if (start != null && deadline != null && deadline.isBefore(start)) {
    deadline = DateTime(deadline.year + 1, deadline.month, deadline.day);
  }
  return (start, deadline);
}

DateTime? _parseTrDate(String value, int year) {
  final match = RegExp(r'(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)')
      .firstMatch(value.trim());
  if (match == null) return null;
  final month = _aylar.indexOf(match.group(2)!.toLowerCase());
  if (month < 0) return null;
  final day = int.parse(match.group(1)!);
  final date = DateTime(year, month + 1, day);
  return date.day == day && date.month == month + 1 ? date : null;
}
