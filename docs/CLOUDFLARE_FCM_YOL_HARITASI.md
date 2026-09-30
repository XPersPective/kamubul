# KamuBul — ücretsiz altyapı ve kişisel bildirim yol haritası

30 Eylül 2026. Durum: inceleme ve tasarım önerisi; uygulama/deployment talimatı değildir.
Kullanıcının öncelikleri: ücretsiz servisler, hesap açmadan kullanım, profil ve
kayıtlı aramaya göre listeleme, uygulama kapalıyken yeni ilan bildirimi.
Başka modelin verdiği metin tasarım girdisidir; bütünüyle kabul edilmiş hedef değildir.

## 1. Öneri ve servis isimleri

Öneri: **Cloudflare Workers + D1 + mevcut sqflite + Firebase Cloud Messaging (FCM)**.
Cloudflare merkezi ilan toplama, API ve eşleştirme yapar; FCM bildirimi taşır.
Firestore Google'ın veritabanıdır, bildirim servisi değildir. Kullanıcının
“Cloud Fire” ifadesi Cloudflare, “Google bildirim servisi” ifadesi FCM olarak
yorumlandı. Firestore gerçekten ayrıca isteniyorsa bu servis seçimi yeniden
değerlendirilir; bu incelemede sessizce üçüncü veritabanı eklenmez.

Hesap ekranı gerekmez. Ancak kişiye özel kapalı-uygulama bildirimi için sunucu
hangi **uygulama kurulumunun** hangi aramaları takip ettiğini bilmelidir.
Kişi hesabı yerine, yalnızca o kuruluma ait güvenli kayıt kullanılır.

Ücretsizlik kullanıcı sayısıyla garanti edilemez. Kota dolunca gecikme veya
geçici servis kesintisi kabul edilerek ücretli plana otomatik geçiş yapılmaz.
İlk sürüm ücretli AI gerektirmez: mevcut deterministik çıkarıcılar korunur.

## 2. Kodla doğrulanan mevcut durum

İnceleme tabanı: yerel `f5da875`; başlangıçta çalışma ağacı temizdi. GitHub
kontrolünde diğer ajanın `origin/master:346863e` çalışması bulundu ve okundu.
Son değerlendirme bu yeni kodu kapsar; eski yerel taban nihai mevcut durum değildir.
Önce PROJECT_BRAIN.md ve Project Brain protokolü, ardından ilgili akışlar okundu.

| Parça | Bugünkü gerçek durum | Sonuç |
| --- | --- | --- |
| Mobil | Flutter, Android/iOS; kullanıcı hesabı yok; backend kodu var, dağıtılmış olduğu doğrulanmadı | Girişsiz deneyim korunabilir |
| Yerel veri | `lib/data/listing_store.dart`: sqflite, şema v4; ilan URL'i anahtar, summary eklendi | Drift/ikinci yerel DB gerekmez |
| İlan toplama | `catalogue_refresh.dart`: KAMUBUL_API verilirse uzak snapshot; kaynak bazında telefondan fallback | Merkezi veri yolu mevcut, ücretsiz platform uyarlaması yeni iş |
| Kayıtlı arama | `SavedSearch`: ad + JSON filtreler; onboarding “Sizin için” araması oluşturur | Etiketler mevcut filtre kümeleridir |
| Filtreler | `packages/kamubul_core/lib/data/search_alerts.dart:matchesFilters`: başlık, kategori, son30, şehir, yaş, eğitim, KPSS türü | Dart app/backend aynı çekirdeği kullanıyor |
| KPSS | P3/P93/P94 gibi tür eşleşmesi; çıkarıcı puan bulabiliyor ancak ListingRecord ve kayıtlı profil puan karşılaştırması taşımıyor | Puan desteği tamamlanmalı |
| Profil vurgusu | `home_page.dart`: adı “Sizin için” olan aramadan türetiliyor | Yeniden adlandırmaya dayanıklı rol/kimlik gerekli |
| Ayrıntılar | Mobil ayrıntı ve `backend/lib/src/pipeline.dart` içinde bounded merkezi ayrıntı/kanıt hazırlama | Hazır olmayan koşullar için push sırası doğrulanmalı |
| Bildirim | Local Workmanager yanında FirebasePush, PushRegistrar, planDevicePush ve FCM HTTP v1 gönderici var | Gerçek FCM ve cihaz teslimi henüz doğrulanmış değil |
| Mevcut tercihler | Arama başına instant/digest/off; 22–08 sessiz saat, günde 6 anlık sınır, kuyruk/geçmiş; kaydedilen ilan için 3 gün hatırlatma | İş kuralları korunup merkezi akışa uyarlanmalı |
| Dokunuş | Yerel ayrıntı; kayıtta yoksa resmî URL; soğuk açılış köprüsü var | jobId + URL ile genişletilebilir |
| Çıkarım | Ortak Dart çekirdeğinde parser/kanıt testleri ve opsiyonel Anthropic/OpenAI/Gemini AI var; AI varsayılan kapalı | Ücretsiz sürüm deterministik çalışmalı |
| Firebase/Cloudflare | Firebase SDK eklenmiş; Dart backend Firestore veya dosya storage ve Cloud Run/VPS deployment tarifli; Worker/D1 yok | Mevcut cloud tarifi sıfır maliyet şartıyla aynı değil |
| Uzak sync | snapshot v1, ETag/304, boyut/timeout kontrolü, local merge ve testler var | Baştan repository yazmak yerine mevcut sözleşme genişletilmeli |
| Kurulum kaydı | Rastgele cihaz id/secret; sunucuda SHA-256, opt-in ve offline silme/retry var | Baştan kimlik sistemi kurulmaz; secure storage ve yarışlar incelenir |

