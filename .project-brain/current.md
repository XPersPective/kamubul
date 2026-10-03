# Mevcut Mimari — KamuBul

3 Ekim 2026. Yalnız çalışan kod ve doğrulanmış dış durum; hedef `target.md`,
uygulama sırası `tasks/`, gerekçeler `decisions/`. Önceki kontrol noktaları Git'tedir.

## 1. Üretim durumu ve gerçek sınır

3Oct user resumed: Android emulator acceptance authorized, iOS/Mac excluded
from this work, production signing/publishing folder migration authorized.
Target and C-042 reconciled; earlier physical/iOS-only blockers superseded.
Unique permanent RSA2048/JKS kamubul-upload and key.properties now live at
D:/AppPublishing/apps/kamubul/credentials/android. User+SYSTEM ACL; second
copy at user .codex/secure-backups/kamubul/android hash-equal, not independent
encrypted/off-device backup proof. Gradle defaults to external publishing root,
supports KAMUBUL_SIGNING/APP_PUBLISHING_ROOT and resolves relative storeFile
there; no debug fallback. Firebase service-account/client copies hash-verified
in app credentials/firebase, original Downloads preserved. Client-only
android.defines.json includes actual API and existing publisher contact;
server key never goes into APK. Publishing README app record/tr-TR draft
title/short/full description/privacy copy exist; Play app/certificate and real
AdMob IDs remain unverified, no store submission. Real obfuscated x64 release
APK built405.6s/24.6MB; check-android-release.ps1 verified signature against
exported public upload DER, expected package and debuggable=false. Permanent
certificate SHA256 B413E49E38562FA7CC83A787491F0CC8B2E1305CEE554BE639F387F210D244DA.
Profile with publishing client config built99.3s/53.1MB and installed-r5554
without data loss. Native onboarding rendered; latest initial draw30s689ms,
no new sampled app ANR, not a performance pass. Release-r was correctly
rejected for existing debug-signature mismatch; no uninstall/data clear.
Emulator foreground switched to unrelated app; package remained present but
enabled=3 disabled-user, causing MainActivity unavailable. Only own package
temporarily re-enabled for investigation; unrelated consent UI not accepted.
Own package restored to prior disabled-user state; shared emulator/data preserved.
Dedicated SDK AVD kamubul_release_check/emulator-5560 created without touching
other AVDs. Real signed release installed Success and onboarding rendered;
system UI/Google services also reported startup ANRs, so native flow not passed.
Own AVD rebooted with4cores/2048MB/software graphics; boot_completed1 observed.
SystemUI ANR persisted, Wait dismissed it; own native onboarding→home→detail→
settings→official sources rendered. Catalogue135 records at07:05UTC, source
notes match server metadata; catalogue includes retained device fetch fallback,
so135 is not D1-only coverage. Server readonly meta46 unchanged. Offline
airplane-mode1+force-stop/relaunch preserved135 cache with honest failure note;
airplane-mode returned0. am-W still timeout11.8s, not performance pass.
Server push remainedoff, no registry/fake production push.
Native Pro page exposed untranslated paywall keys. Startup now merges existing
ProLocalization with core via loadAppTranslations; focused regression1 and
full Flutter175 checks passed, changed2 analyze no issues.
Updated signed APK install-r5560 Success; own home/settings/Pro Turkish copy
and dark-theme/other-apps real catalogue native visuals verified. UIAutomator
idle observations resolve immediate screenshot/event-delivery races; no app
theme bug inferred from earlier mistap. Initial SystemUI/Google-service ANRs
and am-W13.7s timeout persist, not performance pass. Server push stayedoff.
Updated signed x64 APK built183.1s and same certificate/package/debuggable/
ZIP16KB check passed. Signed all-ABI AAB built414.5s/58MB; jarsigner verified,
public keytool certificate SHA256 equals permanent upload DER, llvm-readelf
LOAD alignment>=16KB for12 .so across3ABIs. 16KB-device runtime not tested.
Build Gradle daemon stopped before owned AVD restart; no build/test handle.
Play Console crazypenguin app-list `kamubul` search no results; new-app form
KamuBul/com.crazypenguin.kamubul/tr-TR/application/free prepared, package
availability explicitly confirmed. Legal policy/export checkboxes untouched;
action-time human approval pending, no app creation/upload/publish. Tab3 kept
for review; no other app was modified. AdMob current account still needs setup.
Own5560 emu-kill completed, owned launcher18188 and matching QEMU processes
absent. Official avdmanager delete reported errors: registration.ini removed,
owned .avd directory still present. Guarded PowerShell recursive cleanup was
rejected by automatic policy (no detailed reason supplied), so no alternate
delete attempted; residual C:/Users/rubicon/.android/avd/kamubul_release_check.avd
remains open cleanup. Shared5554/other apps/AVDs preserved; no production test
registration, fixture, inferred condition or push was written.
ZIP archive16KB alignment check added to same runnable script and passed;
All-ABI AAB ELF alignment passed as above;16KB device runtime remains unverified.
AdMob current browser account opens signup/terms, not an existing app console;
no account/financial contract accepted and no IDs fabricated or reused.
Fresh Cloudflare-only no-binding preview: Kariyer detail HTTP522/20115ms,
SBB blocked/416ms. Preview closed; no production write/AI/push/proxy. Official
source access/terms and typed extraction/quality still open. Free AI remains
configured; external provider/key/budgets have not been supplied.

