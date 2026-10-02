# Mevcut Mimari — KamuBul

30 Eylül 2026 geçiş başlangıç noktası. Bu belge çalışan/depo içinde bulunan durumu anlatır; hedef mimari target.md, uygulama sırası tasks/ içindedir. Eski mimari anlatımları Git geçmişindedir.

## 1. Gerçek durum ve sınır
Son checkpoint: production67ad2d7f-2a8e-447e-ad88-93fe33945081, observability%10. Metin AI işinin ilk çağrısından önce provider/model/extractionRevision job.input.aiContract'a kalıcı pinlenir; env model değişimi partial işi karıştırmaz. Sonuç aiProvenance taşır; source_only null, eski sonuçlara model uydurulmaz. Bilinmeyen partial revision veya uyumsuz extractionRevision input korunarak failed olur, quota harcanmaz.129 native test/dry-run/deploy ve live21/42/applied42/meta304 geçti. Remote21 completed/legacy_partial0 readonly doğrulandı. Versioned job identity ve açık bounded reprocess aracı hâlâ yok; unique listing+hash korunur. Gerçek CPU/D1 gözlem sınırları docs/WORKER_FREE_PILOT.md içinde; yeni pinning CPU veya model precision kanıtı değildir.
2 Ekim yeni kullanıcı hedefi ADR-002 ve PB-022'de kayıtlı: harici AI fallback ve kriter asistanı henüz uygulanmadı; provider/key/bütçe yok. Mevcut elle SavedSearch düzenleme/matcher var, _assistantView gerçek sohbet değil kaynak cümlesi rehberi. Canlı AI hâlâ yalnız Workers AI binding, günlük provider kotasında quota_wait.

2 Ekim kaynak CPU kontrol noktası: slot başına bir pending_batch girdisi işleniyor; imleç kalıcı,127 native Worker testi geçti. Önceki dört ilanlı kaynak Cron aşaması20ms CPU gösterdi; yeni tek girişli aşamanın CPU değeri henüz doğrulanmadı. Kaynak slotu3dk olduğundan21 giriş yaklaşık63dk ve tamamlanınca30dk bekleme gerektirebilir. Geçici%100 günlük örneklemesi%10'a geri alındı; deployment a2f92b43-b8d8-4ea1-9650-1afa6b4ef5ac. Ayrıntılı CPU/güncel kapasite kapıları PB-016 Resume içinde açık.

**Sunucuya geçiş tamamlanmadı.** Flutter hâlâ kaynakları telefondan çekiyor. Kalıcı Cloudflare Worker/D1 ve Cron yayında; API HTTP200 doğrulandı. Kariyer resmî RSS üzerinden21 gerçek ilan/42 immutable değişiklik var. Ayrıntı API522/SBB erişim engeli devam ediyor; AI özet/koşul çıkarımı ve gerçek cihaz FCM teslimi doğrulanmadı. FCM gönderici Secrets kalıcı Worker'a aktarıldı; Google OAuth gerçek anahtarla başarılı, canlı health fcmConfigured=true. Yayındaki altyapı tüm hedefin tamamlandığı anlamına gelmez.

Mobil kaynaklar: `lib/main.dart`, `lib/home_page.dart`, `lib/data/catalogue_refresh.dart`, `lib/data/remote_sync.dart`, `lib/data/listing_store.dart`, `lib/notifications/`.
Ortak çekirdek: `packages/kamubul_core/lib/`.
Eski sunucu referansı: `backend/lib/src/`, `backend/bin/`, `backend/test/`; native Dart, Cloudflare Worker değildir.

## 2. Mobil — VERIFIED kod incelemesi

Yaş paritesi güncel kontrol noktası: Worker/Dart aynı kadroda inclusive minAge/
maxAge + ageReferenceDate + bornOnOrAfter/bornOnOrBefore koşullarını birlikte
uygular. Aday age+asOf olası doğum aralığıdır; tam gün alınmaz/tahmin edilmez.
Bütün olasılıklar uygun→match, hiçbiri→no_match, kısmi→unknown; strict push yok.
366day freshness, malformed/çelişen bounds ve unsupported ageCalculation unknown.
Canonical tamamlanmış yıl/29Şubat→1Mart sözleşmesi workers/README.md; kaynak
normalizasyon precision kapısı açılmadı, ham metinden limit varsayımı yapılmaz.
V1 tarihli koşulu basit maxAge'ye düşürmez, groups korunur.58 ortak case Worker/
pure Dart/SQLite,144 enumerated-birthday karşılaştırması; Worker126/core170/
Flutter132 full ve changed analyze temiz. APK223502990 bytes/17.4s rebuilt;
cihaz kurulumu/teslim/production typed extraction kanıtı değildir.

