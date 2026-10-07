# Kullanım, limit ve kredi kontrolü

Proje kökünde, mevcut Cloudflare sahibi oturumuyla:

```powershell
node tool/admin-usage.mjs 7 > .project-brain/.cache/admin-usage-7d.json
```

1–30 günlük salt okunur rapor: son canlı deployment ayarları, Asistan ve ayıklama
giriş/çıkış/cache tokenları, anonim aktif kurulum sayısı ve deneme sayısı,
kuyruk görevleri, ayıklama backlog'u ve bildirim durumları. Secret/kurulum kimliği,
IP/mesaj/profil içermez. Bu yerel yönetici aracıdır; genel API'ye yönetici verisi açmaz.

Yeni `metrics:` sayaçları model ve istemcinin bildirdiği free/pro tier bazında model
yanıtı sayısını, tam token ölçümü gelen yanıt sayısını ve token toplamlarını tutar.
`meanTokensPerMeasuredResponse`, yalnız giriş+çıkış ölçümü bulunan yanıtlardan hesaplanır.
Önceki token toplamları ayrı korunur; eski çağrı sayaçları başarısız/limitli denemeleri
de saydığı için kesin soru başına ortalama sayılmaz. Aktif kurulum başına günlük token
ortalaması raporlanır; geçmişte kayıt gün ortasında açılmış olabilir. Pro tier henüz
Play sunucu doğrulamasından geçmediği için bu ayrım doğrulanmış satın alma değildir.

Kredi bakiyesi token değildir. HTTP hatası/timeout sağlayıcıda kredi tüketmiş olabilir;
model yanıtındaki usage buna tam kanıt sağlamaz. Qwen hesabındaki gerçek kredi tüketimi
ve kalan bakiye ile mutabakat gerekir. Model, giriş/çıkış/cache, thinking ve indirimler
değiştiği için sabit token→kredi oranı uydurulmaz.

7 Ekim canlı model anahtarıyla resmî CLI'ın `/api/v1/models/limits` sorgusu Token Plan
origin'inde iki flash modeli için404 verdi. Rapor bunu açık `limits:null` olarak tutar;
kredi bakiyesi `console_auth_required/balance:null`. Model anahtarı yönetim oturumu
yerine geçmez. Kredi API bağlama ve otomatik yeterlilik tahmini bu yönetim erişimi olmadan
tamamlanmış sayılmaz. [Qwen yönetim sayfası](https://home.qwencloud.com/), Token Plan
abonelik/kullanım ayrıntıları; [resmî CLI](https://github.com/modelstudioai/cli), console
auth gerektiren `usage token-plan` ve `quota check`.

7 Ekim resmî [Qwen Personal plan belgesi](https://docs.qwencloud.com/token-plan/personal/token-plan-personal-overview)
aylık kredi havuzu/abonelik döneminde reset bildiriyor; 5 saat/hafta anlatımı güncel değil.
Belge Personal planın özel uygulama backend'i ve otomatik batch işler için kullanımını
yasaklıyor. Mevcut hesabın planı/uygunluğu doğrulanmalı; uygun ticari API'ye geçiş yeni
ücretli altyapı kararıdır, otomatik geçiş yapılmaz.

7 Ekim son kullanıcı yönüyle limitler: free10/pro100 kurulum başına günlük Asistan isteği;
global ve IP100000/gün (1000*100). Önceki pilotglobal300 kaldırıldı. Soru, kriter oluşturma ve ilan
yardımı bu havuzu paylaşır; liste okuma/filtreleme/favori bunun dışında. Kurulum anonim
uygulama örneğidir, kişi değildir; yeniden kurulum ayrı kimlik oluşturabilir. Free15
önerisi yerine son kullanıcı10 isteği istedi. Uygulama limitleri 1000 Pro'nun100'er isteğini
kesmez; sağlayıcı kredisi/Free altyapının100000 çağrıyı taşıdığı doğrulanmadı. IP tavanı
paylaşımlı ağdaki kullanıcıların kişisel haklarını kesmeyecek şekilde aynı ölçeğe çıkarıldı.

1000 günlük aktif kullanıcı için talep hesabı (kullanım varsayımı, kredi hesabı değil):

| Senaryo | Asistan isteği/gün | Yaklaşık2000token/istekte toplam |
|---|---:|---:|
| Ortalama3 soru/kullanıcı |3000|6Mtoken/gün|
| Ortalama5 soru/kullanıcı |5000|10Mtoken/gün|
|1000free, herkes10 hakkını kullanır |10000|20Mtoken/gün|
|900free+100Pro, herkes tüm hakkını kullanır |19000|38Mtoken/gün|
|1000Pro, herkes100 hakkını kullanır |100000|200Mtoken/gün|

2000token başlangıç tahmini6 Ekim kayıtlı67245token/34 bütçeli istek≈1978'den yuvarlandı;
tam provider maliyet ölçümü veya üretim kullanıcısı davranışı değildir. Uzun ilan/sohbet
bağlamı tokenı artırır; günlük/aylık kredi harcaması token→Credits mutabakatıyla hesaplanmalı.
Ayıklama ayrı bütçedir, aynı ilanın çıktısı1000 kullanıcı için1000 kez üretilmez.
294 Worker test PASS:1000 farklı Pro kimliği, aynı IP, kişi başına100 toplam100000 sahte
model yanıtı;101. kişisel istek ve11. free engellenir. Bu yük testi yalnız yerel sayaç akışıdır;
gerçek sağlayıcıya çağrı yapılmadı, Cloudflare/FCM kapasite kanıtı değildir.

Queue3000 kişi başı değil, tüm source/extract/match/send işlerinin günlük toplamıdır.
Cloudflare Free10.000 Queue operasyonu/gün; normal mesaj yaklaşık3 operasyon, bu nedenle
3000 koruma tavanı. Aynı görev birkaç alıcıyı işler. Çevrimdışı fanout modelinin ~7996
bildirim/gün sonucu tek ilan/senaryo içindir; üretim kapasitesi/SLA garantisi değildir.
6 Ekim canlı Queue3000 tavanına ulaştı; 7 Ekim raporunda04:55UTC451 görev vardı.

[FCM ücretsizdir](https://firebase.google.com/pricing); [varsayılan HTTPv1 proje kotası](https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas)
600.000 mesaj/dakika. Hesabın gerçek kotası Google Cloud → APIs & Services → Firebase
Cloud Messaging API → Quotas & System Limits'ten görülür. FCM kabulü cihaz teslimi değildir.
Mevcut dar boğaz FCM'den önce Cloudflare CPU/D1/Queue ve gerçek sağlayıcı kredisi olabilir.
Workers Free100k istek/gün; D1 Free5M satır okuma/100k yazma/gün. Kotalar hesap genelinde
paylaşılır; kaç kullanıcı kaldırdığı açılış/sync/soru ve bildirim sıklığına bağlıdır.
