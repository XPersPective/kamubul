// Kapsama denetimi: resmî kaynakların canlı toplamı ↔ telefon okuyucusu ↔
// sunucu kataloğu. "Kaçan" = kaynakta olup ne telefonun ne sunucunun aldığı.
//   dart run tool/check_coverage.dart [api-base]
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kamubul_core/kamubul_core.dart';

Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'https://kamubul-api.devx8585.workers.dev' : args.first;
  final client = http.Client();
  // Kaynağın kendi toplamı (okuyucu sınırlarından bağımsız).
  final kariyerRaw = jsonDecode(utf8.decode((await client.post(Uri.parse(kariyerIndexUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'krM_ID': 0, 'searchText': '', 'il': '0', 'ilanTuru': '0'}))).bodyBytes)) as Map;
  final kariyerTotal = (kariyerRaw['searchIlan'] as List).length;
  final kariyer = await loadKariyerListings(client: client);
  final ilanGov = await loadIlanGovListings(client: client);
  final igTotal = parseIlanGovAds(utf8.decode((await client.post(Uri.parse('https://www.ilan.gov.tr/api/api/services/app/Ad/AdsByFilter'), headers: {'Accept': 'text/plain', 'Content-Type': 'application/json-patch+json', 'X-Requested-With': 'XMLHttpRequest', 'X-Request-Origin': 'IGT-UI'}, body: jsonEncode({'keys': {'ats': [5]}, 'skipCount': 0, 'maxResultCount': 1}))).bodyBytes)).$2;
  final iskur = await loadIskurListings(client: client);
  // Sunucu kataloğu (son anlık görüntü).
  final meta = jsonDecode((await client.get(Uri.parse('$base/api/v2/meta'))).body) as Map;
  final server = <String, Map>{};
  String? after = '';
  while (after != null) {
    final page = jsonDecode((await client.get(Uri.parse('$base/api/v2/listings?watermark=${meta['latestSeq']}&after=${Uri.encodeQueryComponent(after)}&limit=50'))).body) as Map;
    for (final item in (page['items'] as List).cast<Map>()) {
      if (item['active'] != false && item['url'] is String) server[item['url'] as String] = item;
    }
    after = page['next'] as String?;
  }
  client.close();
  String key(String url) => url.contains('kariyerkapisi') ? url.toLowerCase() : url;
  final serverKeys = {for (final u in server.keys) key(u)};
  void report(String name, int sourceTotal, Iterable<String> phoneUrls, String serverSource) {
    final phone = {for (final u in phoneUrls) key(u)};
    final onServer = server.values.where((i) => i['sourceId'] == serverSource).length;
    final missingServer = phone.where((u) => !serverKeys.contains(u)).length;
    print('$name: kaynak=$sourceTotal telefon=${phone.length} sunucu=$onServer '
        'telefon-sınırı-kaybı=${sourceTotal - phone.length} sunucuda-olmayan=$missingServer');
  }
  report('Kariyer Kapısı', kariyerTotal, kariyer.map((i) => i.url.toString()), 'kariyerkapisi');
  report('ilan.gov.tr', igTotal, ilanGov.map((i) => i.url.toString()), 'ilangov');
  report('İŞKUR (kamu)', iskur.length, iskur.map((i) => i.url.toString()), 'iskur');
  print('sunucu toplam etkin=${server.length}; kaynaklar: ${meta['sources']}');
}
