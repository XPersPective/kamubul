# Current Architecture

## SA-015 implementation checkpoint — 16 Ekim
- Native AtomicFile/inexact receiver/MethodChannel, ayrı opt-in UI ve açılış/save/unsave/refresh/resume uzlaştırması yazıldı. Yerel okuma ve native hata readback'i sıralı; kapalı kanal gönderilmiş sayılmaz, retry kullanıcı isteğini korur.
- Bağımsız kod incelemesinin beş bulgusu düzeltildi; gerçek Android reboot/delivery/tap ve keyboard/TalkBack hâlâ açık. Eski aşağıdaki native-yok snapshot'ı tarihsel; güncel dosya/görev ve `docs/SA015_ACCEPTANCE_2026-10-16.md` esas alınır. Üretime gönderilmedi.

Son bağımsız gözlem: 2026-10-15. Önceki Project Brain snapshot'ı Git geçmişinde; eski PASS yeni kabul yerine kullanılmaz.

## Runtime
- Flutter Android1.2.2+17, com.crazypenguin.kamubul; Cloudflare Worker/D1/Queue; Firebase yalnız FCM.
- Telefon yalnız API/cache; Türkiye/Türkçe hedef, iOS ertelenmiş. napp_core/pro/ads korunur.

## 16 Ekim akşam yayın
- Worker 5a24d9a2: Asistan kesik JSON düzeltmesi (900 token, json_object, reply kurtarma); wrangler vars canlı sağlayıcıyla eşitlendi (evren-llmapi / qwen3.8-flash-next). Canlı readback temiz answer/criteria.
- Android 1.2.3+18 (SA-015 hatırlatma, SA-017 kadro, SA-018 not, Asistan düzeltmesi) imzalı AAB dahili teste yüklendi; Console readback: dahili kullanıcılara açık, kod 18. Üretim 1.2.2/17 değişmedi.

## 17 Ekim üretim gönderimi
- Son kullanıcı talimatıyla mevcut internal18 Fastlane üzerinden production'a gönderildi; changes_not_sent_for_review=false commit başarılı. Ayrı Play API edit readback: production/internal1.2.3/code18/status completed; Google public onay/erişim henüz gözlenmedi.
- Golden fixture yayın tarihi sabitlendi; Flutter222/222, Worker299/299, analyze0issue; bağımsız kod incelemesi yeni blocker/major bulmadı. AAB hash/imza/ELF16KB/üretim defines doğrulandı. `docs/RELEASE_18_2026-10-17.md` büyüme işleri ve açık ürün kabullerini ayırır; birincilik hedefi tamamlanmış değildir.
- Devam turunda SA-025 yeni Türkçe aday bağımsız PASS sonrası Fastlane text-only review=false commit ile gönderildi (04:50:15TR); ayrı API eşitlik true, yedi görsel değişmedi, production/internal18 korundu. Public browser önceki metin/7Ekim/code17notları gösteriyor; yeni onay/erişim henüz yok. SA-021 gerçek capture için emülatör5554debug17 splash'ta; release18x64 derlemesi sürüyor. Console sign-in, Windows list_apps helper timeout; deney/özel sayfa/CTR için yetkili UI halen gerekli.
- SA-021 capture hazırlığı: release18x64 APK build817.5s PASS; ayrıca Google Play generated universal18 indirildi, Play sertifikası/paket/sürüm/hash doğrulandı (`.store-automation/evidence/SA-021/play18-apk.json`). İki ownedQA5556 coldboot kullanılabilir capture vermedi, host freeRAM160MB görüldü; ownedQA kapatıldı. Yeni görseller gönderilmedi; gerçek capture ve public kabulü açık.

