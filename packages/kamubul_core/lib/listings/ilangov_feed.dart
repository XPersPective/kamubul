import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/turkish_cities.dart';

const ilanGovHost = 'www.ilan.gov.tr';
const _api = 'https://www.ilan.gov.tr/api/api/services/app';

/// Sitenin kendi arayüzünün gönderdiği başlıklar; bunlarsız API boş döner.
const _headers = {
  'Accept': 'text/plain',
  'Content-Type': 'application/json-patch+json',
  'X-Requested-With': 'XMLHttpRequest',
  'X-Request-Origin': 'IGT-UI',
};

/// Basın İlan Kurumu portalındaki "PERSONEL ALIMI" türü ilan (belediyeler,
/// üniversiteler, Resmî Gazete/DPB). robots.txt yalnız tebligatı yasaklar.
class IlanGovListing {
  const IlanGovListing({
    required this.id,
    required this.institution,
    required this.title,
    required this.url,
    required this.category,
    required this.city,
    required this.publishedAt,
  });

  final String id;
  final String institution;
  final String title;
  final Uri url;
  final String category;

  /// Kanonik il adı; tanınmazsa null (tahmin edilmez).
  final String? city;
  final DateTime? publishedAt;
}

/// Liste ucu sayfa başına en çok 20 kayıt verir; nazik sınır 10 sayfa.
Future<List<IlanGovListing>> loadIlanGovListings({
  http.Client? client,
  int maxPages = 10,
}) async {
  final owned = client == null;
  client ??= http.Client();
  try {
    final items = <IlanGovListing>[];
    for (var page = 0; page < maxPages; page++) {
      final response = await client
          .post(
            Uri.parse('$_api/Ad/AdsByFilter'),
            headers: _headers,
            body: jsonEncode({
              'keys': {
                'ats': [5],
              },
              'skipCount': page * 20,
              'maxResultCount': 20,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 3 * 1024 * 1024) {
        throw FormatException('ilan.gov.tr HTTP ${response.statusCode}');
      }
      final (batch, total) = parseIlanGovAds(utf8.decode(response.bodyBytes));
      items.addAll(batch);
      if (batch.isEmpty || items.length >= total) break;
    }
    return items;
  } finally {
    if (owned) client.close();
  }
}

/// AdsByFilter yanıtını ilanlara ve toplam sayıya çevirir.
(List<IlanGovListing>, int) parseIlanGovAds(String body) {
  final json = jsonDecode(body);
  final result = json is Map ? json['result'] : null;
  if (result is! Map || result['ads'] is! List) {
    throw const FormatException('ilan.gov.tr yanıt düzeni değişti');
  }
  final items = <IlanGovListing>[];
  for (final ad in (result['ads'] as List).whereType<Map>()) {
    final id = '${ad['id'] ?? ''}';
    final title = '${ad['title'] ?? ''}'.trim();
    final path = '${ad['urlStr'] ?? ''}';
    if (id.isEmpty || title.isEmpty || !path.startsWith('/ilan/')) continue;
    final values = ad['values'] is List ? ad['values'] as List : const [];
    final category = values
        .whereType<Map>()
        .where((v) => v['key'] == 'Kategori')
        .map((v) => '${v['value'] ?? ''}')
        .firstOrNull;
    final city = '${ad['addressCityName'] ?? ''}';
    items.add(
      IlanGovListing(
        id: id,
        institution: '${ad['advertiserName'] ?? ''}'.trim(),
        title: title,
        url: Uri.https(ilanGovHost, path),
        category: category ?? 'Personel Alımı',
        city: city.isEmpty ? null : canonicalCity(city),
        publishedAt: DateTime.tryParse('${ad['publishStartDate'] ?? ''}'),
      ),
    );
  }
  final total = result['numFound'];
  return (items, total is int ? total : items.length);
}

/// Ayrıntı metni (Asistan bağlamı için); HTML düz metne indirgenir.
Future<String> loadIlanGovDetailText(String id, {http.Client? client}) async {
  final owned = client == null;
  client ??= http.Client();
  try {
    final response = await client
        .get(
          Uri.parse('$_api/AdDetail/GetAdDetail?id=${Uri.encodeQueryComponent(id)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 3 * 1024 * 1024) {
      throw FormatException('ilan.gov.tr ayrıntı HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final content = json is Map && json['result'] is Map
        ? json['result']['content']
        : null;
    if (content is! String) {
      throw const FormatException('ilan.gov.tr ayrıntı düzeni değişti');
    }
    return htmlToPlainText(content);
  } finally {
    if (owned) client.close();
  }
}

/// Basit HTML → metin: blok sonları satıra, etiketler silinir, varlıklar çözülür.
String htmlToPlainText(String html) {
  const entities = {
    '&nbsp;': ' ',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&uuml;': 'ü',
    '&Uuml;': 'Ü',
    '&ouml;': 'ö',
    '&Ouml;': 'Ö',
    '&ccedil;': 'ç',
    '&Ccedil;': 'Ç',
    '&acirc;': 'â',
    '&icirc;': 'î',
    '&ucirc;': 'û',
    '&rsquo;': '’',
    '&lsquo;': '‘',
    '&rdquo;': '”',
    '&ldquo;': '“',
    '&amp;': '&', // en son: çift çözme olmasın
  };
  var text = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true), '')
      .replaceAll(
        RegExp(r'<br\s*/?>|</(p|div|tr|li|h\d)>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  entities.forEach((k, v) => text = text.replaceAll(k, v));
  text = text.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m[1]!)),
  );
  return text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t\r]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}