Onboarding dört adımın başlığını Semantics header/liveRegion olarak sunar;
erişilebilir ad "Adım N / 4: başlık" taşır, görünen tasarım değişmez.
Gerçek AppTheme light/dark ile dört adımda labelled tap target ve Android48dp
guideline geçti; altı onboarding widget kontrolü ve changed2 analyze temiz.
Bu fiziksel TalkBack/VoiceOver veya açılış performansı kanıtı değildir;
bugünkü profile ve signed release bu semantics değişikliğini içerir.

App-open reklam onboarding guard'ı artık gerçek kamubul.onboarded kaydından
restoreAds ile yüklenir; main'de unconditional true yok. OnDone aynı policy'yi
true yapar. Eligible eski oturumlarda bile eksik onboarding reklamı engeller;
marker sonrası izin ve Pro koruması native-free üç Flutter unit check ile
doğrulandı, changed3 analyze temiz. Bu Google Play Games ekranının nedenini
kanıtlamaz; native ad teslimi/store release veya revenue kabulü değildir.
173 full Flutter checks passed; no live test/build handle.201cbe2 actual API/
Firebase profile55637541bytes/79.2s rebuilt, package identity checked and
installed on existing5554 (5558 no longer connected, not restarted).5554
had4339540KB data available and no previous KamuBul package. MainActivity
started, pid12370 alive; native onboarding rendered but ANR dialog observed.
events am_anr03:23:13.676 reports "failed to complete startup" for this process;
dumpsys lastanr misleadingly says none. exit-info has only isolated WebView
process kills, not main exit. Host free RAM~1.1GB. No source/FCM/release/latency
success claim; next diagnose actual native startup ANR, do not attribute it
to Dart/Ads without trace. Own temporary /sdcard screenshot removed; emulator,
app/data preserved. No privilege escalation or system/app deletion.
3Oct startup diagnostic: ActivityManager reports CPU pressure avg10=80.14%,
memory some/full avg10=16.44/5.87%; total CPU98%,85% kernel in ANR window.
Its own primary-pid stack dump aborted on deadline; exact own ANR file read
denied by normal ADB. No root/chmod or broad private bugreport used. Resource
pressure correlates with the failure, but the app root cause is unproven.
Own-app-only force-stop/relaunch preserved data: new pid13000, am start -W
timed out21756ms; Android later reported Displayed/Fully drawn52s432ms.
Native onboarding rendered without a new sampled am_anr entry; original
launch107s297ms remains a failure, second launch is not a latency pass.
Host free RAM~1.8GB on retry. Firebase native auto-init was unsuccessful;
code explicitly initializes with Dart FirebaseOptions only after push opt-in,
so that log alone is not proof of broken FCM configuration. No permission,
account or push created. Next require adequate-device cold-start/thread
evidence before changing startup code; physical release gate remains open.

Canonical mobil ayrıntı mevcut cache'teki summary text/quote/scopeLabel için
açılır kaynak alıntısı gösterir. Eşleşmeyen veya600 karakteri aşan alıntı
sunulmaz; kadro etiketi korunur, alıntısız özet düz metin kalır. Bu yeni
koşul çıkarımı veya AI kalite kapısı değildir. Dar320px/1.3x/light-dark aç/kapat
kontrolü geçti; değiştirilmiş iki dosyanın Flutter analyze sonucu temizdir.
172 full Flutter kontrolü (golden dahil) geçti; fiziksel release kanıtı değildir.

PRIVACY.md artık gerçek Cloudflare katalog/kriter upload/Queue/retention ve
çevrimdışı silme davranışını açıklar. Server-push ayarı arama adları/kriterleri
gönderildiğini ve offline silme retry'sini gösterir. Bu legal/store/privacy
release kabulü değildir; yayıncı destek ayarı dış derleme dosyasında mevcut,
mağaza beyanları ve posta kutusu teslim testi hâlâ doğrulanmamıştır.
Değişen Home açıklaması analyze ve16 alert/navigation widget kontrolünden
geçti. Android Gradle release gerçek key.properties alanlarına bağlıdır;
debug fallback yoktur. checkReleaseSigning APK/AAB paketleme yolunda eksik
ayar, standart debug alias ve eksik keystore'ı reddeder. Native eksik-ayar
kontrolü beklenen hatayı verdi, debug/profile imza kontrolü up-to-date geçti.
Native dry-run APK/AAB görev grafiği korumayı ve dört paketleme/sign hedefini
doğruladı; gerçek imzalı release artefact üretilmedi.
Önceki imza yokluğu artık dış yayın klasöründeki kalıcı anahtarla giderildi;
mağaza sertifikası eşitliği ve bağımsız şifreli harici yedek henüz doğrulanmadı.
Android checkReleaseContact release paketleme yolunda CONTACT_EMAIL zorunlu
tutar; yanlış yazım/example.com-net-org (subdomain dahil)/test-invalid-localhost
alanlarını reddeder. Native altı vaka geçti; syntax-only adres kabulü gerçek
destek posta kutusu/sahiplik doğrulaması değildir. Debug/profile fallback
geliştirme içindir; iOS release kontrolü ve gerçek destek adresi hâlâ eksiktir.
Native dry-run APK/AAB görev grafiği contact/signing korumalarını ve dört
paketleme/sign hedefini doğruladı; paket üretilmedi.
Değişiklik sonrası native debug/profile signing validation başarılıdır.