- Katalog transport durumu normalize HTTPS API köküne (path dahil; sondaki slash eşdeğer) bağlıdır. Schema7→8 origin/generation göçü mevcut cache/favori/arama/cursor'u korur; ilk origin bağlama veya sunucu değişimi yalnız cursor/metadata/ETag/staging'i sıfırlar. Görünen cache tam bootstrap commit'e kadar kalır. Tüm v2 okuma/yazımlar generation kontrolü yapar; A→B→A sırasında cursor/watermark aynı olsa bile eski HTTP cevabı publish edemez. 28 sync test ve Flutter131 full geçti; cihaz geçişi kanıtı değildir.
- Flutter Android/iOS, Türkçe; napp_core tema, napp_ads, napp_pro. Hesap girişi yok. SQLite schema8: remote_catalogue/cursor yanında metadata, ETag ve last_success kalıcı; v5→v6 cursor/favori/arama koruma ve metadata CAS kontrolü doğrulandı. Tema/hareket, skeleton, filtre sheet, onboarding ve erişilebilirlik testleri mevcut.
- `refreshCatalogue`: KAMUBUL_API varsa v2 conditional metadata ve frozen-watermark delta kullanır. SQLite cache+cursor sayfa başına atomik; en çok20 sayfa, kesilen backlog sonraki refresh'te devam eder. Son başarı yalnız tüm watermark tamamlanınca expectedCursor kontrolüyle yazılır. V2 UTC tarihler kartlara korunarak aktarılır. İlk kurulum/eski/ileride cursor frozen full bootstrap kullanır: SQLite staging sayfa/ID cursor kalıcıdır,20 sayfa sonrası sonraki refresh devam eder. Tam son sayfa tek transaction içinde remote kayıtları uzlaştırır; favori/arama/local-only kayıtlar korunur, yok olan favori inactive kalır. Sunucu seq sıfırlanması düşük revision dönüşünü engellemez; bootstrap sonrası yeni metadata watermark'ına delta alınır. Kaynak eksik/hatalı veya son başarı >36 saat ise ilgili resmî kaynağa telefondan geçiş fallback'i sürer; uzak adres yoksa tüm kaynaklar telefondan çekilir. Remote-only geçiş kapıları açık.
- Home cache ilk yüklemede kalıcı son başarılı eşitleme tarihini ve kaynak metadata'sını okur. Remote hata sonucu ayrı remoteFailed taşır; telefon fallback başarısı sunucu başarısı gibi gösterilmez/puan istemi açmaz. Başarı zamanı hata halinde ilerlemez, stale/error önbellek etiketi ve hata mesajı görünür. Kaynaklar ekranı cache'deki server state/note'u gösterir; ilan.gov ID'si Worker ile ilangov hizalı. Offline startup timestamp korunması widget kontrolünde doğrulandı.
- `refreshKariyerCity` ve HomePage şehir seçimi ayrıca doğrudan Kariyer Kapısı'na gider. `ListingGuideView` ayrıntı için resmî kaynağa doğrudan gidebilir. Bunlar sunucuya taşınması gereken ağ yollarıdır; yalnız liste refresh'i değiştirmek yetmez.
- `main.dart` her açılışta `registerBackgroundAlerts` çağırır. Android Workmanager 12 saatlik görev `runAlertCheckOnce` üzerinden kaynakları yeniler, beş şehre kadar ek sorgu yapar, yerel eşleşme/instant/digest/kuyruk/reminder üretir. Yeni hedefte yeni-ilan keşfi ve bu yerel bildirim üretimi kaldırılacak. Bildirimin telefonda OS tarafından gösterilmesi ve foreground sunumu yine cihaz görevidir.
- SavedSearch mevcut SQLite filters TEXT alanında criteriaVersion2 zarfıyla typed SearchCriteria taşır; yeni tablo/schema göçü yok. Legacy Map okunur, referanssız eski yaş1970 tarihiyle unknown kalır. Bozuk/zarf sürümü bilinmeyen kriter hasInvalidCriteria işaretlenir: registry'den çıkarılır, apply/rename/mode engellenir, açık uyarılı edit ile onarılabilir. Kayıtlı arama adı ve bildirim modu değişimi typed puan/yıl/çoklu alanları korur. UserData schema2 typed kriteri export/import eder; schema1 yedekler okunur, bozuk typed yedek hiçbir yazımdan önce reddedilir.
- Yeni/düzenlenen aramalar tek doğrulanan profil formunu kullanır: yaş+ageAsOf, KPSS türü/puanı/yılı ve şehir/eğitim/ilan türü/meslek/kurum için çoklu autocomplete+silinen chip'ler (<=10/alan, Türkçe katlama, en çok20 öneri). Şehir81 il, eğitim/tür statik mevcut sözleşme; meslek/kurum aktif canonical cache+önceki seçimlerden gelir, ek ağ/model çağrısı yok. Keyfi global taxonomy üretilmez. Anahtar kelime title/full kapsamlıdır; kişisel arama adı filtre değildir. Yarım seçim metni save'i engeller; eski yaş otomatik bugüne taşınmaz. Çoklu şehir/eğitim tek legacy filtreye indirgenmez, typed kriter/backup/registry korunur. Ortak _filterSummary typed çoklu kriterleri yönetim/profilde gösterir. Eğitim kimlik/alias eşleştirmesi uygulandı; diğer canonical sözlük kimlikleri hâlâ açık; hızlı filtreler ortak typed eşleştiriciye bağlandı.
- `allListings` aynı SQLite transaction'ında legacy listeler ve remote_catalogue JSON'undan küçük kriter projeksiyonunu okur; doküman metni UI modelinde tutulmaz. Sistem SQLite JSON1 gerektirmez, remote okumaları50 kayıt sayfalıdır. Alternatif requirementGroups aynen korunur; tombstone/active=false kesin eşleşmeden çıkarılır, favori durur. Aynı URL birden fazla canonical kimliğe aitse bilinmeyen olarak kalır. Server v2 payload artık yapılandırılmış varsayılan delta refresh ile cache'e gelir; şehir/ayrıntı/fallback yolları sürdüğünden remote cutover tamamlanmış değildir.
- Kayıtlı arama seçimi stable yerel ID ile yapılır; aynı adlı aramalar karışmaz. Seçili arama listesi, Sizin için rozeti ve geçişte kalan decideAlerts ortak SavedSearch.matchListing → SearchCriteria kullanır. Unknown varsayılan gösterilmez/push üretilmez; kullanıcı Şartları kontrol et açarsa belirsiz kartlar açık uyarıyla görünür. Legacy kaydın düz maxAge/KPSS/education alanlarından çoklu kadro uygunluğu uydurulmaz; canonical koşullar yoksa ilgili typed kriterler unknown kalır. Kaydedilmemiş hızlı filtreler matchFilters → SearchCriteria kullanır; liste ve uyarı aynı üç durumu okur. Son30 gerçek publishedAt ister, deadline yerine kullanılmaz. forSaved yalnız availability kontrolünü atlar; diğer kriterler korunur, push varsayılan strict kalır. Kayıtlı aramadan hızlı düzenlemeye geçişte sadece değişen alan yenilenir; çoklu seçim/puan/yıl/keywordScope/ageAsOf taslakta korunur, özet görünür ve yeniden kayıt formuna geçer. 100 karakter kelime sınırı typed sözleşmeye uygundur. Taxonomy alias geçişi açık.
- Saf `SearchCriteria` typed doğrulama/üç durum/requirementGroups/v1 göçü, Worker ile58 ortak JSON örneğinde aynı sonuç veriyor. PushRegistrar artık `/api/v2/installations/{id}` PUT/DELETE ve criteria+mode payload kullanır;32KB UTF8 body aşımı ağdan önce başarısız olur. Geçersiz/uzun kriter araması bütün olarak hariç tutulur, daraltıcı filtre sessizce silinmez.401/403 sonrası yeni ID yaratarak yetki reddini aşmaz. Kalıcı kimlik/token FIFO akışı korunur; gerçek cihaz kaydı/teslimi henüz yapılmadı.
- `FirebasePush`: derleme FIREBASE_* ayarlarıyla initialize, izin/token/token refresh, onMessageOpenedApp ve initial message URL. Foreground payload bounded HTTPS/title/body+64hex eventId kontrolünden geçer; PendingNotification mevcut yerel kanala gider. Receipt güvenli depo ack'i öncesi gösterilmez; disabled/repeated receipt gösterilmez. OS kimliği eventId'nin ilk8hex'inden stable int + Android tag; iOS otomatik foreground sunumu kapalı, yerel plugin tek sunucu. Initialization izin istemez; gerçek OS teslim/tekrar/fiziksel cihaz testi eksik; Android emulator native-store kontrolü geçti.
- `PushRegistrar` authenticated accepted history GET'i aynı FIFO'ya bağlar: token/izin/yeni kimlik istemez, redirects kapalı,256KB/20s/5page bounded, after+pinned watermark+records atomik secure blob'da saklanır; origin+installation scoped. Kesilen sayfa resume;401/redirect/oversize kimlik/cursor'u değiştirmez,409 bir kez reset/reconcile. Cache en çok100 kayıt/200 receivedID, tüm secure state120KB hedefinde UTF8 trim; registry payload büyümesi ack+cache trim ile aynı batch. Android Keystore/no-backup/iOS ThisDeviceOnly kullanır, yeni dependency/schema yok. Açılış/resume/notification center sync; feed eski OS mesajını yeniden göstermez. Foreground receipt concurrent/restart dedupes; geçmişi temizlemek cursor/receivedIDs tutar, disable tüm server cache'i siler. NotificationCenter cache-first/live stream, accepted=Servise iletildi, received=Alındı, network failure yerel kayıt uyarısı. Pencere dışındaki çok eski retry ve gerçek native/sunucu teslimi kanıtı açık.
- `PushRegistrar`: rastgele kurulum ID/secret, opt-in token+kriter kaydı, PUT/DELETE. Push state (ID/secret/token içeren lastPayload dahil) SecurePushStore üzerinden Android Keystore AES-GCM/noBackupFilesDir ve iOS ThisDeviceOnly Keychain koduna taşındı. Android API36/x64 native yazma/reopen/plaintext temizliği emulator kontrolünde geçti; süreç restart/iOS build/backup-restore kanıtı eksik. Bir hesap/kullanıcı kimliği değildir, yeniden kurulum ayrı cihaz kaydıdır.

