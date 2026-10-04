import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/turkish_cities.dart';
import 'ilangov_feed.dart' show htmlToPlainText;

const iskurHost = 'esube.iskur.gov.tr';
const _searchUrl = 'https://esube.iskur.gov.tr/Istihdam/AcikIsIlanAra.aspx';

/// İŞKUR'daki YALNIZ kamu işyeri ilanı (kamu işçi alımı). Özel sektör
/// ilanları kapsam dışıdır: arama "Kamu" filtresiyle yapılır, her satır ayrıca
/// "Kamu" etiketiyle doğrulanır; filtre sayfadan kalkarsa hiç okunmaz.
class IskurListing {
  const IskurListing({
    required this.id,
    required this.institution,
    required this.occupation,
    required this.url,
    required this.period,
    required this.quota,
    required this.city,
    required this.district,
    required this.deadline,
  });

  final String id;
  final String institution;
  final String occupation;
  final Uri url;

  /// "Daimi" ya da "Geçici".
  final String period;
  final int? quota;
  final String? city;
  final String? district;
  final DateTime? deadline;
}

Uri iskurDetailUrl(String id) => Uri.https(
  iskurHost,
  '/Istihdam/AcikIsIlanDetay.aspx',
  {'uiID': id, 'isyeriTuru': 'Kamu'},
);

Future<List<IskurListing>> loadIskurListings({http.Client? client}) async {
  final owned = client == null;
  client ??= http.Client();
  try {
    final home = await client
        .get(Uri.parse(_searchUrl))
        .timeout(const Duration(seconds: 30));
    if (home.statusCode != 200 || home.bodyBytes.length > 3 * 1024 * 1024) {
      throw FormatException('İŞKUR arama sayfası HTTP ${home.statusCode}');
    }
    final page = utf8.decode(home.bodyBytes, allowMalformed: true);
    if (!page.contains('value="kamuRadio"')) {
      // Kamu filtresi yoksa özel sektör listesine düşmemek için okuma yapılmaz.
      throw const FormatException('İŞKUR kamu filtresi bulunamadı');
    }
    final form = <String, String>{
      '__EVENTTARGET': r'ctl04$ctlAcikIsPageCommand$CommandItem_Search',
      '__EVENTARGUMENT': '',
      r'ctl04$IsyeriTuruRadios': 'kamuRadio',
    };
    for (final name in [
      '__VIEWSTATE',
      '__VIEWSTATEGENERATOR',
      '__VIEWSTATEENCRYPTED',
      '__EVENTVALIDATION',
    ]) {
      final m = RegExp(
        'name="${RegExp.escape(name)}"[^>]*value="([^"]*)"',
      ).firstMatch(page);
      if (m != null) form[name] = _unescape(m[1]!);
    }
    final cookie = home.headers['set-cookie'];
    final listed = await client
        .post(
          Uri.parse(_searchUrl),
          headers: {
            if (cookie != null)
              'Cookie': cookie
                  .split(RegExp(r',(?=[^;]+=)'))
                  .map((c) => c.split(';').first.trim())
                  .join('; '),
          },
          body: form,
        )
        .timeout(const Duration(seconds: 60));
    if (listed.statusCode != 200 ||
        listed.bodyBytes.length > 3 * 1024 * 1024) {
      throw FormatException('İŞKUR listesi HTTP ${listed.statusCode}');
    }
    return parseIskurKamuGrid(utf8.decode(listed.bodyBytes, allowMalformed: true));
  } finally {
    if (owned) client.close();
  }
}

/// Sonuç tablosunu okur; "Kamu" olmayan satırlar atlanır.
List<IskurListing> parseIskurKamuGrid(String html) {
  final grid = html.indexOf('ctlGridAcikIslerListeDetail');
  if (grid < 0) throw const FormatException('İŞKUR sonuç tablosu yok');
  final rows = html.substring(grid).split(RegExp(r'<tr\b'));
  String? span(String row, String suffix) {
    final m = RegExp(
      '_${RegExp.escape(suffix)}"[^>]*>([\\s\\S]*?)</span>',
    ).firstMatch(row);
    return m == null ? null : htmlToPlainText(m[1]!).replaceAll('\n', ' ');
  }

  final items = <IskurListing>[];
  for (final row in rows) {
    final link = RegExp(
      r"PopupJobDetails\(&#39;(\d+)&#39;,&#39;([^&]*)&#39;[^>]*>([\s\S]*?)</a>",
    ).firstMatch(row);
    if (link == null) continue;
    final id = link[1]!;
    if (link[2] != 'Kamu' || span(row, 'ctlIsverenTurDL') != 'Kamu') continue;
    final place = RegExp(
      r'Çalışma Yeri:\s*([^/)]+?)\s*/\s*([^)]+?)\s*\)',
    ).firstMatch(span(row, 'ctlCalismaYeriDL') ?? '');
    final date = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$',
    ).firstMatch(span(row, 'ctlSonBasvuruTarihi') ?? '');
    items.add(
      IskurListing(
        id: id,
        institution: span(row, 'ctlIsverenDL') ?? '',
        occupation: htmlToPlainText(link[3]!).replaceAll('\n', ' '),
        url: iskurDetailUrl(id),
        period: span(row, 'ctlCalismaPeriyotDL') ?? '',
        quota: int.tryParse(span(row, 'Label9') ?? ''),
        city: place == null ? null : canonicalCity(place[1]!),
        district: place?[2],
        // Son gün sonuna kadar başvurulabilir (İstanbul saati gün sonu).
        deadline: date == null
            ? null
            : DateTime(
                int.parse(date[3]!),
                int.parse(date[2]!),
                int.parse(date[1]!),
                23,
                59,
              ),
      ),
    );
  }
  return items;
}

/// Ayrıntı sayfası girişsiz açıktır; özel şartlar Asistan bağlamı olur.
Future<String> loadIskurDetailText(String id, {http.Client? client}) async {
  final owned = client == null;
  client ??= http.Client();
  try {
    final response = await client
        .get(iskurDetailUrl(id))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 3 * 1024 * 1024) {
      throw FormatException('İŞKUR ayrıntı HTTP ${response.statusCode}');
    }
    final text = htmlToPlainText(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    // Giriş formu ve genel hususlar yerine özel şartlardan başlanır.
    final start = text.indexOf('ÖZEL ŞARTLAR');
    final from = start >= 0 ? start : text.indexOf('Genel Hususlar');
    if (from < 0) throw const FormatException('İŞKUR ayrıntı düzeni değişti');
    return text.substring(from);
  } finally {
    if (owned) client.close();
  }
}

String _unescape(String s) => s
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');