**Sunucuya geçiş tamamlanmadı.** Kalıcı Cloudflare API/D1/Cron yayında; Flutter
v2 katalog/cache ve FCM entegrasyonu vardır. Gerçek üretim 23 resmî RSS ilanı ve
46 immutable değişiklik taşır. İlanların tamamında detailState=unavailable,
full source text=0; 23 processing işi source-only completed. Liste başarısı
AI özet/typed uygunluk çıkarımı veya kapalı telefon bildirimi başarısı değildir.
Kariyer liste taze, ayrıntı yenilemesi başarısız; SBB/İŞKUR/ilan.gov blocked.
Telefon fallback/şehir çekimi ve eski Workmanager pilot kapıları nedeniyle durur.
Fake üretim ilanı/kurulumu/push yok; harici ücretli AI etkin değil.

Son readonly kanıt: canlı watermark46/catalogue23/appliedThrough46/detail GET,
missing detail404/conditional meta304. D1 son readonly Kariyer last_success
2026-10-02T17:21:08.812Z/ayrıntı hata notu; SBB blocked last_attempt17:24:08.873Z.
3Oct new readonly D1 SELECT4+23rows/0write/changed=false:23 listings/full_text0;
Kariyer processing last_attempt03:18:08.804Z,last_success02:45:08.812Z,detail
failure note. SBB blocked02:48:08.805Z/last_successnull; other sources blocked.
Migrations0001–0016; ownership triggerları önce installation0 ile doğrulandı.
Son queue deployment readonly installation1/outbox0, dispatch match/send
idle generation0 ve queue_jobs0. Bu kurulumun kaynağı/cihaz teslimi doğrulanmadı;
kimlik/token okunmadı. Önceki installation/outbox/facets0/0/0 tarihsel kanıttır.
Transient D1 7403 retry ile geçti; sonraki readonly state sorguları başarılı.

## 2. Kalıcı bulut ve güvenli yapılandırma

- Worker `kamubul-api`: https://kamubul-api.devx8585.workers.dev;
  son CLI deployment version `3e8bcf33-45e5-4200-9a4d-b1554c674628`.
  D1 `kamubul`, UUID `371092dd-2cc7-487f-b971-84c2499bbc7d`, EEUR/DB;
  migration0001–0016 remote. Free $0 plan önce konsolda gözlendi, upgrade yok.
- Kalıcı Queue `kamubul-work`, ID3eb1ec0a4296443eb552a240dac77ec4;
 17:00:46.689Z oluşturuldu,24h retention seçildi. CLI producer/consumer
 kamubul-api1/1 doğruladı. WORK_QUEUE binding; consumer batch1/concurrency1/
 retry0. Migration16 dispatch_state+daily_usage.queue_jobs.3000 UTC daily
 reservation; AI sayacı ayrı. Mesaj kind+generation, kişisel bilgi yok.
 Generational3dk lease/dedupe, matching mevcut10owner page, send max4instant
 veya ilk3 içindeki digest; dördüncü instant-only. Chaining/Cron recovery,
 kota/transport sonrası D1 iş korunumu. ADR-003 kapsamı/gerçek sınırlar.
 Yerel sequential Queue kontrolü100/1000 alıcıyı36/351 görevde boşalttı;
 10k'da3000 günlük rezervasyon korundu,7996 injected send/2004 pending kaldı.
 Stage/cleanup D1 failure lease recovery ve duplicate korunumu test geçti.
 Bu Cloudflare CPU/Queue operasyonu veya cihaz teslimi ölçümü değildir.
- `workers/wrangler.jsonc`: AI binding `@cf/meta/llama-3.1-8b-instruct`,
  AI_DAILY_JOBS20, source interval30dk, Cron her dakika, observability%10.
  mod3 kaynak/AI/expiry, matching, sending slotları ayırır; her aşama3dk.
  Kaynak slotu yalnız bir kalıcı batch girdisini işler:23 giriş yaklaşık69dk
  ve batch sonrasında30dk bekleme demektir; tam refresh30dk garantisi yok.
- Firebase `kamubul-3ae6e`, Spark $0, FCM HTTPv1 açık; Android
  `com.crazypenguin.kamubul`, appID `1:1003012781397:android:c474608bf0e36534ae2bdc`,
  sender1003012781397. Sender IAM yalnız Firebase Cloud Messaging API Admin.
  FCM_CLIENT_EMAIL/FCM_PRIVATE_KEY Worker Secrets; Google OAuth gerçek key ile
  kabul edildi, cihaz gönderimi ve Cloudflare signing CPU kanıtı değildir.
- Wrangler OAuth kullanıcı onayıyla Windows keyring'de; Worker/D1/AI ve
  account/user read. Secret/key/token Git/Brain/log/APK'da yok. Ignored Android
  google-services.json ve `.tmp/firebase-android.defines.json` client config'dir.