Eğitim taxonomy kontrol noktası: beş sabit education:* kimliği, Ön lisans/Önlisans ve Yüksek lisans/Yükseklisans aynı düzeydir; diğer düzeylerin yerine geçmez. Bilinmeyen eğitim unknown, aynı kadroda bilinen uygun alternatif varsa match. Worker predicate/aday anchor aynı kimlik kullanır; Dart matcher aynı25 corpus'u (SQLite dahil) geçirir. API taxonomy eski label listesini koruyup educationValues id/label/aliases ekler; canlı5 değer doğrulandı. Mobil form/chip/özet kimlikleri Türkçe label gösterir. Eski label wire/persist değerleri topluca değişmez. Migration0010 eski aktif education facet sahiplerine wildcard ekler; heartbeat yeni anahtarlarla indeksi kurar, preference version/baseline korunur; pending/leased fanout cursor reset, completed aynen. Büyük wildcard geçiş kapasitesi ve diğer meslek/kurum/kategori kodları/sözlük sürüm göçü açık. Worker78/core135 full, Flutter131 full + sonUI/SQLite9, changed analyze/diff-check geçti.

Katalog API strict after/watermark validasyonu korundu: malformed400/future409,
metadata ETag saklama sınırını kapsar; public cache v2. Migration0011 kalıcı floor
ve mobil typed expired-pin recovery aşağıdaki güncel kontrol noktasında doğrulandı.
Bounded log silme migration0012 ile aşağıdaki güncel bakım akışındadır.

