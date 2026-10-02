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

Eğitim sözlüğü eşleştirme ve aday indeksinde aynı sabit kimlikleri kullanır:
`education:secondary` Lise, `education:associate` Ön lisans/Önlisans,
`education:bachelor` Lisans, `education:master` Yüksek lisans/Yükseklisans,
`education:doctorate` Doktora. `/api/v2/taxonomy` eski `education` label listesini
korur; ek `educationValues` kimlik/label/alias kayıtlarını yayımlar. Kriter ve
katalogdaki eski label değerleri hâlâ kabul edilir; saklanan değerler topluca
yeniden yazılmaz. Tanınmayan eğitim düzeyi unknown olur, strict push üretmez;
aynı kadroda bilinen uygun eğitim alternatifi varsa eşleşir. Üst öğrenim düzeyi
alt düzeyin yerine otomatik geçmez. Meslek/kurum/kategori kimlikleri ve
genel sözlük-version migration henüz tamamlanmadı.

Migration0010 eski eğitim facet'li aktif kurulumlara `*` koruma anahtarı ekler;
sonraki authenticated registry heartbeat ortak kodlarla indeksi yeniden kurar.
Tercih sürümü/effective_after değiştirilmez, abonelik kaybolmaz. Pending/leased
match cursor'ları yeni sıralama için başa alınır; tamamlanmış event'ler tekrar
açılmaz, outbox UNIQUE tekrar kuyruğa almayı önler. Geniş koruma grubunun geçici
ek okuma yükü heartbeat'e kadar sürer; büyük geçişte kapasite ölçülmelidir.

Şehir sözlüğü mevcut Dart81 il listesiyle aynı label'ları kullanır; native
contract kontrolü iki listenin birebir eşitliğini doğrular. `city:istanbul`,
`city:ankara`, `city:igdir` gibi ID'ler ve Türkçe/ASCII/case label'ları aynı il
anahtarına gider. İlçe/"Merkez"/bilinmeyen konumdan il tahmin edilmez; bilinen
uygun alternatif yoksa unknown, strict push yok. Aynı kadroda kanıtlı uygun il
alternatifi varsa match; başka kadronun ili taşınmaz. UI kodları label gösterir,
eski düz metin yazımlarını değiştirmez; kayıtta toplu wire rewrite yapılmaz.
Taxonomy version1 yanıtına additive `cities` ve `cityValues` eklenir; diğer
alanlar uyumlu kalır, yeni dictionary major/wire migration hâlâ ayrı iştir.

Migration0013 yalnız eski `cities:city:*` facet sahiplerini wildcard ile korur;
authenticated heartbeat label/ID için aynı eski `cities:istanbul` anahtarını
kurar. Düz label anchor'ları değişmez. Tercih version/baseline ve saved searches
korunur; partial fanout reset, completed event'ler ve outbox dedupe değişmez.
Shared Dart/Worker corpus31 case; bütün81 ID/label ve unknown/district durumları
kontrol edilir. Dictionary/coded-city matching çalışması actual source city
coverage, AI/model kalitesi veya gerçek cihaz push kanıtı değildir.