- Eski dev Worker dashboard'da yok; dev D1 cleanup doğrulanmadı.
  Billing/analytics/KV kapsamı genişletilmedi; permission403 tüm hesabın
  erişilemezliği veya CPU testi başarısızlığı olarak yorumlanmaz.

## 3. Worker veri akışı ve kalıcı işler

SBB PDF metin yolu mevcut AI binding'in native toMarkdown dönüşümünü kullanır:
sabit resmî ilanDetay.aspx adresi, PDF magic,25s/3MiB getirme,45s dönüşüm ve
120KB UTF-8 çıktı sınırı. Raw SHA256+reader version başarılı metni cache'ler;
aynı belge tekrar dönüşmez, yalnız PDF metadata değişimi aynı metin için yeni
summary işi açmaz. Mevcut rate_limits tablosunda atomik20 UTC günlük dönüşüm
rezervasyonu summary AI sayacından ayrıdır; başarısız dönüşüm de sayılır.
Boş tarama/hata önceki başarılı metni silmez; OCR veya sayfa sayısı sınırı yok.
162 native Worker kontrolü ve dry-run geçti; e284e590 kalıcı deployment sonrası
canlı46/23/applied46/detail/404/meta304 kontrolü geçti. AI-only remote preview
supported() PDF=true/28 format gösterdi; preview kapalıdır. Bu gerçek belge
dönüşümü, başarılı SBB erişimi, PDF kalitesi veya Free CPU ölçümü değildir.

SBB liste parser'ı gerçek kaydedilmiş HTML'deki class attribute boşluklarını
okur. Mevcut55 etiketli liste satırında kurum/başlık/kategori/start/deadline
gold değerleriyle eşitlik ve3-row fixture geçti;158 Worker native test.
Türkiye UTC+3 civil başlangıç/end-of-day, açık yıl çelişkisi unknown, implicit
yıl geçişi ve leap-day/uppercase EKİM kontrolleri var. Bu liste parser kanıtı
AI typed extraction precision/PDF veya başarılı Cloudflare SBB egress değildir.

`workers/src/{sources,pipeline,criteria,worker,fcm}.js` runtime dependency'siz
Cloudflare uygulamasıdır. Official host/redirect/size/timeout kontrolleri,
source lease/cursor/semantic hash/unique identity ve önceki başarılı içeriği
koruyan failure davranışı bulunur. Kariyer API/RSS ve SBB list adapter vardır;
SBB PDF metin okuyucusu vardır; OCR ve120KB üzeri kaynak okuyucusu yok. Windows'taki resmî adapter aynı
ilanın11 kadro/7113 karakter ayrıntısını okudu; bu Worker egress kanıtı değildir.
Public JS API rotalarını doğrular, RSS/SSR ayrıntı koşulu içermez. WAF/login
bypass/proxy ve yerel ayrıntıyı üretime kopyalama yapılmadı; terms kapısı açıktır.

D1 immutable catalogue seq/upsert/tombstone ve first_seq atomiktir. first_seq
abonelik baseline için log retention'dan bağımsızdır; yeni arama eski ilanları
push yapmaz. Versioned processing UNIQUE(listing/hash/contract_key), pinned
provider/model/extractionRevision, per-listing lease, latest reprocess intent
ve superseded guards vardır. `tool/reprocess-ai.js` max5 explicit ID, default
readonly plan/--apply; eksik source text çağrı başlatmaz. Başarılı aynı hash
model config değişti diye tekrar ingestion inference yapmaz; summary-only
reprocess yeni-ilan event'i üretmez. Model değişimi yarım işi karıştırmaz.

AI extractionRevision2:120KB UTF8→12KB kayıpsız chunk, kalıcı progress; bütün
chunk alıntıları bounded reduction'a gider. Request serialized24KB, en çok8
quote/grup, ara çıktı en çok yarım grup, final3–5; orijinal chunk özetleri
korunur. JSON Mode/temperature0/output1024/rejectIfBusy/45s logical timeout.
Model yalnız30–240 karakter exact quote seçer; native kaynak doğrulaması,
dedupe ve source position scopeLabel uygular; cross-position quote birleştirmez.
Unknown fields veya model etiketi uygunluk kararı değildir. Typed extraction,
paraphrase ve >=50 örnek/kaynak precision>=0.95/recall/coverage kapısı kapalıdır.

Provider3036 günlük kota→durable quota_wait/sonraki UTC gün; attempt/lease ve
chunk progress korunur, application günlük budget kapanır.3040 busy ayrı
bounded retry/max5; timeout inference iptal garantisi değildir.20 request/day
sayacı gerçek Neuron muhasebesi değildir. REST pilot14KB/8kadro/3call/5 scoped
quote35.8426 Neurons; bütün karşılaştırma18 girişim/17 HTTP200/1 timeout,
791.6394 bilinen Neurons (timeout tüketimi bilinmiyor). Bu memory/REST kanıtı
Workers Free CPU/egress/10k kapasite veya üretim AI başarısı değildir.

## 4. Eşleştirme, bildirim ve API