## Map
- `docs/CONSOLE_BASELINE_LOCAL_2026-10-16.md` — yetkili yeni/eski Console serileri için yerel özel rapor konumu; aynıcohort/Vitals kabulü eksik, ham ölçümler publicGit'e taşınmadı.
- `docs/evidence/SA015_QA_SYSTEM_CRASH_2026-10-16.log`, `docs/evidence/SA015_QA_BOOT_SCREEN_2026-10-16.png`, `docs/evidence/SA015_QA_SYSTEM_UI_ANR_2026-10-16.png` — yalnız disposable QA platform crash/ANR kanıtı; uygulama tamkabulü değil.
- `integration_test/qa_deadline_boot.py` — yalnız özel QA AVD/APK/public fixture guard'lı boot denemesi; normal kullanıcı açılışı gerektirir, henüz PASS değil.
- `docs/SA015_ACCEPTANCE_2026-10-16.md`, `docs/evidence/SA015_NATIVE_2026-10-16.log`, `docs/evidence/SA015_NATIVE_OFF_2026-10-16.json`, `docs/evidence/SA015_BOOT_FIRST_FAIL_2026-10-16.log`, `docs/evidence/SA015_BOOT_SECOND_FAIL_2026-10-16.log` — gerçek native teslim/off PASS ve iki boot FAIL kapsamı.
- `tool/brand/check_store_copy.py`, `docs/growth/STORE_TEXT_ACCEPTANCE.md`, `candidate/tr-TR/*.txt` — yeni Türkçe adayın kaynak/sınır/hash kontrolü; gönderilmedi.
- `docs/growth/CONSOLE_READBACK_2026-10-16.md` — Console erişimi doğrulandı; eski tr-TR kısa/tam metin ve telefon görselleri incelemede, managed publishing kapalı. Önceki erişim yok gözlemini değiştirir; yeni yayın ürün kabulü sonrası (ADR-010).
- `docs/growth/STRATEGY.md`, `RESEARCH_2026-10-16.md`, `COMPETITORS_2026-10-16.md`, `STORE_COPY.md` — güncel büyüme kanıtı/karar/devir; `docs/growth/evidence/**` saha ekranları.
- `AGENTS.md` — Store Automation pointer.
- `lib/main.dart`, `lib/home_page.dart` — açılış/liste/kriter/ayar.
- `lib/listings/official_listing_page.dart`, `listing_facts.dart` — cache ayrıntı ve ortak alanlar.
- `lib/ui/assistant_chat.dart`, `lib/data/assistant_client.dart` — Asistan/ilan bağlamı.
- `lib/ui/pro_page.dart`, `lib/data/subscription_check.dart` — aylık Pro/istemci restore.
- `lib/data/listing_store.dart`, `remote_sync.dart` — SQLite schema11, snapshot/delta/favori koruma.
- `lib/notifications/` — FCM secure store/registration/history; eski Workmanager iptali.
- `packages/kamubul_core/lib/` — kriter/eşleşme/parsere/tarih yardımcıları.
- `android/app/src/main/kotlin/com/crazypenguin/kamubul/MainActivity.kt` — hash/secure store/calendar köprüleri.
- `workers/src/worker.js` — public API, private kurulum, cron/queue.
- `workers/src/sources.js`, `pipeline.js` — kaynak/lease/ayıklama/eşleşme/outbox.
- `workers/src/notice_extraction.js`, `extract.js` — mekanik önce, alıntılı fallback.
- `workers/src/assistant.js`, `external_ai.js` — Asistan/sağlayıcı/token ölçümü.
- `workers/migrations/` — D1 schema/retention/outbox.
- `workers/public/privacy/`, `tool/build-privacy-page.ps1` — canlı gizlilik sayfası.
- `tool/admin-usage.mjs` — anonim admin config/kullanım/backlog readback.
- `tool/brand/store_frames.py` — mağaza çerçeveleri; devralınan kullanıcı diff'i korunur.
- `D:/repositories/kamubul-site/dist/` — ayrı statik site kaynak Git/hosting kimliği, JS/API/analytics yok; host bot protection script/cookie ekler.
- `docs/WEB_SITE_CANDIDATE.md` — Site version/deploy/Playwebsite/QA kanıtı.
- `docs/PLAY_GROWTH_AUDIT.md` — rakip/fiyat/Google kanıtları ve ürün boşlukları.
- `D:/AppPublishing/apps/kamubul/stores/google-play/metadata/tr-TR/` — repo dışı mağaza materyali.

