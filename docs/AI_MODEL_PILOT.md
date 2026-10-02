# Gerçek Workers AI pilotu — 2 Ekim 2026

Sürüm sınırı: aşağıdaki gerçek model çağrıları revision2 kalıcı grup azaltması
eklenmeden önce yapıldı. Son pipeline extractionRevision=2; onun büyük, kaçış
karakterli reduction akışı136 native kontrolde doğrulandı, fakat bu belge o
akışın gerçek model/Worker CPU veya coverage ölçümü değildir. Yeni pilot raporu
extractionRevision ve aiProvenance alanlarını taşır; en çok3 manuel çağrı
tavanı bazı çok aşamalı işlerde tamamlanmaya yetmeyebilir, sessizce artırılmaz.

Cloudflare dashboard Workers Plans ekranında Workers Free `$0`, Current plan
doğrulandı. Ücretli upgrade/fallback açılmadı. Account subscriptions REST okuması
mevcut OAuth kapsamıyla403/code10000 verdi; kapsam genişletilmedi. Model
ilk pilotta `@cf/meta/llama-3.1-8b-instruct-fp8` gerçek REST çağrısına HTTP200 yanıt verdi.
Sonraki karşılaştırmada JSON Mode destekli `@cf/meta/llama-3.1-8b-instruct`
seçildi; Workers Free planı korunur.

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

İlk kontrol noktasında toplam5 girişim,4 HTTP200. Yanıtların bildirdiği toplam179.8903009349 Neurons;
timeout çağrısının tüketimi dahil değildir. Bu tutar günlük hesap toplamı veya
fatura değildir. İlk kontrol noktasında3–5 maddelik tam çıktı, son birleştirme ve
completed-hash dedupe gerçek modelle henüz kanıtlanmamıştı. Pilotlar üretime özet yazmaz.

Birinci parçada model, sınavsız KPSS sıralaması iddiasına puan eşitliği alıntısı
ekledi; alıntının metinde bulunması iddiayı doğrulamıyordu. Koşul adaylarında
istenen schema dışı alanlar, belirsiz kadro ilişkileri ve kaynakta bulunmayan
alıntılar da görüldü. Bu nedenle precision/recall kabul kapısı geçilmiş değildir.

## Uygulanan koruma ve kalan iş

Özet `text` en az30/en çok240 karakter ve kaynakta birebir bulunan `quote`
içinden kesintisiz bir alıntı olmalı; tekrar eden metinler elenir. Model yalnız
30–240 karakterlik quote seçer; text kaynak alıntısından deterministik üretilir.
JSON Mode destekli iki aday için JSON schema, diğer önceki fp8 model için
json_object ve temperature0 kullanılır. Final en az3 ayrı doğrulanmış madde
gerektirir; iki maddeli final yayımlanmaz. Paraphrase ve koşul çıkarımı kalite kapısı geçene kadar
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

## JSON Mode karşılaştırması ve son kontrol noktası