Typed SearchCriteria v2: AND aynı kadroda/OR alternatif kadrolarda/ANY arama;
match/no_match/unknown, strict unknown push yok. Yaş+asOf tüm olası doğum günü
aralığıdır; inclusive min/max/reference/birth bounds, completed years ve
29Şubat→1Mart; partial overlap/conflict/malformed/unsupported calculation
unknown.366day freshness; legacy referanssız yaş1970 olarak unknown kalır.
77 ortak Worker/Dart/SQLite case ve144 enumerated-birthday oracle vardır.
Kaynak KPSS type/score/year malformed/range/non-finite veya not_required ile
çelişkili ise kriter filtresinde unknown olur; JS numeric-string coercion yok.
Diğer alanın kesin no_match sonucu ve geçerli alternatif kadro korunur.
176 native Worker/195 core test ve changed2 analyze/dry-run geçti;3e8bcf33
deployment sonrası canlı46/23/applied46/detail/404/meta304 doğrulandı.
172 full Flutter test,77-case SQLite projection ve goldens dahil geçti.
Bu extraction precision veya actual FCM delivery kanıtı değildir.
AgeAsOf freshness bugün/<=366 takvim günü İstanbul UTC+3 pilotuna göre;
00:00–03:00 bugünün tarihi future sayılmaz,367+ gün ve gerçek gelecek unknown.
Source reference/birth bounds civil gün, deadline/publishedAt mutlak an kalır.
81 city:<folded-name> ve5 education:* kimlik/label/alias sözlüğü canlıdır;
meslek/kurum/kategori identity/wire version migration bütünü tamamlanmadı.

Registry authenticated own-installation PUT/DELETE, <=32KB criteria payload,
version/effective baseline ve facet set-diff; secure credential ack öncesi
HTTP yok. Migration0015 farklı secret ile concurrent initial insert'i tüm batch
rollback/401 ile reddeder; hash değişmez. DELETE aynı statement içinde hash
kontrol eder. UPSERT version NOT NULL precondition stale read'i batch rollback/409
yapar; aynı version ile yeni kriter geri yazılamaz. Mobile409 eski heartbeat
cache'ini geçersiz kılar, aynı identity/payload ile bir kez retry; tekrar conflict
failed ve sonraki sync eligible. Normal heartbeat/token rotation version ve
pending outbox'u değiştirmez. Facet coarse superset+exact predicate,10 candidate/4 empty facet
slot, covering index ve kalıcı cursor; broad searches wildcard. Outbox
durable unique event, instant/digest/quiet/deadline, token/version/criteria
send-time recheck, per-installation send lease ve invalid-token race guard.
Digest İstanbul18:00,1/day/10 ilan; backlog sonraki güne kalır, deadline'da
expired. FCM accepted cihaz teslimi değildir, ambiguous send timeout tam
exactly-once sağlamaz. TTL/APNs expiry en çok24h/deadline.

Public v2 meta/taxonomy/listings/changes/detail, private installation/history
ve v1 geçiş API'si bulunur. History accepted-only sequence/pinned watermark,
own-record auth, after/appliedThrough/hasMore; accepted versus received UI
ayrıdır. Public Cache API allowlist60s/taxonomy300s, sorted cursor keys/ETag;
Authorization/Cookie/private/no-store bypass, cache hatası origin'i kesmez.
Cache304 Worker request kotasını kaldırmaz. Catalogue en çok50 contiguous
record/1.8MB; single oversized413 cursor atlamaz. Mobile HTTP sınırları ve
401/403/redirect/oversize failure guards mevcut; key/key-value loglanmaz.

Hourly:59 bakım send slotunu kullanır (o aralık6dk).120day stale owner lease
recheck ile20 outbox/50 facet/owner-child cleanup; heartbeat/live lease korunur.
100 expired rate counters/30 eski günlük budget,90day accepted/terminal20row
payload archive dedupe identities/history sequence/digest bağlarını korur.
Catalogue90day contiguous floor +50 sweep/20 delete, atomic CAS; floor'daki
her ID'nin son temel kaydı ve sonraki revizyonlar kalır. Old pin409/tek metadata
retry+bootstrap, page-read/prune race guards vardır. Gerçek backlog CPU/rows,
long-lived tombstones ve10k kapasite açık; native query plan cloud yük değildir.

## 5. Flutter cache, profil ve ekranlar

SQLite schema9: legacy listings/favorites/searches, remote_catalogue,
cursor/meta/ETag/last_success, persistent bootstrap staging, isolated
remote_details/detail_epoch. Origin(path dahil)+generation A→B→A stale response
reject; visible cache complete bootstrap'e kadar korunur. Delta page+cursor
atomik,20page/refesh resume; full bootstrap frozen watermark, explicit null,
missing favorite inactive, server seq reset ve old-pin recovery korunur.
Son başarı yalnız tüm watermark bittiğinde ilerler. Cache-first/offline/stale
UI source metadata'yı gösterir; phone fallback başarı=server başarı değildir.

