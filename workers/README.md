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

V2 meta/taxonomy/listings/detail/changes GET uçları açık allowlist ile
Cloudflare Cache API kullanır. Dynamic TTL60s, taxonomy300s; sıralanmış query
anahtarında watermark/cursor korunur. Authorization/Cookie/private history ve
no-store istekleri bypass; no-cache yeniden okur. Önbellek hatası API'yi kesmez.
`X-KamuBul-Cache` HIT/MISS canlı doğrulama içindir. Cache HIT D1 okumasını
azaltır, Worker request kotasını kaldırmaz; Cache API veri merkezine yereldir.

V2 listings/changes sayfaları önce en çok50 kayıt boyutunu okur, yalnız1.8MB
yanıt bütçesine sığan kesintisiz kısmın immutable payload'larını yükler.
Cursor/next yalnız gönderilen kayıtları kapsar; frozen watermark korunur.
Tek kayıt sınırı aşarsa413 record_oversize döner, cursor ilerletilmez ve kaynak
verisi silinmez. Bu durum ayrı belge okuyucu/compact catalogue işi gerektirir;
aynı sayfayı sonsuz retry yapmak çözüm değildir. Büyük sayfanın Free CPU
ölçümü henüz yapılmadı; native test başarısı cloud CPU kanıtı değildir.

Bu runtime geçiş halindedir. Tüm ürünün tamamlandığı varsayılmaz:
`.project-brain/current.md` doğrulanmış durumu, PB-016–021 kalan işi içerir.
Model koşul alanları gerçek extraction değerlendirmesi geçmeden açılmaz.
Uzun kaynak metni 120KB UTF-8 sınırında, en çok12KB parçalarla işlenir.
Her tamamlanan parçanın sonucu kalıcı processing job'da tutulur; son özet
birleştirilmeden yayımlanmaz. `AI_DAILY_JOBS=20` ilan sayısını değil, parça,
birleştirme ve başarısız denemeler dahil günlük model isteklerini sınırlar.
Her isteğin serialized girdisi24KB, çıktısı1024 token ile sınırlıdır.
[rejectIfBusy](https://developers.cloudflare.com/workers-ai/features/reject-if-busy/)
kapasite doluyken kuyruğa kabulü engeller.45 saniyelik uygulama timeout'u
sağlayıcı inference işleminin iptal edildiğini garanti etmez; retry de kotaya sayılır.
Gerçek model kalitesi/neurons/Free CPU ölçümü, PDF/OCR ve120KB üzeri belgeler,
digest ve indeksli fanout henüz tamamlanmadı.
Kaynak erişim hataları kaynak sağlığında açıkça görünür; mobil/proxy ile gizlenmez.