Resmî [JSON Mode desteği](https://developers.cloudflare.com/workers-ai/features/json-mode/)
doğrulandı; Free [fiyat/kota kuralları](https://developers.cloudflare.com/workers-ai/platform/pricing/)
değiştirilmedi. Model seçimi sadece Free erişimli üç incelenmiş adaydan yapılır;
CLI son parametresi modeli override eder, üretim config'ini değiştirmez.

| Sonraki deneme | Çağrı | Sonuç | API bildirilen Neurons |
| --- | ---: | --- | ---: |
|3.3 70B json_object|2| İkinci parça schema dışı; tamamlanmadı |177.0352306366|
|3.3 70B text+quote schema|1| Paraphrase üretildi; exact-excerpt guard reddetti |131.8466033936|
|3.3 70B quote-only schema|3| İki parça+consolidation tamamlandı,3 madde |178.5308532715|
|Önceki3.1 8B fp8 quote-only prompt|1| JSON yerine düz metin; yayımlanmadı |52.7209884515|
|3.1 8B JSON Mode quote-only schema|3| İki parça+consolidation tamamlandı,5 madde |35.7728300095|
|3.1 8B son scope+hash replay kontrolü|3|5 scoped madde; pending replay→superseded, yeni model çağrısı yok |35.8425664902|

Bu belge kapsamındaki toplam18 girişim/17 HTTP200/1 timeout; bilinen toplam
791.6393731877 Neurons, timeout tüketimi bilinmiyor. Bunlar tek gerçek ilan için
kontrollü karşılaştırmalardır;18 farklı ilan veya hesap toplamı değildir.
Seçilen8B JSON Mode son pilotunda3 çağrı yaklaşık6s sürdü; Worker CPU değildir.
API result model alanı `@cf/meta/llama-3.1-8b-json` yönlendirmesi gösterdi;
raporda gerçek usage.neurons esas alınır, fiyat tablosundan kullanım uydurulmaz.

Model artık yalnız quote seçer; tekrar metin/paraphrase üretmez. Consolidation
önceki gibi yalnız her parçanın ilk maddesini değil bütün doğrulanmış alıntıları
görür.24KB request sınırı aşılırsa iş hata verir ve ilerleme korunur;
çok büyük consolidation için bounded multi-pass hâlâ gerekir, alıntı sessizce
atılmaz. JSON parse bozukluğu `ai_schema` olarak kaydedilir.

Kadro bağlamı AI'dan alınmaz: quote bir kaynak pozisyonunda bulunuyorsa o
pozisyonun başlığı (<=50 karakter), birden fazla pozisyonda “Bazı kadrolar”;
pozisyon metninde hiç bulunmayıp ortak metinde bulunuyorsa genel. Aynı quote
ortak metne de kopyalanmışsa kadro etiketi korunur. Tek gerçek kaynak
alanında bulunmayan, birleştirme sınırını geçen quote reddedilir. Additive
`scopeLabel` v2 mobil cache ve v1 string projection'da metnin önüne eklenir;
eski string/unscoped maddeler korunur, malformed label/text elenir.

Son gerçek çıktı: Bilgi ve Belge Yönetimi lisans/P3>=60 maddeleri
“Kütüphaneci (Erkek-Kadın)”; yaş35, öğrenci kaydı ve vardiya şartları “Bazı
kadrolar”. Bu bağlamlı kaynak alıntısı, bütün kadroların typed eligibility
çıkarımı değildir. Genel deadline/yöntem coverage ve yararlı madde seçimi
henüz>=50 örnek üzerinden ölçülmedi. Typed koşullar ve paraphrase kapısı kapalı.

İlk iki başarılı rapor yalnız completed job'a yeniden girişte çağrı olmadığını
kontrol etmişti. Son araç completed job'u aynı hash ile bellekte pending yapar;
processed_hash guard gerçek model çağrısını atlar ve superseded durumu doğrular.
SQL fixture/üretim kaydı değil, gerçek modelin tamamladığı bellekteki pilot işidir.
Model config değişimi eski arşivi topluca yeniden işlemeye açmaz; extractor/model
version ve planlı yeniden işleme sözleşmesi hâlâ ayrı kabul işidir.

Doğrulama: Worker95 native test, Flutter132 full ve10 remote sync targeted,
iki değişen Dart dosyası analyze temiz. Native regression later-source excerpts,
final<3 unpublished, quote-only schema/object yanıt, kaynak kadro etiketleri ve
cross-position quotation reddini kapsar. Mobil SQLite check label'ın kayıtta
korunduğunu kanıtlar; gerçek cihaz/kapalı uygulama FCM veya release UX değildir.

2 Ekim kota düzeltmesi: binding'in resmi hata biçimi `internalCode: description`
olarak doğrulandı.3036 account quota, tamamlanan parçaları ve kalan retry hakkını
koruyarak sonraki UTC güne quota_wait bırakır; aynı gün diğer işler application
budget üzerinden yeni inference yapmadan bekler.3040 capacity, aynı parçanın
mevcut en çok5 deneme/backoff yolundadır; ilerleme korunur, sonunda failed açıkça
kaydedilir. daily_usage.ai_jobs bu kesici sonrası uygulama bütçe tavanıdır,
gerçek çağrı/Neuron veya fatura sayacı olarak yorumlanmaz.97 native test geçti;
canlı kotayı tüketerek hata oluşturulmadı, bu yollar SQLite regression kanıtıdır.

Pilot REST aracı artık `options.rejectIfBusy=true` gönderir ve3036/3040 provider
kodlarını pipeline'a koruyarak geçirir. Önceki18 gerçek girişimde bu seçenek
adapter assertion'ında kontrol edilse de HTTP gövdesine eklenmemişti; production
binding üçüncü argümanda zaten gönderiyordu. Önceki model/schema/quote sonuçları
geçerlidir; rejectIfBusy kapasite/latency paritesi kanıtı olarak kullanılamaz.
Bu düzeltmede yeni model çağrısı yoktur. Kaynaklar:
[runtime hata ayrıştırma](https://github.com/cloudflare/workerd/blob/main/src/cloudflare/internal/ai-api.ts),
[provider hata kodları](https://developers.cloudflare.com/workers-ai/platform/errors/),
[REST ve binding rejectIfBusy](https://developers.cloudflare.com/workers-ai/features/reject-if-busy/).
