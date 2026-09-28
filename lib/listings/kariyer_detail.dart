import 'dart:convert';

import 'package:http/http.dart' as http;

class KariyerPosition {
  const KariyerPosition({
    required this.title,
    required this.profession,
    required this.conditions,
    required this.quota,
    required this.places,
  });

  final String title;
  final String profession;
  final String conditions;
  final int quota;
  final List<String> places;

  List<String> get keyConditions => conditions
      .split(RegExp(r'\n+'))
      .map((line) => line.trim())
      .where(
        (line) => RegExp(
          r'KPSS|yaş|mezun|öğrenim',
          caseSensitive: false,
        ).hasMatch(line),
      )
      .take(4)
      .toList();
}

class KariyerDetail {
  const KariyerDetail({
    required this.institution,
    required this.body,
    required this.start,
    required this.deadline,
    required this.applyUrl,
    required this.positions,
  });

  final String institution;
  final String body;
  final DateTime? start;
  final DateTime? deadline;
  final Uri? applyUrl;
  final List<KariyerPosition> positions;

  int get quota => positions.fold(0, (total, item) => total + item.quota);
  List<String> get places =>
      positions.expand((item) => item.places).toSet().toList();
}

/// Kariyer Kapısı ilan sayfasının kullandığı herkese açık iki okuma çağrısı.
Future<KariyerDetail> loadKariyerDetail(
  Uri listingUrl, {
  http.Client? client,
}) async {
  if (listingUrl.scheme != 'https' ||
      listingUrl.host != 'kariyerkapisi.gov.tr' ||
      listingUrl.path != '/IlanDetay' ||
      listingUrl.queryParameters['i'] == null) {
    throw const FormatException('Geçersiz resmî ilan bağlantısı');
  }
  final id = listingUrl.queryParameters['i']!;
  final ownedClient = client == null;
  client ??= http.Client();
  Future<Object?> fetch(String route) async {
    final response = await client!
        .post(
          Uri.parse('https://api.kariyerkapisi.gov.tr/api/$route'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ilanGuid': id}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('İlan ayrıntısı alınamadı');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  try {
    final main = await fetch('ilan/GetIlanPreviewPublic');
    final positions = await fetch('altilan/GetAltIlanInfoByIlanIdPublic');
    return parseKariyerDetail(main, positions);
  } finally {
    if (ownedClient) client.close();
  }
}

KariyerDetail parseKariyerDetail(Object? main, Object? rawPositions) {
  if (main is! Map<String, dynamic> || rawPositions is! List) {
    throw const FormatException('İlan biçimi değişti');
  }
  String field(Map<String, dynamic> map, String key) =>
      map[key] is String ? map[key] as String : '';
  final positions = <KariyerPosition>[];
  for (final raw in rawPositions.take(100)) {
    if (raw is! Map<String, dynamic>) continue;
    final places = <String>[];
    var quota = 0;
    final rawQuotas = raw['kontenjanList'];
    if (rawQuotas is List) {
      for (final item in rawQuotas.take(100)) {
        if (item is! Map<String, dynamic>) continue;
        final count = item['kontenjan'];
        if (count is int && count > 0 && count < 100000) quota += count;
        final place = field(item, 'il').trim();
        final halves = place.split(' / ');
        final cleaned = halves.length == 2 && halves[0] == halves[1]
            ? halves[0]
            : place;
        if (cleaned.isNotEmpty) places.add(cleaned);
      }
    }
    positions.add(
      KariyerPosition(
        title: field(raw, 'ilanBaslik').trim(),
        profession: field(raw, 'unvan').trim(),
        conditions: plainNoticeText(field(raw, 'ilanMetni')),
        quota: quota,
        places: places.toSet().toList(),
      ),
    );
  }
  final rawUrl = main['eDevletteGorunsun'] == 1
      ? field(main, 'eDevletServisURL')
      : field(main, 'basvuruLinki');
  final applyUrl = Uri.tryParse(rawUrl);
  return KariyerDetail(
    institution: field(main, 'kurumAdi').trim(),
    body: plainNoticeText(field(main, 'ilanMetni')),
    start: DateTime.tryParse(field(main, 'basTarih')),
    deadline: DateTime.tryParse(field(main, 'bitTarih')),
    applyUrl: applyUrl?.scheme == 'https' ? applyUrl : null,
    positions: positions,
  );
}

String plainNoticeText(String value) => value
    .replaceAll(RegExp(r'\[url=[^\]]+\]', caseSensitive: false), '')
    .replaceAll(RegExp(r'\[/?[a-z]+(?:=[^\]]+)?\]', caseSensitive: false), '')
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
