import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:napp_core/napp_core.dart';

import 'remote_sync.dart';

const _firstKey = 'kamubul.ads.first';

/// Yerel ve sunucu ilk açılış zamanlarından erken olanı (yeniden kurulumla
/// deneme süresi sıfırlanamaz).
int earliestFirstLaunch(int? localMs, DateTime? server) {
  final serverMs = server?.millisecondsSinceEpoch;
  if (localMs == null) return serverMs ?? DateTime.now().millisecondsSinceEpoch;
  if (serverMs == null) return localMs;
  return serverMs < localMs ? serverMs : localMs;
}

/// Cihazın uygulamaya özgü kimlik karmasıyla deneme başlangıcını sunucudan
/// alır. Ağ yoksa veya hata olursa yerel değer korunur; uygulama beklemez.
Future<void> syncTrialStart(
  SettingsStore store, {
  http.Client? client,
  MethodChannel channel = const MethodChannel('kamubul/device'),
  String baseUrl = kApiBaseUrl,
}) async {
  if (baseUrl.isEmpty) return;
  final ownedClient = client == null;
  final http.Client c = client ?? http.Client();
  try {
    final hash = await channel.invokeMethod<String>('trialHash');
    if (hash == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) return;
    final response = await c
        .post(
          Uri.parse('$baseUrl/api/v2/trial'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'deviceHash': hash}),
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) return;
    final body = jsonDecode(response.body);
    final firstSeen = body is Map
        ? DateTime.tryParse('${body['firstSeen']}')
        : null;
    if (firstSeen == null) return;
    store.setInt(
      _firstKey,
      earliestFirstLaunch(store.getInt(_firstKey), firstSeen),
    );
  } on Object {
    // Çevrimdışı/eski cihaz: yerel deneme sayacı geçerli kalır.
  } finally {
    if (ownedClient) c.close();
  }
}