## Domains

### Product QA and reminders — 16 Ekim son tur
Status: OBSERVED
Sources: `packages/kamubul_core/lib/data/search_alerts.dart`, `packages/kamubul_core/test/deadline_plan_test.dart`, `docs/PRODUCT_ACCEPTANCE_2026-10-16.md`, `.store-automation/tasks/SA-015.md`
- SA-017 kadro/yıl düzeltmesi Git içinde; Flutter206/206, Worker contracts+pipeline162/162, core219/219 önceki tur PASS. Cihaz TalkBack ve bağımsız review açık; yayınlanmadı.
- SA-015 saf deadlineReminderPlan eklendi:3gün önce09 Türkiye, UTC slot/expiry,22–08 sessiz saat, iptal/unsave/belirsiz tarih koruması. Hedefli20/20 ve analyze temiz; son genel Flutter206/206/core223/223 PASS.
- Native alarm/receiver, opt-in ayar ve save/unsave/revision/resume/boot entegrasyonu henüz yok; otomatik hatırlatma çalışıyor denmez. ADR-011 teslim anında expiry/quiet kontrolünü zorunlu kılar; yeni dependency veya kaynak taraması yok.
- Kullanıcı yeni mağaza gönderiminden önce ürün kabulü istedi (ADR-010). Yetkili Console mevcut eski tr-TR metin/görselleri incelemede gösterdi; önceki erişim yok notu tarihsel. Genel ürün kabulü ve büyüme sonucu açık.

### Research and growth checkpoint — 16 Ekim 2026
Status: OBSERVED
Sources: `docs/growth/**`, `docs/GROWTH_RECHECK_2026-10-16.md`, `lib/ui/assistant_chat.dart`, `workers/src/worker.js`
- SA-022/023:25 resmi kaynak grubu,12 rakip,3 tekseferlik Play TR web sorgusu,3 rakip görseli; strateji/metin/brief ve tam kullanıcı hedefi Git içinde. `docs/growth/STRATEGY.md` devir girişidir.
- Public TR tarayıcı:eski8görsel,sonPro100/30; yerel/APIadayı7 ile public eşleşmiyor. Google publishing state okunmadan upload tekrarlanmaz; SA-021.
- AI yanıt bildirimi AssistantChatView/Workerrouter içinde yok; SA-024. SELLSOFT da hesapsız eşleşme+AIayıklama beyanı; benzersizlik iddiası yok.
- 16Ekim canlı API213aktif/135complete/57partial/21metinsiz/13AI; SBBblocked,İŞKUR500,Kariyer önceki metni koruyan ayrıntı hatası. Bu bölüm eski snapshot sayılarından yenidir.
- Son checkout Flutter204geçti/2canonicaltabletgoldenfail; positionfilter7/7,Workercontracts+pipeline162/162. Bunlar gerçek ödeme/FCM/reklam kabulü değil; SA-017dirty korunur.
- Günlük heartbeat hedefdosyasının takip yasağıyla silindi:automation_update deleteStatus=deleted. Yeni takip kurulmadı. ConsoleCTR/Vitals/Androidrakipfiyat/WebindexUNKNOWN.


### Sources and extraction
Status: OBSERVED
Sources: `workers/src/**`, `workers/wrangler.jsonc`, `workers/test/**`
- 15 Ekim health:212 aktif;137complete/56partial/19metinsiz/12AI katkılı (değişen anlık değerler).
- Meta:ilan.gov ok; Kariyer eski metni koruyan ayrıntı hatası; SBB blocked; İŞKUR HTTP500/last_success yok.
- Kapsam ve kaynak başına field precision kabulü eksik (SA-003/004); bütün kaynaklar eksiksiz denmez.
- Native kimlik önce saklanır; kaynak/AI telefona dönmez. 294Worker testi PASS, canlı kapsam/teslim kanıtı değildir.