Model `@cf/meta/llama-3.1-8b-instruct-fp8`, güncel official catalogue'da doğrulandı:
[model](https://developers.cloudflare.com/workers-ai/models/llama-3.1-8b-instruct-fp8/),
[Free allocation](https://developers.cloudflare.com/workers-ai/platform/pricing/).
Gerçek REST pilotu5 girişimde4 HTTP200 aldı; raporlanan179.8903 Neurons ve bir
timeout tüketimi bilinmiyor. Tam iki-parça/birleştirme sonucu doğrulanmadı;
[pilot kanıtı](../docs/AI_MODEL_PILOT.md) ve `tool/eval-ai.js` tekrar komutu içerir.
Model alıntı yanında desteklenmeyen iddia ürettiği için özet text'i yalnız
alıntının birebir içinden kabul edilir; paraphrase/koşul kalite kapısı açık.

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
geniş kitle fanout kapasitesi henüz doğrulanmadı.
Kaynak erişim hataları kaynak sağlığında açıkça görünür; mobil/proxy ile gizlenmez.

Günlük özet İstanbul saat18:00 slotunda (sessiz saat bitişine ötelenebilir),
kurulum başına günde bir FCM mesajıdır. Bir özet en çok10 ilan taşır; kalanlar
sonraki günün özetine dayanıklı kuyrukta kalır, deadline geçmişse expired
olarak kaydedilir. Bu pilot tavanının büyük backlog gecikmesi ölçülecek;
kapasiteyi artırmak ölçülen CPU/D1 bütçesine bağlıdır. Özet, anlık bildirim
kotası sent_count'tan ayrı digest_day ile sayılır. Kurulum send lease'i paralel
Cron'un günlük sınırı aşmasını engeller; digest delivery_id üyeliği retry'da
sabit kalır. FCM timeout sonrası tekrar olabilir, exactly-once vaat edilmez.
Gönderimden önce güncel ilan/strict criteria/off/token tekrar kontrol edilir;
accepted ile cihaz teslimi aynı şey değildir. Android TTL ve APNs expiry
son tarihe/en çok24 saate sınırlanır ([FCM lifespan](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan)).
Cron her dakika tetiklenir; scheduledTime dakika mod3 ile kaynak/AI/expiry,
eşleştirme ve gönderim ayrı slotlarda çalışır. Her aşama üç dakikada bir
ilerler; kaynak polling aralığı30dk kalır. Bu ayrım Free50 D1 sorgu/subrequest
sınırında tüm aşamaların aynı çağrıda birleşmesini önler; gerçek CPU10ms
yük ölçümü yerine geçmez. Kaynak slotunda en çok10 eski ilan tombstone olur; eski AI işi
model çağırmadan superseded, eski match event fanout yapmadan expired olur.
Migration0002–0003 bu kalıcı delivery/lease/digest alanlarını ve indeksleri
kurar. Native SQL/FCM fixture kontrolleri gerçek cihaz teslimi veya Free10ms
CPU kanıtı değildir; prod'a test cihazı/ilan/bildirim yazılmaz.

Migration0004 kurulum adaylarını `(key,installation_id)` covering indeksiyle
tutar. Her arama şehir/meslek/eğitim/kurum alanlarından en kısa dolu listeyi
aday anahtarı seçer; keyword/score-only veya sınırsız arama `*` kullanır.
Kurulum tüm açık aramalarının anahtarlarını birleştirir. İlanın kadro alanları
adayları bulur, sonra ortak strict predicate tüm kriterleri doğrular; unknown
push üretmez. Birden çok facet/arama aynı kurulum+ilan outbox satırını çoğaltmaz.
Registry aynı transaction'da farkları günceller; değişmeyen heartbeat facet
satırı yazmaz. Mevcut abonelik migration'da geçici `*` ile korunur.
Her eşleştirme slotunda en çok10 aday veya4 boş facet; facet_index+ID cursor
kalıcıdır. En kötü sorgu üst sınırı38; çalışan SQL fixture sayımı ve canlı
EXPLAIN indeks kullanımı kontrol edildi. Geniş `*` kitleleri için gecikme,
günlük row-read/write ve CPU kapasitesi ölçülmeden10k desteği vaat edilmez.

Migration0005 `history_seq` ve `accepted_at` ekler. FCM accepted state commit'i
aynı transaction'daki trigger ile kalıcı tek-satır sayacı artırır; her accepted
olayda sayaç+outbox güncellemesi iki ek row mutation'dır (indeksler ayrıca).
Eski accepted kayıtlar migration'da korunur, pending/cancelled geçmişe girmez.
`GET /api/v2/installations/{id}/notifications?after=0&limit=30` own-record
secret gerektirir, no-store'dur. `watermark`, `appliedThrough`, `hasMore`,
numerik string `next` döner; sonraki sayfaya aynı watermark gönderilir.
Son sayfanın appliedThrough değeri bir sonraki açılışın after imlecidir.
Hash cursor artık kabul edilmez (400); ilerideki cursor409 cursor_ahead.
Seq global sayaçtan atanır fakat endpoint yalnız kurulumun kendi kayıtlarını
gösterir. Yanıt ilan title/url/revision/searchIds/mode/count ve event/delivery
kimliğini taşır; kaynak belgesi/özel tercih taşınmaz. accepted, cihaz teslimi
değildir. Mobil decoder/secure bounded cache/feed/receipt dedupe Flutter'da
uygulandı; native/gerçek FCM delivery testi açık. Server retention tamamlanmadı.

Migration0006 `listings.first_seq` alanını mevcut en erken katalog sırasından
doldurur; yeni ilan ilk katalog commit'inde trigger ile aynı transaction'da
atanır. Sonraki revizyonlar/değişiklik günlüğü temizliği bu değeri değiştirmez.
Eşleştirme aboneliğin effective_after değerini bu kalıcı ilk sırayla karşılaştırır;
yeni arama eski ilan revizyonu için push almaz. Eksik ilk sıra fail-closed'dur.
Katalog temizliği migration0012 ile aşağıdaki sınırlı bakım akışında çalışır.

Katalog `after`/`watermark` yalnız güvenli, negatif olmayan tam sayı dizeleridir.
Eksik watermark o isteğin latest sırasını sabitler; verilmiş watermark sessizce
latest'e çevrilmez. Boş/bozuk değer400 cursor, after'dan küçük watermark400
watermark, latest'ten büyük sıra409 cursor_ahead döner. Watermark0 boş geçmiş
anıdır; limit için mevcut bounded/default davranış korunur. Metadata ETag'i
latest+oldestRetainedSeq+source durumlarını içerir; retention sınırı değişince
aynı latest için304 dönmez. Public cache namespace v2 eski gevşek yanıtları ayırır.
Migration0011 kalıcı `catalogue_retention.floor` ekler (başlangıç0). Metadata
sınırı floor+1 olur; delta after<floor için409 cursor_expired, snapshot
watermark<floor için409 snapshot_expired döner. Floor'daki snapshot ve delta
geçerlidir; eski per-listing temel kayıtları MIN(seq)'den bağımsız korunabilir.
Mobil yalnız endpoint-specific/bounded409 hata kodunda bir kez no-cache metadata
ve bootstrap dener; ağ/diğer409/malformed hata cache'i sıfırlamaz. Favoriler ve
son başarı zamanı tamamlanmamış tekrar indirmede korunur.

Migration0012 `gc_after` kalıcı sweep imlecini ekler; mevcut
`catalogue_listing_seq` indeksi yeniden kullanılır. Saatlik bakımda floor'dan
sonraki en çok50 sıra/tarih okunur; yalnız90 günü geçmiş kesintisiz önek boyunca
floor ilerler. İlk yeni/geçersiz/canonical-olmayan tarih durdurur; en son global
seq daima tutulur. Böylece timestamp sırası bozulsa bile yeni bir revizyonun
üzerinden atlanmaz. Floor yayınlandıktan sonra en çok50 eski sıra okunur, aynı
ilana ait floor'a kadar daha yeni bir kayıt varsa en çok20 eski kayıt silinir.
Her ilanın floor'daki son upsert/tombstone kaydı ve floor sonrası bütün değişiklikler
kalır. Silme+sweep cursor aynı atomic batch/CAS; başka pass'ın floor/cursor'u
değiştiyse eski pass hiçbirini değiştirmez. `listings.first_seq`, güncel ilan,
eşleştirme/outbox/favori verisi etkilenmez. En az bir temel kayıt/ilan kalır;
bu politika tüm arşiv ilanlarını veya bildirim dedupe tombstone'larını silmez.

Delta/bootstrap cache-miss okumaları yanıt vermeden floor'u yeniden kontrol
eder; metadata ile immutable payload okuması arasında silinen kayıt da typed409
üretir. Prune yüzünden eksik sayfa başarılı imleç ilerlemesi olarak sunulmaz.
Cache'deki tam immutable sayfa TTL boyunca kullanılabilir; sonraki expired pin
mobilin tek fresh-metadata/bootstrap retry yoluna girer.

ponytail ceiling: saatte50 floor satırı,50 sweep adayı,20 silme. Daha büyük
backlog'da temizlik süresi ve CPU/row-write ölçümüne göre bakım slotu artırılmalı.
Katalog bakımı boş log'da1, recent/floor0 log'da2, eski/obsolete log'da en çok6
SQL kullanır; registry ile toplam en çok15 SQL, Free50 sınırı altındadır.
Bu query sayısı CPU10ms veya kullanıcı kapasitesi kanıtı değildir.

Saatlik `:59` Cron slotu registry ve katalog bakımına ayrılır; o saatte gönderim
slotları arasındaki aralık bir kez 6dk olur. 120 gün heartbeat almayan kurulumun
aktif send lease'i varsa dokunulmaz. Diğer stale kurulumlar önce disabled olur;
tek owner/pass için 20 outbox ve 50 facet silinir, child'lar bitince kurulum ve
en çok 20 saved search cascade ile kaldırılır. Bütün transaction adımları stale
tarihini tekrar kontrol eder; arada başarılı heartbeat varsa kayıtlar korunur.
Rate-limit expiry indeksiyle/pass 100 süresi dolmuş sayaç, 30 günden eski günlük
AI bütçesinden/pass 30 satır temizlenir; bugünkü bütçe korunur. Büyük backlog'un
temizlenme süresi ve CPU/row-write kapasitesi ölçüm bekler. Aktif kurulumların
bildirim geçmişinin sunum payload'u aşağıdaki arşiv politikasıyla küçültülür;
katalog log'u yukarıdaki floor/base/sweep politikasıyla budanır.

Migration0008 accepted_at/id partial indeksi ile bakım slotu en çok20 adet
90 günü geçmiş accepted bildirimi archived yapar. Payload `{}` olur; FCM
provider ID/hata içeriği kaldırılır. Kimlik, installation+listing UNIQUE,
history_seq ve digest bağı korunur: eski bir ilan tekrar push kuyruğuna girmez,
imleç gerilemez. Pending/leased digest üyeleri varsa o gruba dokunulmaz.
History endpoint yalnız accepted satırları gösterir; archived sıraların üzerinden
boş son sayfa pinned watermark'a ilerleyebilir. Yerel bounded history cache bu
işlemle zorla silinmez. Dedupe tombstone satırları stale-owner cleanup'a kadar
kalır; çok uzun ömürlü kurulumlarda toplam satır kapasitesi hâlâ ölçüm konusudur.

Migration0009 terminal payload partial indeksiyle aynı bakım slotu en çok20
adet `failed`/`cancelled`/`expired` satırın oluşturulmasından90 gün sonra
payload'u `{}` yapar ve FCM provider ID'sini temizler. Durum/hata kodu,
kimlik/UNIQUE ve digest bağı korunur; history sequence değişmez. Pending/leased
grup üyesi varsa terminal payload da korunur. Boşaltılmış satır partial indeksten
çıkar, her pass tekrar yazılmaz. Bu politika tombstone toplam satır büyümesini
çözmez; toplam satır kapasitesi açık iştir. Registry kısmı owner seçilmezse
5 SQL, seçilirse9 SQL çalıştırır; katalog kısmı yukarıdaki en çok6 SQL ekler.
Gerçek backlog CPU/read/write ölçümü gerekir.