## 3. Ortak kod ve eski sunucu — VERIFIED kod incelemesi

- kamubul_core saf Dart modeller, Kariyer/SBB parser, deterministik koşul çıkarımı ve kanıt/eval kapıları, dedupe, snapshot schema1, remote client, kayıt doğrulama, AI adaptör/gate ve push planner içerir. Flutter bunları import/re-export ediyor; silinmeyecek.
- backend native Dart API `/v1/listings.json`, `/v1/sources.json`, `/v1/health`, `PUT|DELETE /v1/devices/{id}`; dosya veya Firestore depolama, fetch-detail-AI-publish-match-FCM pipeline. Cloud Run için tasarlanmıştı, canlı dağıtım yok. SQL/D1 implementasyonu yok.
- AI adaptörleri Anthropic/OpenAI-uyumlu/Gemini, şema+alıntı+confidence kapısı ve bütçe/eval aracı içeriyor. Gerçek model ölçümü ve Workers AI adaptörü yok; alanlar varsayılan kapalı. Kullanıcı profilleri modele gönderilmiyor.
- Pipeline cihazları tarıyor ve 25 paralel gönderim yapıyor; Free Worker'a taşınabilir kabul edilmemeli. URL/detailed işaretleri güvenilir içerik revizyon hash'i değildir. pendingPush tüm cihaz turundan sonra temizleniyor; kalıcı outbox/cursor ve timeout sonrası tekrar kontrolü gerekiyor. Mevcut planner'ın 50 kayıt kuyruğu ve arama bazında tekrarları yeni sözleşmeye uymaz.
- Eski Google/VPS dağıtım reçeteleri ve konfigürasyonları bu hizalama çalışmasında aktif ağaçtan kaldırıldı. backend runtime/testleri geçişte API/parite referansı olarak korunuyor; FirestoreStorage hâlâ referans kod, hedef storage değil. Başarılı geçiş sonrası silinmesi PB-019 kabul ölçütüdür.

## 4. Kaynaklar

Kariyer Kapısı liste/API/RSS ve SBB WebForms/PDF Dart adaptörleri mevcut. Worker API/RSS ve SBB liste adaptörleri `workers/src/sources.js` içinde. Canlı: Kariyer API HTTP522; RSS20 kayıt başarılı fakat20 ayrıntı unavailable. SBB blocked. Aynı Node adaptörleri Windows çıkışından gerçek20/135 liste kaydı okudu; bu Cloudflare ayrıntı erişim kanıtı değildir. SBB PDF içerik çıkarımı Worker'a taşınmadı. Resmî Gazete kapsam dışı. İŞKUR/ilan.gov.tr WAF/oturum kısıtlı; belediye kapsamı eksik. Kaynak engeli telefon/proxy fallback ile gizlenmeyecek.

## 5. Kalıcı bulut kaynakları — VERIFIED CLI/live HTTP, planlar OBSERVED konsol

Son canlı doğrulama: genuine ingestion sonrası21 ilan/42 immutable değişiklik,
appliedThrough42/metadata304. Remote read-only aggregate21 source_only ve
2026-10-02 daily_usage boş; rows_written0/changed_db=false/319488bytes. Bu
çalışma AI çağrısı/pilot production kaydı/push yaratmadı. Kaynak detail erişimi
ve typed extraction hâlâ açık; yeni ilan sayısı bu kapıları kanıtlamaz.

AI kota/capacity kontrol noktası: provider3036 resmi binding mesajından tanınır;
job quota_wait/sonraki UTC gün, lease bırakılır, attempt geri alınır, başarılı
chunk input aynen kalır. Aynı transaction bugünün daily_usage bütçesini kapatır;
diğer işler yeni inference yapmadan bekler. Bu kesici sonrası ai_jobs gerçek
çağrı/Neuron sayısı değil application budget tavanıdır.3040 ai_busy, aynı parçada
en çok5/backoff ardından explicit failed; ilerleme kalır. Worker97 full ve
dry-run/deploy geçti; canlı health ok/20 ilan/40 değişiklik/applied40/meta304.
Canlı quota tükenmesi yaratılmadı; hata yolları SQLite regression kanıtıdır.
Pilot REST options.rejectIfBusy ve provider codes düzeltildi; eski18 çağrıda
REST options iletilmemişti, production binding zaten gönderiyordu. Yeni AI
çağrısı/migration/mobile değişimi yok; detay docs/AI_MODEL_PILOT.md.