### Assistant and Pro
Status: OBSERVED
Sources: `lib/data/assistant_client.dart`, `lib/data/subscription_check.dart`, `lib/ui/pro_page.dart`, `workers/src/assistant.js`, `workers/wrangler.jsonc`, `tool/admin-usage.mjs`
- Repo:Asistan qwen3.6-flash/ayıklama qwen3.8-flash. Canlı version readback:ikisinde qwen3.8-flash-next; kör Worker deploy yok.
- Kod/canlı kota10free/50pro, global/IP100000. Canlı extraction günlük10000/saat2000/global20000; eski1000/200 artık geçerli değil.
- 15Ekim ölçüm:1Asistan yanıtı4099token;6extraction ölçümlü yanıt ort9041token. Credits/maliyet/hata oranı değildir.
- Pro body.tier istemci iddiasına dayanır; server Play doğrulaması SA-016 açık.
- Wrangler secret adları:EXTERNAL_AI_KEY/FCM_CLIENT_EMAIL/FCM_PRIVATE_KEY; Play binding yok. İçerikler okunmadı/kopyalanmadı.
- Token Plan koşulu/Credits kalibrasyonu ve owner key rotation SA-005 açık kapılarıdır.

### Mobile and notifications
Status: OBSERVED
Sources: `lib/**`, `android/app/src/main/**`, `test/**`, `integration_test/**`
- Kayıt/kriter/üç durum/çevrimdışı metin/tema/yazı ölçeği mevcut; standalone Flutter güncel199/199 PASS (SA-019 golden güncellemesi dahil).
- SA-014 kesin gelecekteki deadline için native calendar editor:all-day gün, saat açıklamada, kayıt kullanıcıda. Native kabul görevin Evidence bölümünde.
- Otomatik saved reminder bağlı değil:deadlineReminder/markReminded çağrısız; eski Workmanager iptal. SA-015 açık.
- FCM outbox15Ekim:115accepted/3cancelled/22pending; accepted cihaz teslimi değildir.
- Gerçek post-trial reklam/restore/FCM yaşam döngüsü/TalkBack/hız kapıları SA-005 açık.

### Store growth and release
Status: OBSERVED
Sources: `docs/PLAY_GROWTH_AUDIT.md`, `docs/STORE_LISTING_CANDIDATE.md`, `docs/WEB_SITE_CANDIDATE.md`
- Play subscriptions15Ekim:kamubul_pro_monthly/aylik ACTIVE/P1M/TR58,99TRY; dönen yıllık plan yok. Fiyat değiştirilmedi.
- Fastlane metadata commit+ayrı API readback: Asistan-first title/short/full ve7orderedSHA256 eşit (SA-006/c1322e8). Production/internal1.2.2/code17 değişmedi; Google public onay/yayılım bekliyor.
- Eski100/30 Pro görseli silinmeden assets/unassigned içine taşındı; yalnız7doğru ekran gönderildi. Sekizinci varyant için doğru50/10 capture gerekir.
- 16 Ekim akşam: Console (devx8585→crazypenguin) ve wrangler OAuth (devx8585) erişimi doğrulandı; eski "oturum yok" notları geçersiz. Metadata incelemesi yayına çıktı (yayınlanmamış değişiklik yok). Edinim hacmi deney için çok düşük; Vitals/elde tutma eşik altı. Özel sayılar yalnız yerel baseline'da.
- Statik Sites public yayında: https://kamubul-kamu-ilanlari.ochre-coin-3625.chatgpt.site; source9723514, native deployment succeeded, browser/6HTTP200 readback. Play contactWebsite commit+separate edit GET doğrulandı; public Google approval ayrı. Worker deploy yok.
