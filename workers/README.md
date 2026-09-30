# KamuBul Cloudflare runtime

Kalıcı kaynaklar: Worker `kamubul-api`, D1 `kamubul`. Üretim veritabanına demo
ilan/cihaz yazılmaz. Yapılandırma `wrangler.jsonc`, migration `migrations/`.

```powershell
npm ci
npm test
npx wrangler deploy --dry-run
npm run migrate
npm run deploy
```

Runtime bağımlılığı yok. Node24 native SQLite contract kontrolleri yalnız
bellek içi DB kullanır. Bunlar gerçek FCM/AI/kaynak erişimi testi değildir.

`contracts/criteria-v2.json` Dart/Worker ortak corpus'tur. Saf Dart v2 paritesi
`packages/kamubul_core/test/search_criteria_test.dart` içindedir. Canlı HTTP
sözleşmesini üretime kayıt yazmadan doğrulamak için core dizininde:

```powershell
dart run tool/check_worker.dart
```

Model `@cf/meta/llama-3.1-8b-instruct-fp8`, güncel official catalogue'da doğrulandı:
[model](https://developers.cloudflare.com/workers-ai/models/llama-3.1-8b-instruct-fp8/),
[Free allocation](https://developers.cloudflare.com/workers-ai/platform/pricing/).
Gerçek model değerlendirmesi ve neurons ölçümü henüz tamamlanmadı.

`FCM_CLIENT_EMAIL` ve `FCM_PRIVATE_KEY` yalnız Worker Secrets'tadır.
Firebase Android client ayarı sunucu özel anahtarının yerine geçmez.
Wrangler oturumu Windows keyring'de saklanır; token repoya kopyalanmaz.

Canlı API: https://kamubul-api.devx8585.workers.dev/api/v2/health

Bu runtime geçiş halindedir. Tüm ürünün tamamlandığı varsayılmaz:
`.project-brain/current.md` doğrulanmış durumu, PB-016–021 kalan işi içerir.
Model koşul alanları gerçek extraction değerlendirmesi geçmeden açılmaz.
Digest, indeksli fanout ve PDF/uzun belge işleme henüz tamamlanmadı.
Kaynak erişim hataları kaynak sağlığında açıkça görünür; mobil/proxy ile gizlenmez.