Kaynak kapsamı: Kariyer Kapısı ve SBB adaptörleri mevcut. Yeni ortak çekirdek
refactor'unda Resmî Gazete kapsamdan çıkarılmış; eski sıfır-yield adaptörü artık yok.
İŞKUR ve ilan.gov.tr erişim engelleri kayıtlı;
belediye adaptörü yok. Önceki canlı kontroller 28 Eylül tarihli; bu inceleme canlı
kaynak erişimini yeniden test etmedi. Kaynak defteri `docs/SOURCE_REGISTRY.md`.

### Geçişten önce ele alınacak sınırlar

- Yaş şu an sadece üst yaş sınırıyla kıyaslanıyor; alt sınır ve ilandaki esas
  alınan tarih yok. Bu eşleşme başvuruya kesin uygunluk anlamına gelmez.
- Şehir yapılandırılmış yerle eşleşiyor; kurum adı şehir kanıtı sayılmıyor.
  Merkezi serviste şehir kanıtı ayrıntıdan veya resmî şehir sorgusundan alınmalı.
- Bir ilandaki farklı pozisyonların eğitim/KPSS/şehir koşulları birbirine
  karıştırılmamalı: aynı pozisyon tüm seçili koşulları karşılamalı.
- Bilinmeyen koşul bugün sıkı filtrede eleniyor. Bunu örtük biçimde “uygun”
  yapmayacağız; kullanıcıya eksik veri nedeniyle kapsamın daraldığını göstereceğiz.
- Mevcut fingerprint kurum + tarih temelli sezgiseldir. Aynı kurum aynı gün
  farklı ilanlar açabilir; küresel UNIQUE anahtarı olarak kullanılmamalı.
- Bildirim görünürlüğü arama başına hesaplandığından, birden çok aramaya uyan
  ilan farklı aramalardan tekrarlanabilir. Merkezi tekilleştirme kurulum bazında olmalı.
- Sayaçlar günün numarasını tutuyor; tam tarih ve zaman dilimiyle değiştirilmeli.
  Yeni server instant sayacı tam tarih kullanıyor; digest hâlâ gün numarası.
  Mevcut digest davranışı sabit 18:00 gönderimi garantilemiyor.
- iOS native arka plan/push yapılandırması ve izin akışı tamamlanmış sayılmaz;
  mevcut izin fonksiyonu Android sonucunu döndürüyor. Önceki cihaz doğrulama
  sınırlamaları PB-004'te kayıtlı; FCM gerçek cihaz testi ayrıca gerekli.

### Diğer ajanın işinden alınacaklar ve gözlenen açıklar

`packages/kamubul_core/` parsers, modeller, snapshot/client, eşleştirici,
device registration ve push planner içeriyor. `backend/` API/storage/pipeline/
FCM katmanlarını; Flutter remote_sync/push_setup bunların mobil bağlantısını içeriyor.
Bunlar silinip yeniden yazılmamalı. PB-010..015 gerçek deploy, kaynak/FCM,
uygulama bağlantısı ve release kontrollerinin açık olduğunu kaydediyor.

Önemli uyumsuzluk: `backend/README.md` Cloud Run + Scheduler + Firestore için
Blaze planına geçiş öneriyor. Bu yol ücretsiz kullanım kotası içerebilir ama
ücretlendirmeye açık plan olduğu için yeni “tamamen ücretsiz” şartını karşılayan
varsayılan deployment olarak kabul edilemez. Bu tarifi uygulamadım.

Gözlenen teknik açıklar:

- `_notify` bütün cihazları her çalışmada tarıyor, 25 cihazı paralel işliyor.
  Bu, Worker'ın 6 dış bağlantı ve 50 dış istek sınırına doğrudan taşınamaz.
- `_notifyDevice` FCM gönderiminden sonra cihaz durumunu yazıyor; gönderimden
  sonra kesilme tekrara, cihaz hata alıp global pendingPush temizlenmesi kayba
  yol açabilecek sınırdır. Kalıcı kurulum/olay outbox ve claim gerekir.
- `planDevicePush` aramaların sonuçlarını topluyor; aynı URL'yi aramalar
  arasında tekilleştirmiyor. Kuyruk 50 kayıtla sınırlı; taşanı sessiz kaybetme
  politikası yerine açık durum/saklama kuralı gerekir.
- Flutter'da `onMessage` ön plan işlemi ve özel inbox/history eşitlemesi yok;
  tap ve token refresh bağlanmış. Eski local üreticiyle çift bildirim kapısı gerekli.
- Kurulum sırrı `SettingsStore` köprüsünde; secure storage'a taşınması önerilir.
- Snapshot full merge mevcut; sequence delta/tombstone protokolü henüz yok.
  RemoteCatalogueClient ETag destekliyor ama mobil sync çağrısı ETag'i henüz
  vermiyor; yeteneğin varlığı ile uçtan uca 304 kullanımını ayırmalıyız.