- Worker `kamubul-api`, `https://kamubul-api.devx8585.workers.dev`, Free $0; D1 `kamubul`, ID `371092dd-2cc7-487f-b971-84c2499bbc7d`, EEUR/DB binding. Migration0001–0013 remote uygulandı. Deployment `6f148686-305f-4405-8815-956786cdd006`; live health status=ok/latestSeq42/fcmConfigured=true/aiConfigured=true. Cron her dakika; scheduledTime mod3 kaynak/AI/expiry, eşleştirme, gönderim slotlarını ayırır. Her aşama3dk, kaynak polling30dk. Üretime demo ilan/cihaz yazılmadı; son read-only installations/outbox/facets/pending_matches0/0/0/0 ve bu çalışmada registry/push çağrısı yok.
- Worker v2 meta/taxonomy/listings/changes/detail/installations/history ve v1 geçiş uçları var. Immutable seq/tombstone trigger, source lease/cursor/hash, durable AI processing, matching cursor/outbox/FCM HTTPv1 kodu bulunur; runtime dependency yok. Indexed candidate matching uygulandı; büyük kitle kapasitesi, eğitim dışı canonical/alias kimliği ve toplam server retention eksik; mobil retained-cursor bootstrap hazır.
- Aday indeksi installation_facets(key,installation_id); şehir/meslek/eğitim/kurumdan en kısa arama listesi, broad/keyword/score-only `*`. Registry transaction'da set diff yapar (değişmeyen facet heartbeat yazımı0), eski abonelikler migration'da wildcard ile korunur. İlan kadro anahtarları superset, exact shared predicate son karar; unknown push yok. Slot başına10 aday/4 boş facet, kalıcı facet_index+ID cursor, kurulum+ilan outbox unique. Native fixture sorgu sayımı<=38; canlı EXPLAIN covering key+ID indeksi. Free50 sorgu/subrequest sınırı için slotlar ayrıldı; gerçek CPU/fanout/write kapasitesi henüz ölçülmedi.
- Private history migration0005: FCM accepted commit trigger'ı notification_sequence tek-satır sayacından history_seq/accepted_at atar, eski accepted kayıtlar korunur; repeated acceptance yeni sıra üretmez. Authenticated own-record endpoint accepted-only, compact presentation fields, numeric after/pinned watermark/appliedThrough/hasMore/next; hash cursor400/ahead409. Live installation_history_seq range index doğrulandı; production accepted/outbox0 olduğundan gerçek gönderimle sequence doğrulanmadı. Native fixtures düşük hash/yeni acceptance/pinned pages/auth crossing/2MB source excluded/backfill kontrolü içerir. İki ek row mutation/acceptance+index maliyeti; accepted payload arşivi ve mobil feed/dedupe kodu mevcut, gerçek cihaz teslimi ve kalan retention açık.
- Pipeline geçici detail failure'da önceki payload/hash/özet/firstSeen'i korur; eksik ayrıntı kaynak uyarısında görünür. AI yazımı yalnız AI alanlarını json_set ile günceller; eşzamanlı metadata ezilmez.120KB UTF8 kaynak metni12KB kayıpsız parçalarla kalıcı ilerleme/son birleştirme üzerinden işlenir. Günlük20 model isteği parça/birleştirme/retry dahil; request24KB/output1024 token. rejectIfBusy +45s logical timeout var; timeout sağlayıcı inference iptali değildir. PDF/OCR ve120KB üzeri belge okuyucu eksik.
- Outbox günlük digest İstanbul18:00/sessiz saat; kurulum başına bir/gün,10 ilan/grup, kalan durable queue'da sonraki güne kalır ve deadline'da expired. delivery_id retry üyeliğini korur; ayrı digest_day anlık sent_count kotasını tüketmez. send_lease_until paralel Cron cap yarışını sıralar. Gönderimden önce current listing/revision/deadline/strict criteria + opt-out/token/version recheck; invalid eski token yeni tokenı pasifleştirmez. Accepted history payload güncel gönderilen revision/title/searchIds ile, canonical eventId ve ayrı deliveryId. FCM TTL/APNs expiry deadline/en çok24h; gerçek teslim henüz yok, ambiguous timeout exactly-once değil. Bounded10 backlog gecikmesi/Free CPU pilotu açık.
- expireListings kaynak slotunda (3dk)10 indexed deadline kaydını inactive/revision+immutable tombstone yapar; expired processing model quota harcamadan superseded, expired match fanout yapmadan sonlanır. V2 meta pending/processing iç durumlarını desteklenen state'e eşler; source refresh ortasında client schema bozulmaz.
- AI binding/model artık JSON Mode destekli `@cf/meta/llama-3.1-8b-instruct`; Free plan korunur.2 Ekim karşılaştırma18 girişim/17 HTTP200/1 timeout, raporlanan791.6394 Neurons (timeout tüketimi bilinmiyor). Son8B pilot gerçek14KB/8kadrolu ilanı iki parça+consolidation/3 çağrıda5 alıntıyla tamamladı,35.8426 Neurons; completed hash pending replay yeni inference olmadan superseded. REST+üretim processNotice kodu+bellekte SQLite kanıtıdır, Worker CPU/egress/precision değildir. Gerçek üretim D1 salt-okunur kontrolünde20 ilan source_only, bugünkü daily_usage satırı yok; CLI pilot sayacı üretim bütçesine yazılmaz.
- Model yalnız quote seçer, text alıntıdan üretilir;30–240 karakter/duplicate guard ve final>=3 madde gerekir. JSON schema ve temperature0; malformed JSON ai_schema. Consolidation bütün parça alıntılarını görür, sessiz first-item kaybı kaldırıldı;24KB aşımında ilerleme korunarak hata, büyük multi-pass reduction açık. Kadro kapsamı native kaynak metninden gelir, model etiketine güvenilmez: tek kadro başlığı<=50 karakter veya Bazı kadrolar; yalnız genel metindeki alıntı etiketsiz; ortak metne kopyalanan kadro quote etiketi korunur, cross-position birleşik quote reddedilir. Additive scopeLabel v2 mobil cache ve v1 string projection'da korunur; malformed label/text elenir. Son gerçek P3/eğitim alıntıları Kütüphaneci, yaş/öğrenci/vardiya Bazı kadrolar olarak işaretlendi.
- Paraphrase/typed şart çıkarımı ve>=50/kaynak precision/recall/useful-summary coverage kapısı hâlâ kapalı. Bu geçici kaynak alıntısı tam hedefin yerine tamamlandı sayılmaz; kalan model/extractor version ve planlı reprocess sözleşmesi açık, config eski arşivi topluca yeniden okumaz. `docs/AI_MODEL_PILOT.md` kanıt/CLI sınırları. Dashboard Workers Free `$0` Current plan doğrulandı; ücretli upgrade/fallback yok, üretime pilot ilan/push yazılmadı.
- Public Cache API allowlist yalnız v2 meta/taxonomy/listings/detail/changes GET: dynamic60s/taxonomy300s, sorted query/cursor/watermark anahtarı. Authorization/Cookie/private history/no-store bypass; no-cache fresh. Cache arızası API'yi kesmez. Canlı200 HIT ve ETag304 HIT görüldü. Cache veri merkezine yereldir; Worker request kotasını kaldırmaz.
- V2 listings/changes önce en çok50 kayıt boyutunu sorgular,1.8MB bütçesine sığan contiguous immutable payload'ları yükler. Cursor/next yalnız gönderilenlere ilerler, frozen watermark sonrası revizyon sızmaz. Tek oversized kayıt413 record_oversize döndürür; kayıt silinmez/cursor atlanmaz. Bu durum ayrı compact catalogue/document reader gerektirir; büyük sayfa Free CPU ölçümü eksik.
- Wrangler OAuth kullanıcı onayıyla Windows keyring'de; account/user read + Worker/D1/AI yönetimi. Credential Git/Brain'de yok.2 Ekim dashboard eski `kamubul-api-dev` URL'sinde Worker yok dedi; Workers & Pages overview yalnız1 app `kamubul-api` gösterdi. Dev Worker artık gözlenen listede yok; ne zaman/kim tarafından kaldırıldığı bilinmiyor. D1 `kamubul-dev` (ID `3fbb739f-891c-4da1-821e-417018139721`) cleanup hâlâ doğrulanmadı. Önceki CLI delete KV listeleme izni yüzünden auth10000 verdi; ek KV kapsamı verilmedi. Account subscriptions REST403/code10000 verdi, billing-read kapsamı genişletilmedi; Free plan UI üzerinden doğrulandı.
- Firebase `kamubul-3ae6e`, Spark $0; FCM v1 Enabled. Android `com.crazypenguin.kamubul`, appID `1:1003012781397:android:c474608bf0e36534ae2bdc`, sender1003012781397. `kamubul-fcm-sender` yalnız Firebase Cloud Messaging API Admin rolünde; IAM tablosu doğrulandı. Kullanıcının JSON'u kimlik/PEM kontrolünden sonra resmî Wrangler secret bulk stdin ile FCM_CLIENT_EMAIL/FCM_PRIVATE_KEY olarak kalıcı Worker'a aktarıldı. Google Keys'te yalnız yeni aktif key var; indirilmeyen eski key kullanıcı tarafından kaldırıldı. Yerel kullanıcı JSON korunur; key/token Git/Brain/log/client config'e yazılmadı.
- Mevcut fcmAccessToken ile Windows Node gerçek Google OAuth kabulü aldı; push gönderilmedi. Bu Cloudflare OAuth CPU veya cihaz teslim kanıtı değildir. Client google-services.json ignored Android dosyasına kopyalandı; ignored .tmp/firebase-android.defines.json dört FIREBASE_* değeri içerir, server key içermez.

