import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

const kariyerFeedUrl = 'https://kariyerkapisi.gov.tr/RSS';
const kariyerIndexUrl =
    'https://api.kariyerkapisi.gov.tr/api/ilan/GetIseAlimPage';

class PublicListing {
  const PublicListing({
    required this.title,
    required this.category,
    required this.url,
    required this.publishedAt,
    this.deadline,
  });

  final String title;
  final String category;
  final Uri url;
  final DateTime? publishedAt;
  final DateTime? deadline;
}

/// Portalın ilan listesinde kullandığı açık okuma çağrısı son başvuru tarihini
/// verir. RSS yayın gününü tamamlar; API değişirse RSS çalışmaya devam eder.
Future<List<PublicListing>> loadKariyerListings({http.Client? client}) async {
  final ownedClient = client == null;
  client ??= http.Client();
  try {
    List<PublicListing> indexed;
    try {
      final response = await client
          .post(
            Uri.parse(kariyerIndexUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'krM_ID': 0,
              'searchText': '',
              'il': '0',
              'ilanTuru': '0',
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 1024 * 1024) {
        throw const FormatException('İlan listesi okunamadı');
      }
      indexed = parseKariyerIndex(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Exception {
      return await loadKariyerFeed(client: client);
    }
    try {
      final feed = await loadKariyerFeed(client: client);
      final dates = {for (final item in feed) item.url: item.publishedAt};
      return [
        for (final item in indexed)
          PublicListing(
            title: item.title,
            category: item.category,
            url: item.url,
            publishedAt: dates[item.url],
            deadline: item.deadline,
          ),
      ];
    } on Exception {
      return indexed;
    }
  } finally {
    if (ownedClient) client.close();
  }
}

List<PublicListing> parseKariyerIndex(Object? raw) {
  if (raw is! Map<String, dynamic> || raw['searchIlan'] is! List) {
    throw const FormatException('İlan listesi biçimi değişti');
  }
  final seen = <String>{};
  final result = <PublicListing>[];
  final items = raw['searchIlan'] as List;
  for (final item in items.take(200)) {
    if (item is! Map<String, dynamic>) continue;
    final id = item['guid'];
    final title = item['ilanBaslik'];
    final category = item['ilanTuru'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 300 ||
        category == 'Yurt Dışı Eğitim İlanları' ||
        !seen.add(id)) {
      continue;
    }
    final deadline = DateTime.tryParse(
      item['bitTarih'] is String ? item['bitTarih'] as String : '',
    );
    if (deadline == null) continue;
    result.add(
      PublicListing(
        title: title.trim(),
        category: category is String ? category : '',
        url: Uri.https('kariyerkapisi.gov.tr', '/IlanDetay', {'i': id}),
        publishedAt: null,
        deadline: deadline,
      ),
    );
  }
  return result;
}

/// Kariyer Kapısı'nın kendi yayımladığı RSS; sayfa kazıma yalnızca feed yoksa.
Future<List<PublicListing>> loadKariyerFeed({http.Client? client}) async {
  final ownedClient = client == null;
  client ??= http.Client();
  try {
    final response = await client
        .get(Uri.parse(kariyerFeedUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('Kaynak yanıtı okunamadı');
    }
    return parseKariyerFeed(utf8.decode(response.bodyBytes));
  } finally {
    if (ownedClient) client.close();
  }
}

List<PublicListing> parseKariyerFeed(String raw) {
  if (raw.length > 1024 * 1024) throw const FormatException('Akış çok büyük');
  final document = XmlDocument.parse(raw);
  if (document.rootElement.name.local != 'rss') {
    throw const FormatException('RSS bekleniyor');
  }
  String value(XmlElement item, String name) =>
      item.getElement(name)?.innerText.trim() ?? '';
  final seen = <Uri>{};
  final result = <PublicListing>[];
  for (final item in document.findAllElements('item').take(200)) {
    final url = Uri.tryParse(value(item, 'link'));
    final title = value(item, 'title');
    final category = value(item, 'category');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'kariyerkapisi.gov.tr' ||
        url.path != '/IlanDetay' ||
        title.isEmpty ||
        title.length > 300 ||
        category == 'Yurt Dışı Eğitim İlanları' ||
        !seen.add(url)) {
      continue;
    }
    final publishedAt = _parseRssDate(value(item, 'pubDate'));
    result.add(
      PublicListing(
        title: title,
        category: category,
        url: url,
        publishedAt: publishedAt,
      ),
    );
  }
  return result;
}

DateTime? _parseRssDate(String value) {
  final match = RegExp(
    r'^(?:[A-Za-z]{3}, )?(\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}:\d{2}:\d{2}) ([+-]\d{4}|GMT)$',
  ).firstMatch(value);
  if (match == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months.indexOf(match[2]!);
  if (month < 0) return null;
  // Yayın tarihi takvim günüdür; cihaz saat dilimi gece yarısı ilanını
  // yanlışlıkla bir önceki güne kaydırmamalı.
  final day = int.parse(match[1]!);
  final date = DateTime(int.parse(match[3]!), month + 1, day);
  return date.day == day && date.month == month + 1 ? date : null;
}