Mevcut backend **Dart native/Docker**; Cloudflare Workers'a imaj yüklenerek
çalıştırılamaz. Ücretsiz fizibilitenin bir kapısı dil/runtime uyarlamasıdır.
Önce saf çekirdeğin Workers uyumlu çıktı üretme olanağı küçük deneyle ölçülür;
dart:io ve package bağımlılıkları nedeniyle uyum varsayılmaz. Uyum yoksa sadece
gerekli ingest/eşleştirme Worker kodu TypeScript'e taşınır, aynı fixtures ile
parite kontrol edilir. Bu taşımanın bakım maliyeti raporlanmadan tam port yapılmaz.

## 3. Uyarlanmış veri akışı

```text
Resmî kaynaklar → Cron → sınırlı getirme/ayrıntı/çıkarım → D1 katalog
                                                        │
                          ┌─────────────────────────────┴─────────────┐
                          ▼                                           ▼
                   Public Worker API                    kayıtlı aramayla eşleştir
                          │                                           │
                          ▼                                           ▼
                 Flutter mevcut sqflite                  kalıcı bildirim işleri
                          │                                           │
                          ▼                                           ▼
                kişisel liste/yerel filtre              küçük gönderim grupları
                                                                      │
Flutter → kurulum kaydı + bildirim tercihleri → Worker/D1              FCM
                                                                      │
                                                   işletim sistemi → Flutter
```

Katalogda D1 yetkilidir. Favoriler ve kişisel yerel verinin asıl kaydı cihazdır.
Sunucudaki arama kopyası push aboneliğidir; cihazdan sürümlü olarak güncellenir.
FCM olay uyarısı taşır; ilan verisinin güvenilir eşitleme kanalı değildir.

## 4. Giriş olmadan kurulum ve tercih yönetimi

1. Bildirim açıklaması ve izin sonrasında kurulum kaydı oluşturulur; ret halinde
   katalog, yerel kişiselleştirme ve favoriler çalışır.
2. Sunucu rastgele, tahmin edilemez kurulum kimliği ve yalnızca o kaydı yöneten
   yüksek entropili kurulum erişim belirteci üretir. D1'de belirtecin hash'i,
   telefonda Keychain/Android güvenli depoda aslı tutulur. UUID tek başına yetki değildir.
3. FCM token ayrı bir teslim adresidir; kullanıcı kimliği veya API parolası değildir.
   Başlangıç/yenilemede değişen token aynı kuruluma bağlanır; eski token devre dışı kalır.
4. Bildirim açık aramaların filtreleri, stabil searchId, tercih sürümü, bildirim
   modu, sessiz saatler, zaman dilimi ve günlük sınır gönderilir. Arama adı ve
   doğum tarihi gereksizse cihazda kalır; eşleşme için gereken yaş/puan dahil
   alanların aktarımı kullanıcıya açıkça anlatılır.
5. Tercihler önce yerelde kaydedilir; çevrimdışı değişiklikler bağlantıda gönderilir.
   Eski sürüm yeni sürümü ezemez. Sunucu onayı gelene kadar “eşitlenmeyi bekliyor”
   durumu gösterilir; sunucu henüz eski tercihle gönderebilir.
6. Arama silme/off değişikliği bekleyen işleri iptal eder; gönderim öncesinde
   güncel preferenceVersion tekrar kontrol edilir. FCM'ye verilmiş mesaj geri alınamaz.
7. “Bildirim verilerimi sil” kurulumun token/abonelik/geçmişini kaldırır. Uygulama
   silinirken ağ çağrısı garantili olmadığından geçersiz token ve yaşlanan kayıtlar
   planlı temizlenir. Yeniden kurulum yeni kayıt olabilir; otomatik cihazlar arası
   hesap eşitlemesi vaat edilmez. Mevcut dışa/içe aktarma korunur; kimlik sırları yedeğe girmez.

Mevcut rastgele id/secret + hash modeli önerinin temelidir; sunucu üretimli
kimliğe geçiş zorunlu değildir. Önce mevcut PUT/DELETE sözleşmesi korunur.
Öneri Firebase Auth kullanmadan kurulum yetkilendirmesidir. Firebase anonim Auth
alternatif olarak giriş ekranını kaldırır ama üçüncü bir Firebase servisi ve
anonim hesap yaşam döngüsü ekler; bu sürümün zorunlu parçası değildir.
Kurulum belirteci sahte kurulum açılmasını tek başına engellemez: kayıt kotası,
IP/kurulum hız sınırı ve ölçek aşamasında doğrulanmış uygulama kanıtı değerlendirilir.
FCM token sahipliği için kayıt sonrası uygulamaya doğrulama mesajı/nonce akışı
pilot sırasında ölçülür; başka tokenı bağlama veya taşıma yalnızca tokenı bilerek yapılamaz.

## 5. Kişiselleştirme sözleşmesi

“Etiket” = kullanıcının verdiği adla saklanan filtre grubu; etiketin adı
kendiliğinden anahtar kelime değildir. Serbest anahtar kelime özelliği ayrıca
seçilirse `keywords` açık bir alan olur; mevcut `q` başlık aramasından ayrılır.

Arama içindeki koşullar **VE**, farklı aramalar **VEYA** olarak birleşir.
İlan üç aramaya uyarsa bir kez bildirilir; eşleşen arama kimlikleri olayda tutulur.
Yeni kaydedilen arama mevcut ilanları hemen listeler; ilk kurulum/arama oluşturma
tarihinden önceki ilanlar topluca “yeni” diye gönderilmez. Kullanıcı isterse
geçmiş eşleşmeleri ayrı bir sonuç/özet ekranından görebilir.

