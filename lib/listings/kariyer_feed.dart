import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

const kariyerFeedUrl = 'https://kariyerkapisi.gov.tr/RSS';

class PublicListing {
  const PublicListing({
    required this.title,
    required this.category,
    required this.url,
    required this.publishedAt,
  });

  final String title;
  final String category;
  final Uri url;
  final DateTime? publishedAt;
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
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'kariyerkapisi.gov.tr' ||
        url.path != '/IlanDetay' ||
        title.isEmpty ||
        title.length > 300 ||
        !seen.add(url)) {
      continue;
    }
    final publishedAt = _parseRssDate(value(item, 'pubDate'));
    result.add(
      PublicListing(
        title: title,
        category: value(item, 'category'),
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