## 6. Doğrulama ve açık sınırlar

Migration0008 outbox_accepted_retention partial covering indeksi canlı EXPLAIN ile doğrulandı. Saatlik bakım90day accepted kayıtların en çok20 tanesini archived yapar; payload `{}`/FCM ID/error silinir. Installation+listing UNIQUE/eventID/history_seq/accepted_at/digest bağı tutulur, pending/leased grup üyeleri korunur. History GET accepted-only, watermark MAX tüm accepted+archived sequence'den; pinned boş final page imleci ilerletir, yeni acceptance sıra artırır. Native69 test (prune/dedupe/20row cap/pending group/pinned gaps) ve canlı20/40/304 geçti. Üretim outbox/installation0, model/gerçek push yok. Migration0009 terminal payload indeksi canlı EXPLAIN ile doğrulandı; aynı bakım slotunda90 gün önce oluşturulan failed/cancelled/expired satırlardan<=20 payload boşaltılır ve FCM ID temizlenir. Durum/error code/UNIQUE/identity/digest bağı korunur, incomplete digest üyeleri korunur; boş payload partial indeksten çıkar. Native70 full; sınır günü/yeni/pending/leased/grup/dedupe/sequence ve tekrar-pass kontrolü geçti. Owner yoksa5, varsa9 SQL; gerçek backlog CPU/read/write, uzun yaşayan kurulum tombstone kapasitesi hâlâ açık. Katalog bakım politikası aşağıda güncel.
Mobil history/registry25 targeted test ve ilgili analyze temiz; yeni boş-final-page/pinned ilerleme kontrolü eklendi. Flutter131 full yeni history ve selector kontrollerini içerir.

Migration0007 rate_limit_expiry covering indeksi canlı EXPLAIN ile doğrulandı. Saatlik :59 Cron normal gönderim yerine maintainRegistry çalıştırır (bir saatlik döngüde bir kez gönderim aralığı6dk): 120day stale/send-lease-expired owner seçilir, aynı transaction tüm adımlarda tarih/lease yeniden kontrolüyle disabled→20 outbox/50 facet budama→child bitince owner+<=20 search cascade. Heartbeat araya girerse kayıtlar kalır; aktif send lease korunur. Pass başına100 expired rate counter/30 eski UTC günlük AI budget row; bugünkü bütçe korunur. Native69 test stale boundary/partial resume/concurrent heartbeat/live index ve canlı20/40/304 geçti. Üretimde installation/outbox0; gerçek bakım backlog/CPU/load veya tüm server retention tamamlandı kanıtı değildir. Accepted history payload arşivi yukarıda doğrulandı; Katalog bakım akışı aşağıda doğrulandı; tombstone toplam kapasitesi açık.