remote_details son20/8MiB/single2MiB, main cursor/favori/search mutasyonu yok;
positive safe listingRevision yeterliyse cache first, newer fetch, network
failure eski detail açık uyarıyla gösterilir. Generation+detail epoch reject,
newer canonical delta/tombstone eski HTTP'ye üstündür; normal interrupted
bootstrap eski cache'i korur. Same pending/open tap id+revision tek route/request;
newer tap geç HTTP'yi bastırır, higher revision replaces old route, Back reopen.
Route lifetime startup refresh/client close'u bekletmez. History tile canonical
API detail açar. Cold404 versus503, cache-empty/offline tap yolları testlidir.

Home normal/saved/legacy URL-tap ortak _listingPage canonical kayıtta cache
OfficialListingPage açar, removed saved inactive gösterilir. Guide canonical
kayıtta kaynak HTTP/FutureBuilder başlatmaz; özet+aynı cache detay erişimi.
Detail ayrı requirementGroups kartları, city/education labels, KPSS ve age/date
bounds, unknown/source-only açıklama, provenance temelli AI özet başlığı ve
52dp sticky official CTA içerir; ilk100 group render sınırı açık. Yeni evidence
schema uydurulmadı. allListings JSON1 gerektirmeyen50row projection, same URL
multiple canonical identity unknown; aiProvenance korunur.

SavedSearch SQLite filters alanında version2 zarfı; legacy/backup schema1
korunur, UserData schema2 typed criteria taşır. Invalid criteria bütün olarak
registry'den dışlanır, apply/rename/mode engellenir, edit onarır. Tek create/edit
formu age+ageAsOf, score/type/year, <=10/field multiple autocomplete/20 öneri,
keyword title/full/name ayrımı; pending text save'i engeller. Cache-derived
occupation/institution önerileri ek model/ağ çağrısı yapmaz. Stable search ID,
manual/quick filters aynı matcher, unknown ayrı Şartları kontrol et opt-in.
SBB wire sbb ve legacy kamuilan_sbb refresh/status/label/backup tanınır;
canonical wire state alias'a üstün, existing IDs/URLs topluca rewrite edilmez.
Kart geri sayımı ve geçiş kodundaki yerel deadlineReminder, gerçek deadline
anında sona erer; yerel takvim günlerini UTC date-only farkıyla sayar. Kısmi
24h truncation yanlış Bugün/erken hatırlatma üretmez; kaynak saati gün sonuna
ötelenmez. Ertesi gün/son dakika/aynı gün expiry/bounded3day/UTC testleri vardır.

İlk açılış4 skippable adım; Atla yalnız onboarded marker yazar, arama/izin
oluşturmaz. İlanları bul shared SearchCriteria doğrulamasından sonra ilk yerel
aramayı kaydeder: age+current ageAsOf, canonical81-city autocomplete/max20,
KPSS uppercase/type validation; score/year ve diğer koşullar mevcut editörde.
Save single-flight, controls disabled, failure alanları korur/retry/skip açık;
controller dispose ve keyboard-aware ListView/expanded primary button. Server
criteria upload açıklaması vardır; onboarding native permission istemez,
bildirimleri kullanıcı ayrıca açar. Skip/save marker AppHome.onDone'da saklanır.
5 widget check: skip/current-date/error/busy/city+KPSS/320px1.3x+keyboard.
Onboarding ve editörün bugün doğrulaması mevcut wallClock/dayKey ile Türkiye
takvimini kullanır; cihaz saat dilimi aynı referansı değiştirmez. Kayıtlı arama
özetinde yaşın referans tarihi görünür. Editör366gün/future unknown ve strict
push açıklaması verir; doğrulama yalnız tarihi değiştirir, yaşı tahmin etmez.
Normal/320px1.3x düzenleme testleri bu davranışı ve eski tarihi korumayı denetler.

Template master7101480 fetch güncel; core-v1.0.1 OtherAppsPage/Repository reuse.
Keşfet5th destination + settings Diğer uygulamalarımız; ilk4 tab index korunur.
OTHER_APPS_URL default napp_apps/HEAD/apps.json, explicit empty disables;
HTTPS/URL guard, app-lifetime repository/24h SettingsStore cache ve real
DoctorFilter tr/en embedded fallback, own package exclusion. Live catalogue
200/schema1/1record. Shared repository256KiB streaming cap/no redirects/total
timeout+abort; rejected/cancelled body cleanup nonblocking, owned client closes,
injected client remains caller-owned. Corrupt cache shape/type/date fallback,
future date refresh ve default order0 omission near-cap offline retention.
Core patch0.0.1+1 fixed tagcore-v1.0.1; old tags/pro/ads unchanged. Shared119
workspace tests/analyze passed, independent review findings fixed. Actual new
repository GitHub GET catalogue_count1, no injected/embedded fallback. Yeni
dependency yok; package Git metadata preserves hosted ^0.0.1 constraints.

## 6. Cihazdaki bildirim ve güvenli kurulum kimliği

FirebasePush initializes without requesting permission; token/refresh,
foreground, onMessageOpenedApp/initial tap. Payload bounds/HTTPS/event64hex;
receipt secure ack sonrası local foreground render, duplicate/disabled yok.
OS eventID first8hex stable int+Android tag; iOS otomatik foreground kapalı,
local plugin tek sunucu. SecurePushStore awaited atomic batch: Android
Keystore AES-GCM/noBackupFilesDir, iOS ThisDeviceOnly Keychain. FIFO per-owner
sync/token/delete/enable, ack öncesi HTTP yok;401/403 new identity bypass yok.
Old plaintext state secure write başarılı olmadan silinmez, fallback plaintext yok.

