# Gerçek Workers AI pilotu — 2 Ekim 2026

Cloudflare dashboard Workers Plans ekranında Workers Free `$0`, Current plan
doğrulandı. Ücretli upgrade/fallback açılmadı. Account subscriptions REST okuması
mevcut OAuth kapsamıyla403/code10000 verdi; kapsam genişletilmedi. Model
`@cf/meta/llama-3.1-8b-instruct-fp8` gerçek REST çağrısına HTTP200 yanıt verdi.

## Girdi ve kapsam

Resmî [Sivas Bilim ve Teknoloji Üniversitesi ilanı](https://kariyerkapisi.gov.tr/IlanDetay?i=a3fc2acb-8b4d-48c0-b273-1a68554b2772),
8 kadro, birleşik metin14361 UTF8 byte, iki12KB parça. Windows üzerinden alınan
gerçek liste/ayrıntı metni kullanıldı. Semantic input SHA256:
`84f653267eb1edb850696599e56e9a4ff700c0844271f9c6098a367ccf6f7b28`.
Üretim `processNotice`/parçalama/doğrulama kodu bellekteki SQLite migration'ları
ile çalıştırıldı. Üretim D1'e ilan/kurulum/outbox yazılmadı, push gönderilmedi.
Bu, Worker kaynak egress'i veya Free CPU kanıtı değildir.

## Sonuç

| Deneme | Gerçek çağrı | Sonuç | API bildirilen Neurons |
| --- | ---: | --- | ---: |
| İlk prompt |1| Tek özet maddesi240 karakter sınırını aştı; yayımlanmadı |58.9845588272|
| Açık uzunluk sınırları |1|45s sürede tamamlanmadı; tüketim bilinmiyor | Bilinmiyor |
| Aynı prompt, sınırlı yeni pilot |2| İlk parça kabul edildi; ikinci parçada birebir alıntı yok, iş tamamlanmadı |71.4137011049|
| Alıntı içinden metin/temperature0 |1| Model metin/alıntıyı birebir kopyalamadı, yeni kontrol reddetti |49.4920400027|

Toplam5 girişim,4 HTTP200. Yanıtların bildirdiği toplam179.8903009349 Neurons;
timeout çağrısının tüketimi dahil değildir. Bu tutar günlük hesap toplamı veya
fatura değildir.3–5 maddelik tam çıktı, son birleştirme ve completed-hash dedupe
gerçek modelle henüz kanıtlanmadı. Hiçbir deneme üretime tamamlanmış özet yazmadı.

Birinci parçada model, sınavsız KPSS sıralaması iddiasına puan eşitliği alıntısı
ekledi; alıntının metinde bulunması iddiayı doğrulamıyordu. Koşul adaylarında
istenen schema dışı alanlar, belirsiz kadro ilişkileri ve kaynakta bulunmayan
alıntılar da görüldü. Bu nedenle precision/recall kabul kapısı geçilmiş değildir.

## Uygulanan koruma ve kalan iş

Özet `text` en az10/en çok240 karakter ve kaynakta birebir bulunan `quote`
içinden kesintisiz bir alıntı olmalı. Prompt10–180/10–400 karakter ister,
temperature0 kullanır. Paraphrase ve koşul çıkarımı kalite kapısı geçene kadar
açılmaz; conditions boş istenir. Alıntı seçiminin önem/anlaşılabilirlik/coverage
kalitesi henüz kanıtlanmadı. Bu geçici kaynak alıntısı koruması, hedefteki
kanıtlı Türkçe özet ve typed şart çıkarımının yerine tamamlanmış kabul edilmez.

Sonraki çalışma: Free erişimli model/prompt karşılaştırması, gerçek kadro
kimliğiyle kaynak-grounded extraction, kaynak başına>=50 etiketli ilan,
alan precision>=0.95/recall/coverage ve gerçek per-notice toplam Neurons;
sonra Worker CPU ve üretim kaynak erişimi. Guard'ı gevşeterek geçerli sonuç
elde edilmiş sayılmaz. Timeout sağlayıcı işleminin iptal edildiğini kanıtlamaz.

## Tekrarlama

Workers Free planını dashboard'da doğrula; sadece aktif gerçek resmî ilan
JSON'u, Node24 ve mevcut yetkili Wrangler oturumu kullan. Worker dizininde:

```powershell
node tool/eval-ai.js ../.tmp/ai-pilot-notice.json ../.tmp/ai-pilot-report.json
```

Araç en çok3 model çağrısı yapar, hata sonrası otomatik retry yoktur; gerçek
`processNotice` ve bellekteki DB kullanılır. OAuth yalnız işlem belleğindedir;
raporda credential yoktur. CLI çağrıları üretim D1 günlük20 istek sayacına
yazılmaz; manuel pilot tüketimi ayrıca değerlendirilmelidir. Tekrarlar otomatik
döngüye alınmaz. Rapor başarısızsa exit1; model API usage/Neurons, ham public
çıktı ve kabul edilen summary kaydedilir. Ignored `.tmp` dosyaları Git'e girmez;
devirde yukarıdaki kaynak/hash/sonuç kaydı esas alınır.