Örnek: Ankara + lisans + 29 yaş + P3/72 → Ankara'daki aynı pozisyon lisans
kabul ediyor, yaş koşulu karşılanıyor, P3 tabanı 70 ise eşleşir; taban 75 ise
eşleşmez. Puan türü farklıysa karşılaştırma yapılmaz. KPSS şartı yok bilgisi
ile KPSS alanı bilinmiyor bilgisi farklıdır; KPSS'siz ilan tercihi açıkça tanımlanır.

Önerilen sonuçlar: `match`, `no_match`, `unknown`. Kesin filtre ve otomatik
push için `match`; eksik bilgi isteyen kullanıcıya “Koşulları kontrol edin”
başlığı altında `unknown` sonuçları ayrı sunulur. İlandaki yaş hesabı referans
tarihine dayalıysa yalnızca yaş sayısıyla kesin sonuç üretilmez. Eğitim hiyerarşisi
ve bölüm denkliği tahmin edilmez. Süresi bitmiş ve yayın günü gelmemiş ilanlar
yeni-ilan push'ına girmez; favorilerde tarihsel olarak kalabilir.

İlk geçişte bugünkü destekli filtreler korunur. KPSS puanı, alt yaş/referans tarih,
çoklu pozisyon ve kurum/unvan/ilçe/özel kontenjan filtreleri yeterli kanıt verisi
oldukça eklenir; ekranda olup gerçekte çalışmayan filtre sunulmaz.
Mobil ile mevcut Dart backend aynı çekirdeği zaten paylaşır. Worker'a dil
taşıması gerekirse aynı sözleşme ve ortak JSON örnekleriyle
doğrulanır. Dart işlevi TypeScript'te doğrudan kullanılamaz; iki uygulama aynı
veri örnekleriyle aynı sonucu vermelidir. Yeni genel kural motoru gerekmez.

## 6. Uygulama açık/kapalı davranışı

| Durum | Tasarlanan davranış |
| --- | --- |
| Açık | FCM olayıyla bounded sync, liste ve bildirim merkezi güncelleme; aynı olay için tek sunum |
| Arka planda/normal kapalı | `notification + data` payload işletim sistemi bildirimi; dokununca ilan ayrıntısı |
| Çevrimdışı | Yerel ilanlar görünür; bildirimin TTL süresinde gecikmeli teslimi mümkün |
| İzin kapalı | Görünür push yok; açılışta normal sync ve kişisel liste çalışır |
| Force-stop/OS kısıtı | Teslim ve arka plan çalışması garanti edilmez; açılışta eksikler tamamlanır |