Private history same FIFO, no new permission/token/identity; redirect off,
256KB/20s/5page, origin+installation scoped atomic secure after/pin/records.
100 cache/200 receipt IDs/120KB UTF8 target; partial resume,409 single reconcile,
clear-history cursor/dedupe tutar, disable server cache siler. History feed eski
OS notification'ı yeniden göstermez; accepted=Servise iletildi/received=Alındı.
Android native secure write/reopen/plaintext cleanup API36/x64 emulator'da
önce geçti; actual process restart/backup restore/iOS/physical FCM kanıtı yok.

## 7. Doğrulama, geçiş kodu ve sonraki kapılar

3 Ekim mevcut emulator-5558 (flutter_emulator, kullanıcıya ait; kapatılmadı/
silinmedi) başlangıçta682728KB data alanı ve yaklaşık1.7GB host free RAM
taşıyordu. Latest API/Firebase profile x64 build ve install başarılı;
onboarding Atla ve gerçek ilanlı home light/dark görüntüleri alındı. Home135
kayıt gösterdi; bu retained phone fallback karışımıdır, remote-only proof değil.
Keşfet native ekranında otherApps.title literal göründü: main boş sözlük
kullanıyordu. Mevcut NappTranslations.loadCore startup+required app field ile
bağlandı; yerel generator template aynı root fix'i aldı.16 navigation/widget
test ve changed2 analyze temiz. Yeni profile55637541bytes/88.8s; package ID
apkanalyzer ile doğrulandı, install-r başarılı, native dark Keşfet ekranı
Türkçe başlık+gerçek DoctorFilter kartını gösterdi. Screenshot.tmp altında;
ephemeral /sdcard dosyaları kaldırıldı, app/data/emulator korunur.
172 full Flutter test geçti;3Oct template fetch master7101480/0 behind/clean.
Google Play Games profile ekranı araya girdi; hesap oluşturulmadı, Back ve
KamuBul resume ile geri dönüldü. Nedeni kanıtlanmadı. Host free RAM yaklaşık
800MB'a indi; latency/physical release/FCM/Pro-store kabulü verilmez. Test
AdMob kimlikleri profile içindir, production AdMob/signing gate'i hâlâ açık.

2 Ekim16:33UTC binding'siz remote preview aynı resmî Kariyer detail'de20.240ms
HTTP522/SBB579ms blocked; session kapalı, prod write/deploy/AI/FCM yok.
Production readonly23/23 unavailable; Kariyer yeni tur processing16:18attempt,
last_success15:45;0write. Kaynak full-detail engeli güncel olarak doğrulandı.
Yerel wide-match tool100/1000/10000 kurulumda11/101/1001 matching round,
max15SQL/round ve eksiksiz/idempotent pending outbox doğrular.10k SQL sayısı
34004→15004; ten-owner indexed JOIN enabled/search/version/baseline birlikte
okur. EXPLAIN full owner/search scan yok; unrelated/unknown/new-subscription/
multi-facet regresyonu geçti.149 native/dry-run/deploy doğrulandı. Scheduler480
match/456send günlük Cron slot üretir; eski yalnız-Cron yolunda10k eşleşmede
ideal steady-state gönderim iş yükü21.93gün. Fast10k kabulü geçmedi; cloud
CPU/D1 counter kanıtı değildir. docs/FANOUT_CAPACITY.md/PB-021 sonraki kapıdır.
cdc82483 sonrası live readonly watermark46/catalogue23/applied46/detail/missing404/
meta304 geçti; sources Kariyerok ve diğer3blocked. Nonempty cloud fanout/
OAuth send CPU/gerçek teslim ölçülmedi; bu eski sürümde Queue yoktu.

Sender pending/leased backlog root sort iki indexed LIMIT1 candidate ile
sınırlandı; due/id sırası ve expired/live lease korumaları testli. Atomik owner
claim güncel kayıt döndürür; final opt-out/version/cap kontrolleri durur.
Extended local sender probe10k max8SQL,80000 total,p95/p99=1.34/1.78ms;
injected sender, actual FCM/OAuth/CPU/cihaz kanıtı yok. Remote readonly EXPLAIN
iki outbox_due index'i0read/0write/changed=false doğruladı; runtime scan değil.
Leased branch canlı lease ziyaret sınırı hâlâ var. Cron tek send davranışı
ve456/gün Cron üst hızı aynı;150 native/dry-run/deploy geçti.6deecc4f sonrasında
live readonly46/23/applied46/detail/missing404/meta304 geçti.

Yeni Queue dispatch156 native/dry-run/deploy/remote migration16 geçti;
b41b6716 live readonly46/23/applied46/detail/missing404/meta304 geçti.
Producer+consumer CLI doğrulaması actual nonempty Queue/CPU/FCM kanıtı değildir.
Yalnız-Cron456 sınırı toplam mimariyi artık tanımlamaz; shared task bütçesi ve
cloud Consumer CPU/10k daily cost/delivery ölçümü henüz açık.

