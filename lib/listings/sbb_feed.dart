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
    required this.publishedAt,
    required this.start,
    required this.deadline,
    required this.quota,
  });

  final String institution;
  final String title;
  final Uri url;
  final String category;
  final DateTime? publishedAt;
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
    return parseSbbListings(utf8.decode(listed.bodyBytes));
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
final _imgDateRegex = RegExp(r'#(\d{1,2})\.(\d{1,2})\.(\d{4})');
final _tagRegex = RegExp(r'<[^>]+>');

/// Liste HTML'inden ilanları çıkarır; düzen değişirse FormatException verir.
List<SbbListing> parseSbbListings(String raw) {
  final items = <SbbListing>[];
  for (final match in _itemRegex.allMatches(raw).take(500)) {
    final href = match.group(1)!;
    final kod = Uri.decodeComponent(
      href.replaceFirst('ilanDetay.aspx?kod=', ''),
    );
    if (kod.isEmpty) continue;
    final block = match.group(2)!;
    final spans = <String, String>{};
    for (final span in _spanRegex.allMatches(block)) {
      spans[span.group(1)!] = _clean(span.group(2)!);
    }
    final institution = spans['black'] ?? '';
    final patrol = spans['patrol'] ?? '';
    final dateRange = spans['h5date'] ?? '';
    if (institution.isEmpty || patrol.isEmpty) continue;
    final quota = RegExp(r'\d+').firstMatch(patrol);
    final upper = patrol.toUpperCase();
    final category = upper.contains('SÖZLEŞMELİ')
        ? 'Sözleşmeli Personel'
        : upper.contains('İŞÇİ')
        ? 'İşçi'
        : 'Kamu Personeli';
    final imgMatch = _imgDateRegex.firstMatch(block);
    final publishedAt = imgMatch == null
        ? null
        : DateTime(
            int.parse(imgMatch.group(3)!),
            int.parse(imgMatch.group(2)!),
            int.parse(imgMatch.group(1)!),
          );
    final range = _parseDateRange(dateRange, publishedAt);
    items.add(
      SbbListing(
        institution: institution,
        title: patrol,
        url: Uri.https(sbbHost, '/ilanDetay.aspx', {'kod': kod}),
        category: category,
        publishedAt: publishedAt,
        start: range.$1,
        deadline: range.$2,
        quota: quota == null ? null : int.tryParse(quota.group(0)!),
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

(DateTime?, DateTime?) _parseDateRange(String value, DateTime? anchor) {
  final parts = value.split(RegExp(r'[-–]'));
  if (parts.length != 2) return (null, null);
  final start = _parseTrDate(parts[0], anchor);
  var deadline = _parseTrDate(parts[1], anchor);
  if (start != null && deadline != null && deadline.isBefore(start)) {
    deadline = DateTime(deadline.year + 1, deadline.month, deadline.day);
  }
  return (start, deadline);
}

DateTime? _parseTrDate(String value, DateTime? anchor) {
  final match = RegExp(r'(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)')
      .firstMatch(value.trim());
  if (match == null) return null;
  final month = _aylar.indexOf(match.group(2)!.toLowerCase());
  if (month < 0) return null;
  final year = anchor?.year ?? DateTime.now().year;
  final day = int.parse(match.group(1)!);
  final date = DateTime(year, month + 1, day);
  return date.day == day && date.month == month + 1 ? date : null;
}