Migration0006 kalıcı listings.first_seq ekledi; mevcut20 ilan en erken change seq'den dolduruldu (missing0/mismatch0 canlı salt-okunur kontrol). Yeni ilan ilk catalogue commit trigger'ında aynı transaction'da atanır, sonraki revision/tombstone korur. MatchEvents current listing okumasından bu sırayı kullanır; katalog log'u budandığında yeni abonelik eski ilan için push almaz. Eksik sıra fail-closed/retry; sınırlı katalog temizliği migration0012 ile devrededir. Worker69 native test/dry-run/deploy ve canlı20/40/meta304 başarılı; gerçek fanout/CPU kanıtı değildir.

| Kapsam | Son doğrulanmış kanıt | Kanıtın sınırı |
|---|---|---|
| Worker |95 native Node/SQLite test, dry-run/deploy; remote migration0004 ve covering index planı, üç-slot timestamp kontrolü; canlı Dart watermark40/catalogue20/applied40/changes40/metadata304 | Gerçek model, source detail erişimi, OAuth/FCM/great-page CPU ve load değil |
| Core/backend referansı | Core127 full; backend37 önceki hizalama kontrolü | Canlı cloud/backend release kanıtı değil |
| Flutter |132 full; selectors390px/320px1.3x ve önceki history32 targeted+8 UI/2FG; core143 full; pinned history resume/receipt FIFO/native budget/HTTP auth/redirect/size ve320px1.3x offline/live UI; analyze temiz | Keychain/gerçek kapalı-app teslimi veya release cihaz UX değil; Android native-store kanıtı ayrı satırda |
| Android build | Main debug actual Firebase/API build47.7s, app-debug.apk223499557bytes; city ID labels+shared predicates ve önceki retention recovery içinde | Debug signing/AdMob test fallback; bu build cihazda kurulup çalıştırılmadı. Mevcut emulator x64 APK önceki eğitim alias checkpoint'idir; physical FCM/iOS/release kanıtı değil |
| Native store integration | API36/x64 emulator-5556:124588634byte tek-ABI APK manuel adb install-r başarılı; flutter drive prebuilt binary ile native write/reopen/plaintext temizliği geçti. Normal actual-config223494589byte APK sonrasında install-r ile geri kuruldu | Süreç restart/backup restore/fiziksel FCM/iOS kanıtı değil. Eski Workmanager callback test binary'sinde yok; test sırasında ayrı engine entrypoint hatası loglandı, normal APK geri kuruldu. README tekrar komutlarını içerir |
| Free runtime | Önceki canlı source-only idle Cron4–6ms CPU/outcome ok | Source+model+OAuth+fanout yükünü veya10k ücretsiz kullanıcıyı kanıtlamaz |
| Gerçek AI pilotu |18 girişim/17 HTTP200/1 timeout; son8B JSON Mode iki parça+consolidation/5 scoped alıntı ve processed_hash replay guard geçti,35.8426 Neurons;95 native test/dry-run/deploy ve canlı20/40/meta304 | Alan precision/recall/coverage/Worker CPU yok; genel timeout tüketimi bilinmiyor. `docs/AI_MODEL_PILOT.md` |

SecurePushStore tüm push state'i (ID/secret/lastPayload FCM token dahil) atomik awaited batch ile native depoya yazar. Android AES-GCM/Keystore ve noBackupFilesDir, iOS ThisDeviceOnly Keychain kodu var; iOS native build/çalıştırma/backup restore doğrulanmadı. Eski SettingsStore kimliği yeni yazım başarılı olmadan kaldırılmaz; migration hatasında eldeki kimlik korunur. Plaintext fallback yok. Registrar per-installation FIFO enable/sync/token/delete yarışını sıralar; credential ack olmadan HTTP yok; kapatma tamamlandıktan sonraki token refresh kaydı yeniden açmaz. Main secure state load'u UI başlangıcından önce bekler, Firebase listener init UI'yı bekletmez.

Listing persistence testindeki takvime bağlı expired beklentisi kaldırıldı; deadline/yer/quota ve tekrar açılış kontrolü durur. Değişen alanlarda yeni lint yok; remote_sync testindeki eski gereksiz importlar kaldırıldı. Fiziksel Android bağlı değil; emulator Android16/API36/x64, tek-ABI integration kurulumundan sonra742MB boş; normal uygulama APK'sı veri silmeden geri kuruldu. Android cihazı hakkında kullanıcıya soru gönderildi; cevap henüz yok. iOS/Mac/APNs, production signing/AdMob/store satın alma/restore ve release görsel testleri açık. Source terms, field precision corpus, neuron/scan/write kapasite ölçümü ve real-device notification kapıları hâlâ geçilmedi. Son kriter/senkronizasyon/server history/receipt/live UI değişiklikleri actual-config debug APK içine derlendi; cihazda çalıştırılmadı. Tüm hedef tamamlandı kabul edilmez; eski telefon fetch/Workmanager runtime'ı kaldırılmadı.

Hızlı typed filtre kontrol noktası: Flutter131 full/core135 full, değişen5 alan analyze ve diff-check temiz. 390px/320px1.3x UI akışında elle kelime değişimi, belirsiz kart uyarısı ve yeniden kayıt formunda çoklu seçim/puan/eski yaş referansı korunması doğrulandı. Actual API+Firebase debug APK yeniden derlendi (223494589 byte); cihaz çalışması/release kanıtı değildir.

