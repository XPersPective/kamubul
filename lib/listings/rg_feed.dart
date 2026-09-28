import 'dart:convert';

import 'package:http/http.dart' as http;

const rgHost = 'www.resmigazete.gov.tr';

/// Resmî Gazete "personel alımı" duyuruları (PB-009).
///
/// Eski arşiv dizini (/eskiler/YYYY/MM/YYYYMMDD.htm) başlıksız belge
/// bağlantıları verir; her .htm belge çekilip başlığından sınıflandırılır.
/// robots.txt taramayı yasaklamıyor (2026-09-27 doğrulandı); günde tek
/// dizin + sınırlı belge isteği yapılır.
class RgNotice {
  const RgNotice({
    required this.title,
    required this.url,
    required this.publishedAt,
  });

  final String title;
  final Uri url;
  final DateTime publishedAt;
}

/// windows-1254: latin1'in yalnızca altı üst baytı Türkçe harflere sapar.
String decodeWindows1254(List<int> bytes) {
  final latin = latin1.decode(bytes, allowInvalid: true);
  return latin
      .replaceAll('Ð', 'Ğ')
      .replaceAll('Ý', 'İ')
      .replaceAll('Þ', 'Ş')
      .replaceAll('ð', 'ğ')
      .replaceAll('ý', 'ı')
      .replaceAll('þ', 'ş');
}

String _pagePath(DateTime date) =>
    '/eskiler/${date.year}/${date.month.toString().padLeft(2, '0')}/'
    '${date.year}${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}.htm';

final _docLinkRegex = RegExp(
  r'''href=.(\d{8}-\d{1,3}\.htm)[^>]*>''',
  caseSensitive: false,
);

final _tagRegex = RegExp(r'<[^>]+>');

/// Başlıklar yalnızca tarih içerir; sınıflandırma gövde metnine bakar.
bool _looksLikePersonnelNotice(String bodyText) {
  final lower = bodyText.toLowerCase();
  return (lower.contains('personel') &&
          (lower.contains('alın') || lower.contains('alim'))) ||
      lower.contains('memur alım') ||
      lower.contains('kadroya atan');
}

String _noticeTitle(String bodyText, String fallback) {
  for (final line in bodyText.split('\\n')) {
    final clean = line.trim();
    if (clean.length < 12 || clean.length > 200) continue;
    final lower = clean.toLowerCase();
    if (lower.contains('personel') &&
        (lower.contains('alın') || lower.contains('alim'))) {
      return clean;
    }
  }
  return fallback;
}

/// Verilen günün Resmî Gazete'sinde personel alımı duyurularını arar.
/// Belge başlığı uymayan belgeler atlanır; dizin bozuksa FormatException.
Future<List<RgNotice>> loadRgPersonnelNotices({
  http.Client? client,
  DateTime? date,
  int maxDocs = 12,
}) async {
  final ownedClient = client == null;
  client ??= http.Client();
  final day = date ?? DateTime.now().subtract(const Duration(days: 1));
  final path = _pagePath(day);
  try {
    final index = await client
        .get(Uri.https(rgHost, path))
        .timeout(const Duration(seconds: 20));
    if (index.statusCode != 200 || index.bodyBytes.length > 2 * 1024 * 1024) {
      throw FormatException('RG dizini okunamadı ($path)');
    }
    final indexHtml = decodeWindows1254(index.bodyBytes);
    final docs = _docLinkRegex
        .allMatches(indexHtml)
        .map((match) => match.group(1))
        .toSet()
        .take(maxDocs)
        .toList();
    if (docs.isEmpty) {
      throw const FormatException('RG dizin düzeni değişti');
    }
    final notices = <RgNotice>[];
    for (final doc in docs) {
      final response = await client
          .get(
            Uri.https(
              rgHost,
              '/eskiler/${day.year}/${day.month.toString().padLeft(2, '0')}/$doc',
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 1024 * 1024) {
        continue;
      }
      final html = decodeWindows1254(response.bodyBytes);
      final bodyText = html
          .replaceAll(
            RegExp(r'<(script|style)[\\s\\S]*?</\1>', caseSensitive: false),
            ' ',
          )
          .replaceAll(_tagRegex, '\n')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      if (bodyText.isEmpty) continue;
      if (_looksLikePersonnelNotice(bodyText)) {
        notices.add(
          RgNotice(
            title: _noticeTitle(bodyText, 'Resmî Gazete ilanı'),
            url: Uri.https(
              rgHost,
              '/eskiler/${day.year}/${day.month.toString().padLeft(2, '0')}/$doc',
            ),
            publishedAt: DateTime(day.year, day.month, day.day),
          ),
        );
      }
    }
    return notices;
  } finally {
    if (ownedClient) client.close();
  }
}