Son doğrulama:171 Flutter full,181 core full,156 Worker native; changed Dart
analyze ve diff-check temiz. SQLite race tests:
cross-owner initial registration bütün dependent rows'u korur; stale same-owner
heartbeat409/newer criteria korunur/retry yeni version; delete/recreate hash
guard. Mobile bounded retry/cache invalidation/identity preservation testleri.
Normal/saved canonical cache, guide offline, SBB freshness/conflicting aliases,
backup roundtrip,320px1.3x light/dark/unknown/malformed/nav testleri vardır.
Yeni canonical detail dört phone/tablet/light/dark/1.3x düzeninde üst/koşul
bölümleri için8 golden taşır; gerçek AppTheme ve48dp CTA hit-test kontrolü.
Golden test SDK'nın Roboto regular/medium/bold ve MaterialIcons fontlarını
package_config'deki Flutter root'tan yükler; host fontu/yeni dependency yok.
8 canonical +3 legacy reference gerçek Türkçe gliflerle görsel olarak incelendi;
canonical fixture education:bachelor ve Lisans label assert kullanır. Telefon/
tablet/light/dark/1.3x layout kontrolüdür; physical premium kabulü değildir.
Önceki70023118 sürümü dashboard19 invocation/0 subrequest/0 error,
CPU P50/P90/P99=2.04/5.26/6.29ms. Aynı sürüm15:54 scheduled source/expiry/AI
slotu2ms CPU/748ms wall/outcome ok; idle/due kontrolü, başarılı detail/AI
işleme veya10k kanıtı değil. Ayrıntı docs/WORKER_FREE_PILOT.md.
Latest actual Firebase/API x64 debug116610754bytes/141.3s (core catalogue patch/
age calendar/onboarding/registry/deadline code), cihaz kurulumu/visual proof yok.
171 Flutter/changed analyze passed with pinned core patch; real catalogue count1.
Önceki universal debug
223536538bytes/25.7s ve x64 debug89653916bytes/20.5s. emulator-5556 install-r
storage error, yeni debug kurulmadı; unrelated
files/apps veya kullanıcı verisi silinmedi. Profile actual-config x64 APK
44286151bytes/49.8s derlendi. Streamed install session abandoned; non-streaming
tekrar da storage355687827bytes gereksinimiyle reddedildi.5556 old codePath/
lastUpdateTime04:30:14 korunur, yeni sürüm kurulmuş sayılmaz. Ayrı geçici
kamubul_pilot AVD, mevcut API36/Google Play/x64 imajıyla C: task tmp altında
oluşturuldu;5558 boot tamamlandı/profile install Success, MainActivity önde ve
onboarding gerçek glyph screenshot alındı. Android system ANR dialogu var;
host free RAM812712KB/total16471276KB ölçüldü, temiz visual/latency kabulü yok.
Yalnız owned5558 emu kill ile kapatıldı; resmi avdmanager delete kamubul_pilot
başarılı, exact task AVD directory/ini yok ve owned PIDs yok.5554/5556 veya
unrelated files/apps silinmedi.5556 kendi KamuBul debug süreci veri silmeden
restart edildi; flutter attach actual defines ile sync41.9s yaptı, sonra
VM connection lost/CLI terminal. App process alive/no sampled AndroidRuntime
FATAL; yeni Dart UI/hot-restart doğrulaması değildir. Fiziksel cihaz yok.

`refreshCatalogue` source failure/stale36h/no API için hâlâ phone fallback;
refreshKariyerCity ve local-only guide/detail automatic source paths kalır.
main registerBackgroundAlerts/Workmanager12h,<=5city fetch/local new-match/
digest/reminder üretimi geçiş kodudur. Canonical cache yolu düzeltmesi global
remote-only cutover değildir; PB-019 source/sync/push kapılarından sonra sökülür.
`backend/` native Dart/FirestoreStorage/25parallel sender eski deploy edilmemiş
referanstır; aktif Workers runtime değildir. Ortak kamubul_core matcher/parser/
cache/validation mobilce kullanılır ve topluca silinmez.

ADR-002/PB-022: own external API gerçek Free daily provider quota fallback ve
ayrı kullanıcı criteria assistant için onaylı. Provider/model/key/ayrı günlük+
aylık bütçe verilmedi; etkin API/gerçek assistant yok. Elle form korunur;
mevcut rehber serbest AI sohbeti değildir. FCM-less auth-only setup, bounded
requestId/baseVersion draft/apply/cancel/delete ve ayrı bütçeler henüz yapılmadı.

Açık kapılar: permitted source full-detail/PDF/terms; >=50/source grounded typed
extraction precision/recall/summary coverage; actual Free CPU/OAuth/AI/neuron
accounting/10k D1/fanout/backlog; physical foreground/background/terminated/
force-stop/off/token/delete/digest/history/reinstall/backup; iOS Mac/APNs;
release signing/AdMob/store purchase/restore/accessibility+visual response.
Kanıt dosyaları: docs/SOURCE_REGISTRY.md, AI_MODEL_PILOT.md,
WORKER_FREE_PILOT.md, CLOUDFLARE_FCM_YOL_HARITASI.md. Tüm hedef tamamlanmadı.