Katalog retention: migrations0011–0012 kalıcı floor/gc_after singleton
(canlı0/0). Saatlik:59 registry sonrası maintainCatalogue; <=50 floor adayı,
<=50 eski sweep adayı/<=20 silme. Floor yalnız canonical ISO90day eski kesintisiz
önek boyunca ilerler; ilk recent/invalid tarihte durur ve global latest seq
korunur. Her ilanın floor'daki son immutable upsert/tombstone temel kaydı ve
bütün sonraki revizyonları kalır. Silme+gc cursor atomic batch/CAS ile korumalı;
concurrent pass state'i değiştirirse eski pass değişiklik yapmaz, failed batch
cursor/silme rollback olur. listings.first_seq/güncel ilan/outbox etkilenmez.
Mevcut catalogue_listing_seq covering indeksi yeniden kullanılır; live EXPLAIN
primary-key bounded range+covering lookup gösterdi. Katalog kısmı<=6 SQL, registry
ile<=15; backlog silme20/hour ceiling, CPU10ms/yük kapasitesi ölçüm bekler.
Metadata floor+1 ve expired409 sözleşmesi korunur. Delta/bootstrap response öncesi
floor tekrar kontrolü ve arada kaybolan payload tespiti yanlış başarılı cursor
ilerlemesini engeller. Mobil bounded1KB endpoint-specific409/tek no-cache metadata
+bootstrap retry önceki132 Flutter/136 core full kontrolünde ve actual-config
APK'da doğrulandı. Son server değişiklikleri86 native full/dry-run/deploy;
base/ilk yayın/latest/tombstone/recent+invalidtimestamp/partial resume/CAS/rollback
ve page-read prune race kontrolü içerir. Üretim6f148686-305f-4405-8815-956786cdd006;
canlı floor0/gc0/listing20/change40 ve no-cache API20/40/latest40/oldest1+304 geçti.
90day eski canlı kayıt olmadığı için üretim silme sonucu veya bakım CPU/yük
kanıtı yok; sahte production veri yaratılmadı. Eski temel kayıt/ilan minimumu ve
bildirim dedupe tombstone kapasitesi, source/AI/FCM/release kapıları hâlâ açık.

Bu kontrol noktasında actual Firebase/API Android debug APK yeniden derlendi:
223497245bytes, Gradle62.1s. Changed4 analyze temiz; emulator kurulum/çalıştırma
bu build için yapılmadı. Eski APK build çıktısı yenisiyle güncellendi; debug
signing/AdMob test fallback ve fiziksel FCM/iOS/release sınırları aynıdır.

Kaynak erişimi incelemesi2Oct: Windows'tan public Kariyer Infrastructure ve
IlanDetay JS okuması Worker'ın API root/iki POST adresiyle aynı rotaları gösterdi;
RSS açıklaması başlık tekrarı, detail HTML koşulları SSR olarak vermiyor. Bu
kontrol doğru rotaya işaret eder, Worker522 nedeni/egress başarısı kanıtı değildir.
docs/SOURCE_REGISTRY.md Cloudflare/30dk/legacy pilot durumuna hizalandı; eski
Google backend zamanlaması işletim mimarisi diye sunulmaz. Terms/robots/model
örnek kalite ve Worker detail erişimi hâlâ açık; bypass/proxy/fake detail yok.

Şehir kimlikleri: aynı Dart81 şehir havuzu Worker'da city:<folded-name> ID/label
olarak API taxonomy cities/cityValues içine eklendi (version1 additive). Node
contract tüm listenin Dart const kaynakla eşitliğini ve81 ID/label predicate'i
kontrol eder; shared corpus31 case'de city code/case/Türkçe, farklı il, district,
unknown ve bilinen alternatif durumları Dart/Worker ve SQLite'da aynı sonucu verir.
Known city key coarse anchors+exact matcher aynı; ilçe/"Merkez" kaynak konumu il
olarak tahmin edilmez, unknown strict push üretmez. `canonicalCity` bütün
caller'larda ID/diacritics kabul eder; UI cityLabel kodları Türkçe isim gösterir,
eski düz text label'ı korur. Create/edit/summary/quick chip ve city-loading
aynı görünen değeri kullanır; kriter payload'ları topluca yeniden yazılmaz.
Migration0013 eski literal cities:city:* anchor'larına wildcard koruması ekler;
heartbeat aynı normal cities:* anahtarını kurar, preference version/baseline ve
saved search korur. Partial fanout reset, completed events/outbox UNIQUE korunur.
Native93/full core143 ve son34core/2UI kodlu şehir akışı geçti; normal390px ve
320px1.3x form ve SQLite kriter korunması doğrulandı. Live81 city/5 education
sözlüğü ve20/40/meta304 geçti. Diğer meslek/kurum/kategori kimlikleri, dictionary
major/wire version migration ve gerçek kaynak/FCM/capacity kapıları açık.

Şehir kontrol noktası tamamlandı: son Flutter132 full, core143 full (+son34core),
Worker93 full; changed5 analyze/diff-check temiz. Actual API/Firebase debug APK
223499557bytes/47.7s derlendi; cihaz kurulumu veya FCM teslimi bu build'de yok.
İlk UI koşusunda düz label normalizasyonu eski yazımı değiştirmişti; cityLabel
şimdi yalnız kodu label'a açar ve plain legacy yazımı korur. Coded-city UI
akışı ardından2targeted+tam132 tekrar geçti; atlanan assertion/test yok.