Payload küçük tutulur: eventId, jobId, catalogueVersion, type; başlık/kısa metin.
Yaş/puan/profil payload'a yazılmaz. Kilit ekranında genel bildirim seçeneği
düşünülür. Sessiz saat ve günlük sınır sunucuda uygulanır; cihaz kapalıyken
yerel eşleştirmeye güvenerek herkese görünür bildirim gönderilmez.
FCM kabulü telefonun gördüğünü kanıtlamaz; `accepted` ile `read/opened` ayrılır.
Data-only push ile garantili arka plan filtreleme/senkronizasyon vaat edilmez.
[Flutter alım davranışı](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

Mevcut local notifications ön plan sunumu ve yerel deadline hatırlatması için
kullanılır. Aynı yeni ilanı hem Workmanager hem FCM bildirmemeli; merkezi moda
geçen kurulumda eski yeni-ilan üreticisi kapatılır. Sunucudan alınan olaylar
yerel geçmişe eventId ile UPSERT edilir. Normal açılışta özel inbox endpoint'i
kaçırılan olayları getirir; FCM tek başına geçmişi tamamlayamaz.

## 7. En küçük sunucu veri modeli ve API

Bu bir D1 şema önerisidir; migration/SQL uygulaması henüz yapılmaz. Var olan
Storage/DeviceRegistration/Snapshot modelleri alan ve API uyumluluğu için esas alınır.

| Tablo | Amaç ve temel anahtar |
| --- | --- |
| sources | kaynak, cursor/ETag, parserVersion, son başarı/hata, nextDueAt |
| jobs | stabil id, durum, tarihler, kurum, kaynak kanıtı, contentHash, revision |
| job_origins | jobId + sourceId + externalId veya canonicalURL; kaynağa özgü UNIQUE |
| job_positions | yalnızca çoklu pozisyon gerçekten gerektiğinde; koşul bütünlüğü |
| catalogue_changes | artan sequence, jobId, upsert/inactive/delete; bounded saklama |
| installations | id, credentialHash, token, platform, izin/aktif, timezone, tercih sürümü |
| saved_searches | installationId + searchId, doğrulanmış filters, mode, startsAt |
| notification_outbox | installationId + jobId + eventType için UNIQUE; attempt, nextAttemptAt, lease, durum |
| notification_batches | günlük özet kimliği, tarih/kurulum, içerdiği olaylar; yalnızca digest için |
| sync_runs | kaynak çalışması, sayılar, süre, hata; sınırlı saklama |

Özet ve yeni-ilan tekilleştirmesi, liste revizyonunu körlemesine anahtara eklemez:
küçük ilan güncellemesi yeniden “yeni ilan” üretmez. Gerekli büyük değişiklik
bildirimi ayrı eventType/politikadır. Tam inbox/outbox her arama başına çoğaltılmaz.
Gönderilmiş kayıt saklama penceresi ve arşivleme/özetleme depolama ölçümüyle belirlenir.

İlk indeksler: jobs(active, publishedAt, id), changes(sequence),
origins(sourceId, externalId), searches(installationId), outbox(status,nextAttemptAt),
outbox(installationId,createdAt). Şehir/kategori aday indeksleri gerçek sorgularla
ölçülür; her olası filtreye indeks eklenmez. D1 okuma satır taramasıdır; indeks
yazmaları da kota tüketir. [D1 fiyatlandırma](https://developers.cloudflare.com/d1/platform/pricing/).

| Endpoint | Sözleşme |
| --- | --- |
| GET /api/v1/meta | katalog sürümü, şema sürümü, kaynak tazeliği; ETag |
| GET /api/v1/jobs | aktif liste, en fazla 50, stabil cursor; ortak public cache |
| GET /api/v1/jobs/{id} | ilan + kanıt/pozisyonlar; expired/removed durumu açık |
| GET /api/v1/jobs/sync?after=… | sequence sıralı değişimler, nextCursor, hasMore, snapshotVersion |
| POST /api/v1/installations | sınırlı kayıt ve kurulum yetkisi |
| PUT /api/v1/installations/me/preferences | tam tercih kopyası, sürüm ve boyut sınırı; yetkili |
| PUT /api/v1/installations/me/token | token/izin güncelleme; yetkili |
| GET /api/v1/installations/me/inbox | olay cursor'u; yetkili, private/no-store |
| DELETE /api/v1/installations/me | kurulumun bulut verisini sil; yetkili |

Bu endpoint listesi hedef sözleşme taslağıdır; mevcut `/v1/listings.json`,
`/v1/sources.json`, `/v1/health`, `PUT|DELETE /v1/devices/{id}` korunarak başlanır.
Yeni `/api/v1` adı için istemciyi sebepsiz kırmayız; sync/inbox ekleri mevcut
versiyonda veya uyumluluk yolu ile açılır. Mevcut devices/{id} için secret/id
eşleşmesi sunucuda kontrol edilir; başka kaydı seçmek yetki vermez.
Yeni özel uçlarda belirteç sahibi sunucuda türetilir.
Public filtreler allowlist; SQL parametreli; internal ingest/send public API değildir.
Mevcut `backend/` Dart projesi yerinde korunur. Runtime fizibilitesi TypeScript
gerektirirse ayrı küçük `workers/` projesi ve D1 migrations eklenir; mevcut Dart
klasörüne TypeScript dosyaları karıştırılmaz. Mikroservis yok.

## 8. Güvenilir toplama, gönderme ve sync

### Toplama

Mevcut Dart pipeline davranışını esas alarak önce yalnızca Kariyer Kapısı.
Listeyi getir, source identity ile tekilleştir,
değişen içeriği hash ile belirle; ayrıntıları sınırlı iş olarak hazırla. Parser
başarısızlığı kayıtları silmez. ETag/cursor ancak kaynak gerçekten destekliyorsa
kullanılır; bugünkü adaptörlerde varmış gibi kabul edilmez. Yeni ilanlar önce
ham/pending kaydedilir; hazır ve kanıtlı alanlar oluşunca eşleştirme yapılır.
Eksik ayrıntı daha sonra tamamlanırsa henüz bildirilmemiş eşleşme değerlendirilebilir.

Katalog değişikliği ve iş planı transaction/batch sınırında tutarlı kaydedilir.
FCM çağrısı commit sonrasıdır. İlk yükleme bütün eski ilanları bildirime dönüştürmez.
Kaynaklar arası birleştirme ancak güçlü ortak kaynak/başvuru/pozisyon kanıtıyla;
şüpheli eşleşme ayrı kalır. Tek crawl'da görünmemek silinme kanıtı değildir.

### Bildirim gönderimi

FCM HTTP v1 ve kısa ömürlü OAuth token; service-account private key yalnızca
Worker Secret. Her cihaz gönderiminde OAuth yeniden üretilmez; kısa ömürlü
token yeniden kullanılır, gerektiğinde yenilenir. JWT imzalama ve parse CPU'su
ücretsiz Worker üzerinde ölçülür. [FCM yetkilendirme](https://firebase.google.com/docs/cloud-messaging/send/v1-api).

Outbox'tan lease ile küçük grup al; güncel abonelik, izin, ilan durumu,
sessiz saat/tavan kontrolü yap; gönder; FCM kabulü/hatasını kaydet. Timeout ve
429/5xx için Retry-After + jitter/backoff, deneme/tarih sınırı; kalıcı hatalarda
retry durur. Geçersiz token temizlenir; INVALID_ARGUMENT tek başına tokenı
silme nedeni değildir, payload da hatalı olabilir.
[Token bakımı](https://firebase.google.com/docs/cloud-messaging/manage-tokens).

**Tam “exactly once” garanti edilemez:** FCM kabul ettiğinde Worker sonucu
kaydetmeden kesilebilir. Stable eventId, cihaz/history tekilleştirmesi, lease
ve platform bildirim kimlikleri tekrar riskini azaltır; özellikle OS'nin
otomatik sunduğu background bildirimi için sıfır tekrar iddiası yapılmaz.
Günlük tavan sayaçları paralel çalışanlarda atomik tutulur; tarih YYYY-MM-DD
ve kullanıcının zaman diliminden hesaplanır. Birden çok arama tek günlük sınırı paylaşır.

Genel `all_jobs` görünür topic kullanımı kişiselleştirme gereksinimini karşılamaz.
Kategori/şehir topic'leri karmaşık VE koşullarını karşılamaz; yalnızca kullanıcı
açıkça genel duyuru isterse kullanılabilir. Kişisel push sunucuda eşleşmiş tokena gider.
Topic adlarına yaş/puan gibi profil verisi kodlanmaz.
[FCM topic davranışı](https://firebase.google.com/docs/cloud-messaging/topic-messaging).

### Eşitleme

Mevcut sqflite korunur; remote snapshot/delta kaynağı `refreshCatalogue` akışına
bağlanır. API alanları için migration stabil jobId, sequence, active ve kanıtları
ekler; URL → jobId eşlemesi favorileri ve eski tap yollarını korur.
Katalog upsert'i local saved/savedAt ve aramaları değiştirmez.

İlk sync aktif ilanları stabil snapshot üzerinden sayfalar. Sonraki sync yalnızca
değişimleri getirir; inactive/deletion ile silinen kayıt hayalet olarak kalmaz.
Bir sayfanın kayıtları ve checkpoint aynı SQLite transaction'ında yazılır;
son sayfaya gelmeden global sürüme atlanmaz. Kesilen işlem yeniden çalışabilir.
Delta saklama penceresinin gerisindeki cursor için full-resync gerekir; favoriler korunur.
İlan detayının kaldırılması, favorinin kullanıcı bilgilerini silmez.

Kişisel liste ilk sürümde cihazdaki aynı filtreyle hesaplanır; her filtre
dokunuşunda sunucu sorgusu gerekmez. Sunucu push için aynı sözleşmeyi kullanır.
Cache yalnızca public ortak cevaplarda; özel inbox ve tercihler cache'lenmez.
ETag, kısa TTL ve sürümlü anahtarlar kullanılır. Worker cache HIT de Worker
çağrı kotasını tüketir; Cache API içeriği veri merkezleri arasında otomatik
çoğaltılmaz. Cron cache silmesi küresel invalidation sanılmaz.
[Cache API](https://developers.cloudflare.com/workers/runtime-apis/cache/).

## 9. Ücretsiz kapasite ve uygulanabilirlik sınırı

Resmî belgeler 30 Eylül 2026'da kontrol edildi; yayından önce tekrar doğrulanır.

| Hizmet | Ücretsiz sınır | Tasarıma etkisi |
| --- | --- | --- |
| Workers | 100.000 istek/gün; HTTP ve Cron için 10 ms CPU; 50 dış subrequest/çağrı, 6 eşzamanlı dış bağlantı | Küçük işler, parse/crypto ölçümü; tek çalışmada 10.000 token gönderimi yok |
| D1 | 5 milyon okunan satır/gün, 100.000 yazılan satır/gün; toplam 5 GB, tek DB 500 MB | Sorgu ve saklama bütçesi, indeks maliyeti |
| Queues | 10.000 işlem/gün; genelde mesaj başına 3 işlem, ücretsiz retention 24 saat | Cihaz başına queue mesajı kota tüketir; kalıcı asıl iş kaydı D1 |
| FCM | Ücretsiz | Teslim/izin/kota/platform sınırlamaları devam eder |

Kaynaklar: [Workers sınırları](https://developers.cloudflare.com/workers/platform/limits/),
[D1 sınırları](https://developers.cloudflare.com/d1/platform/limits/),
[Queues fiyatlandırma](https://developers.cloudflare.com/queues/platform/pricing/),
[Firebase fiyatlandırma](https://firebase.google.com/pricing/).

İlk prototip D1 pending/outbox + sınırlı Cron ile yapılabilir. Her dakika
yaklaşık 30 cihaz gönderimi yalnızca teorik 43.200 gönderim/gün tavanı verir;
CPU, retry ve diğer işlerden dolayı gerçek kapasite düşüktür. 10.000 cihaza
tek tur yaklaşık 334 dakika sürebilir. Bu model geniş eşleşmeli ilanlar için
hızlı teslim hedefini tek başına karşılamaz.

Bu nedenle pilot kapısı: küçük **gönderim gruplarını** Queues ile uyandırmayı
ölçmek. Örneğin 30 hedefli grubun tek queue mesajı olması, cihaz başına mesajdan
daha az queue işlemi tüketir; grup içi checkpoint ve outbox kalıcı kalır.
Queue retry'ı tüm başarılı hedeflere yeniden gönderim yapmamalı. Queue kaybı/
24 saat aşımı Cron ile D1'den onarılır. Bu ek hizmet ölçüm ihtiyacıyla eklenir;
ücretsiz sınırlar içinde kalacağı peşinen varsayılmaz.

**10.000 kullanıcı senaryosu (ölçüm değildir):**

- Günde 2 açılış × açılış başına 2 API isteği = 40.000 çağrı. Ayrıntı, inbox,
  kayıt, sync sayfaları ve retry buna eklenir. Sık arka plan polling yapılmaz.
- 20 yeni ilan × 3 kayıtlı arama × 10.000 cihaz = kaba 600.000 karşılaştırma.
  Bütün profilleri her Cron'da taramak yerine şehir/kategori adaylarını daralt,
  aramaları sayfala; CPU sınırında işler arası devam et.
- Her cihaza günlük 6 anlık bildirim = 60.000 teslim işi. Her işin planlama,
  claim ve sonuç yazımları, ayrıca indeksler, 100.000 satır yazma sınırını
  aşabilir. Günlük 6 sınırı ücretsiz kapasite taahhüdü değildir.
- Bir günlük özet/cihaz = 10.000 gönderim; bu da CPU, DB ve queue ölçümü ister.
  Hedef, kişiye özel anlık mod + yük artışında açıkça belirtilmiş özet/gecikme
  politikasıdır; instant tercihi sessizce digest'e çevrilmez.

Önerilen işletim bütçesi: paylaşılan hesap tüketimi dahil resmi kotaların
yaklaşık %70'inde uyarı, %85'inde düşük öncelikli işi bekletme; sayaç gecikmesine
karşı rezerv. Worker/D1 hatalarında cache korunur ve push kuyruğu kaybolmaz.
Ücretsiz kotada sınırsız saldırı veya 10.000 kişiye saniyeler içinde kişisel
teslim garantisi verilemez. Limit aşıldığında ücretli geçiş yerine açık servis
durumu ve yeniden deneme uygulanır. workers.dev ile başlangıçta özel alan adı gerekmez.

Firestore alternatifinde ücretsiz 50.000 belge okuma/gün, 20.000 yazma/gün,
1 GiB depolama, 10 GiB/ay çıkış var. 10.000 kişi bir kez 30 ilan okursa
300.000 belge okuması olur; doğrudan tüm listeyi her telefona okutmak uygun değil.
Firestore tek başına kişisel push göndericisi değildir. D1 + Firestore birlikte
ilk sürümde gereksiz çift veri/iki sync sorunu oluşturur.
[Firestore kotaları](https://firebase.google.com/docs/firestore/quotas).

“Ücretsiz” burada işletim servisleri içindir; iOS push için APNs yapılandırması
ve mevcut Apple geliştirici/cihaz gereksinimleri ayrıca vardır. Android ilk
pilot için daha erişilebilir. FCM kurulumu Google Play services ve iOS APNs
hazırlığını içerir. [Platform kurulumu](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

## 10. Başka modelin planından alınacaklar ve revizyonlar

| Alınacak | Revize/ertelenecek |
| --- | --- |
| Merkezi resmî kaynak erişimi, unique kaynak kimliği, hash | Mevcut adaptörler/kanıt testleri esas; tüm kaynaklar çalışıyormuş gibi başlanmaz |
| Worker API, D1 migration, pagination, ETag | Endpoint envanteri gerçek mobil ihtiyaca küçültülür |
| Offline-first, delta, inactive/tombstone | Zaten sqflite var; Drift'e geçiş yok |
| Commit sonrası push, retry, secrets, log | jobId tek başına push tekilleştirmesi yetmez; kurulum/olay bazında outbox |
| Güvenilmeyen dış içerik ve kaynak allowlist | Redirect hedefi, boyut, timeout; CAPTCHA/login aşma yok |
| Kişisel abonelik sistemi | “Sonra yapılacak” değil ilk kişisel push sürümünde zorunlu |
| Queue fikri | Mevcut Dart gönderici Worker'a doğrudan taşınamaz; ücretsiz batch prototipi; R2/DO/KV gerekçe olmadan yok |
| AI hash/maliyet fikri | AI ilk sürümde kapalı; deterministik çıkarım yeterli |
| Ortam ayrımı | Önce local dev + ayrı test Firebase/D1 + prod; gereksiz üçüncü sürekli ortam yok |
| Güvenlik | Her WAF/bot özelliği ücretsiz sanılmaz; endpoint sınırları ve kullanılabilir ücretsiz kurallar |

## 11. Fazlar, kabul ölçütleri ve sıra

| Faz | Yapılacak | Tamamlanma kanıtı |
| --- | --- | --- |
| 0 — sözleşme | Yeni Dart backend/core/FCM temelini koruma; etiket/profile, KPSS puanı, unknown/pozisyon kuralları | Mevcut API ve testlerin haritası, bu tasarımın karara bağlanması |
| 1 — ücretsiz fizibilite | Workers runtime/Dart uyumu veya dar port; Kariyer/SBB erişimi, CPU/crypto/FCM batch | 10 ms/istek ve runtime kanıtı; engeller açık |
| 2 — merkezi katalog | Tek kaynak Kariyer, kaynak kimlikleri, pending ayrıntı, kanıt çıkarımı, migration, bounded Cron | Aynı tur iki kez çalışınca duplicate yok; hata eski ilanları silmiyor |
| 3 — mobil API/sync | Public API, sqflite migration, ilk snapshot/delta, favorite koruma | Offline açılış; yarıda kesilen sync tekrarında veri/favori kaybı yok |
| 4 — kurulum/tercih | Güvenli kurulum kaydı, token/izin, sürümlü aramalar, silme | Başka kurulum verisine erişim yok; offline edit/token yenileme doğru |
| 5 — kişisel push | Match + outbox + bounded sender; gerekli ise Queues batch; history/tap | Aynı ilan çoklu aramada tek olay; açık/kapalı gerçek Android testi |
| 6 — modlar | Tam tarihli günlük sınır, quiet hours/timezone, gerçek günlük digest, local deadline | Gün/ay değişimi, quiet saat, tercih iptali ve cap yarışları doğru |
| 7 — yük ve işletim | 10.000 sentetik kurulum; geniş/dar eşleşme, retry; cache ve kota ölçümü | Kota rezervi, gecikme ve maliyet raporu; ücretli servise bağımlılık yok |
| 8 — yayın kapısı | SBB kapsamı, gizlilik/mağaza beyanı, iOS/APNs; kademeli test dağıtımı | Android release ve Apple gerçek cihaz kanıtı; kaynak şartları ve kapatma yolu |

İlk prototipin başarı ölçütü “sunucu kurulmuş” değildir: aynı filtreli iki farklı
cihazdan yalnızca eşleşene bildirim gitmesi, kapalı cihazın tap ile doğru ilanı
açması ve yerel favorinin migration sonrası korunmasıdır. Daha sonra 100,
1.000 ve 10.000 sentetik kurulumla kapasite doğrulanır; 10.000 gerçek kişiye test
push gönderilmez. Hesap/secret oluşturma ve production dağıtımı bu incelemenin dışındadır.

## 12. Test ve işletim kontrolü

Asgari kontroller: eşleşmede P3/puan sınırı, null/unknown, çoklu pozisyon,
yaş tarihi; yeni aramanın geçmişi bildirmemesi; aynı ilan çoklu arama/kaynak;
iki Cron/consumer yarışı; commit sonrası kesinti; FCM timeout/429/geçersiz token;
token yenileme; sessiz saatlerde timezone ve ay değişimi; off/silme sırasında
bekleyen işler; izin ret/sonradan kapatma; offline/migration/bozuk delta;
snapshot sırasında yeni kayıt ve silinme; eski cursor full sync; bildirim
tap'inde cache boş/ilan kaldırılmış; kayıt spam'ı ve başka kurulum yetkisi.

İlk yerel tabanda beş dosyalık hedefli kontrol çalıştırıldı: search_alerts,
catalogue_refresh, listing_store, alert_tap ve extraction_eval; **43 test geçti**.
Bu, eski yerel tabanın kanıtıdır. Uzak commitler birleştirildikten sonra
**104 ortak çekirdek + 37 backend + 83 Flutter = 224 test geçti**.
Ortak çekirdek ve backend statik analizi temiz. Flutter analyze, diğer ajanın
`test/remote_sync_test.dart:8-9` satırlarında iki unnecessary_import bildirimi
verdi; bu incelemede uygulama/test kodu değiştirilmedi. Birleştirme sonrası
pub get mevcut Firebase/core bağımlılıklarının eksik root lock kayıtlarını tamamladı.
Bunlar canlı bulut mimarisini
kanıtlamaz; yeni canlı kaynak/FCM/yük veya iOS cihaz testi bu aşamada yapılmadı.

Mobilde mevcut testler genişletilir; backend için küçük runnable kontroller ve
aynı JSON eşleşme örnekleri yeterli başlangıçtır. Mevcut test framework'ü
terk edilmez; sırf plan için yeni framework/dependency eklenmez.

Log: sourceId, runId, yeni/değişen ilan sayısı, parser hata oranı, outbox yaşı,
FCM kabul/hata sayısı, p95 CPU/gecikme, D1 rows_read/rows_written, cache oranı.
Token, erişim belirteci, yaş/puan ve private key loglanmaz. FCM servis kabulü
“teslim edildi” diye raporlanmaz. Gerekirse kullanıcı eylemli read/opened kaydı.

Güvenlik: yalnız HTTPS, bounded payload/search sayısı, şema/range doğrulama,
parameterized SQL, source/redirect allowlist, HTML güvenliği, private/no-store,
kurulum başına yetki, registry abuse sınırı, secrets rotasyonu ve veri silme.
Firebase client config ile sunucu private key aynı şey değildir; client config
yetkilendirme yerine kullanılmaz. KVKK/gizlilik metni ve mağaza veri beyanları
bildirim için sunucuya aktarılan alanları doğru yansıtır.

## 13. Uygulamaya geçmeden açık kalan kararlar

- Servis isimleri: bu belge Cloudflare + FCM önerisidir; Firestore ayrıca talep
  edilirse DB seçimi netleştirilmeli.
- Eksik koşullu ilanların ayrı gösterimi ve puan/çoklu pozisyon kapsamı.
- Ücretsizlik için kabul edilebilir geniş eşleşme teslim süresi; pilot bunun
  rakamını verir. İlan kontrol aralığı ile tüm cihazlara teslim süresi ayrıdır.
- Kaynakların Cloudflare çıkış IP'sine ve kullanım şartlarına uygunluğu. Engel
  halinde kaynak “erişilemiyor” kalır; proxy/ücretli servis veya erişim aşma eklenmez.
- Firebase/Cloudflare proje erişimi, Android network cihazı, iOS APNs/Apple host.

Bu kararların varlığı mevcut incelemeyi eksik bırakmaz; uygulamanın hangi
ölçülebilir kapılarla ilerlemesi gerektiğini belirler. İlk sonraki teknik iş
**ücretsiz Worker üzerinde tek kaynak + FCM gönderici fizibilite deneyi** olmalıdır.
