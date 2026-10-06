# Mevcut Mimari — KamuBul

5 Ekim 2026. Bu dosya doğrulanmış mevcut durumu tutar; eski kontrol noktaları
Git geçmişindedir. Son kullanıcı yönü PB-027/C-054: mekanik önce, yeterlilik
kontrolü ve eksikse saklı tam metni okuyan Qwen. Telefon fallback koruması
ve eski CF-first model sırası geçersizdir. Tam üretim kabulü henüz tamamlanmadı.

## Sunucu ve kaynak verisi
Kalıcı Worker: https://kamubul-api.devx8585.workers.dev, son deployment
22ac5fc4-4d40-4248-a2dc-e56bc4f7c52a. Önceki health200/AI/FCM configured;
PB-027 deployment sonrası canlı kalite/sayı kontrolü sürüyor.
D1 kamubul (371092dd-2cc7-487f-b971-84c2499bbc7d), migration0001–0028 remote.
Queue kamubul-work, batch1/concurrency1/retry0. Cron her dakika recovery;
source/extract/match/send generation+lease, atomik3000 UTC günlük görev sınırı.
Cloudflare Free/Firebase Spark korunur; otomatik ücretli yükseltme yok.
Firebase kamubul-3ae6e; Android com.crazypenguin.kamubul. FCM HTTPv1 kimliği
Firebase Cloud Messaging API Admin; private key ve Qwen key yalnız dış
credentials/Worker Secrets. Client Firebase config sunucu yetkisi değildir.

Kaynak index bütün native kimlikleri ayrıntı/AI'dan önce D1'e kaydeder.
ilan.gov native20 sayfa cursor'u kalıcı; eksik/tekrarlanan/değişen snapshot açık
hata. Kariyer/SBB liste ve Kariyer kadro sessiz slice limitleri kaldırıldı.
İŞKUR WebForms kamu filtresi/cookie/pager adapteri mevcut, özel sektör alınmaz.
HTML paragraf/tablo satır-hücre sınırları okunabilir metinde korunur.
Liste30dk yenilenir; ayrıntı backlog'u sürerken yeni kimlikler yayımlanır,
tamamlanan ayrıntı cursor'u korunur. Kaynak Queue15s pacing/turda1 ayrıntı;
başarılı ayrıntı6h recheck. İki başarısız onarım sonrası kalıcı6h cooldown;
crash/kota eski başarılı metni silmez. İlk snapshot bildirim üretmez.
SBB PDF reader native AI.toMarkdown:3MiB/25s fetch,45s conversion,
120KB çıktı/20 UTC günlük rezervasyon, hash+reader cache. Gerçek SBB PDF
conversion/kalite kanıtı henüz yok; OCR/sayfa sayısı sınırı yok.

Son canlı readonly: ilan.gov177 kimlik/text167/conditions_checked37;
Kariyer27 kimlik/text0. Bu bütün kaynak kapsamı değildir. ilan.gov yeni snapshot
sayfalaması sürüyor. Gerçek preview: ilan.gov200+749chars; Kariyer homepage/RSS200
fakat mevcut API522; SBB403 Access Restricted; İŞKUR500 veya200 Request Rejected
(ilan sayfası değil). Resmi güncel JS'de APIURL/body/detail routes okuyucuyla
aynıdır; resmi browser headers aynı CF preview'de API522 verdi. IP/ülke nedeni
çıkarılmadı. Kullanıcının çalışan Cloudflare kaynak yolu henüz eşleştirilmedi.

## Ayıklama ve Asistan
Üretim EXTRACT_AI_PROVIDER=external, qwen3.6-flash/Token Plan/thinking kapalı.
Kaynağın kimlik/tarih/il/kontenjandan gelen alanları AI gerektirmez.
Ayıklama normalize tam metin+prompt/model hash'inde D1 shared cache; kabul edilen
120000 karakterin tamamı gönderilir. Her alan birebir kaynak alıntısıyla
validate edilir; belirsiz unknown. Bir geçerli sonuç tek çağrı, bozuk/hata için
kalıcı iki çağrı tavanı/lease. Ayrı parça başına özet inference kapalıdır.
Quota/hata conditions_due_at ile ertelenir; sıradaki ilan ilerler. Eski özet
quota_wait işleri migration0028 ile tekrar pending; extraction bütçesi korunur.
Günlük ayıklama150/saatlik30/global400, ayrı Asistan global300/kurulum30free,
100pro/IP500. Bütçe ölçümü kredi garantisi değildir. Pro tier istemci iddiası
henüz Play sunucu doğrulamasından geçmez; bu üretim güvenlik kapısı açıktır.
Provider usage kişisel metin olmadan assistant_usage tokens:* bucket'larında:
ilk ölçülen input123247/output55479. Console gerçek Credits ile kalibrasyon açık.
Canlı ilan2235014/3498chars/2grup extraction cache replay200/cached:true PASS;
aynı saklı metin tekrar source/model çağrısı yapmadı.
Asistan120k saklı metni kabul eder, soruya/profil sözcüklerine göre<=8000chars
kesit seçer; partial flag yokluk iddiasını kısıtlar. Sonlardaki ilgili şart için
regression vardır. Kaynağa gitmez, seçili ilan açılışında otomatik soru göndermez.

## Kalıcı katalog, eşleşme ve bildirim
Public v2 meta/taxonomy/listings/changes/detail + geçiş v1; immutable watermark,
ETag/CacheAPI public60s/taxonomy300s. Cookie/auth/private/no-store cache bypass;
hata origin'i kesmez. Sayfa<=50/1.8MB; oversized413 cursor atlamaz.90day retention
floor/base/expired-pin recovery, CAS ile pruning. Uzun vadeli yük ölçümü açık.
Typed SearchCriteria2: aynı kadro AND/alternatif OR, match/no_match/unknown.
77 ortak Dart/Worker/SQLite corpus +144 doğum-günü oracle; İstanbul referans tarihi,
365/366 gün freshness, yanlış KPSS type/range/score unknown.81 city ve5education
kimlik/alias; meslek/kurum/kategori genel sözlüğü henüz tamamlanmadı.
Authenticated own installation PUT/DELETE, version precondition ve atomik facets;
401/cross-owner ve409/stale yarış kontrolleri. Mobile409 bir bounded retry.
Eşleşme indexed10 owner/cursor; strict unknown push yok. Durable unique outbox,
quiet/digest/deadline/send-time token/version/criteria recheck/invalid-token guard.
FCM accepted != delivered; belirsiz timeout exactly-once garantisi vermez.
Secure device FIFO: Android Keystore AES-GCM/noBackup, iOS ThisDeviceOnly (iOS
bu çalışma dışında). Private history/receipt cache bounded/owner scoped.
4 Ekim gerçek emulator FCM foreground/process-yokken OS/cold tap/opt-out
kanıtı önceki Git kaydında; Cron kaynak→AI→match→outbox uçtan uca kanıtı değildir.

## Telefon ve yayın
Flutter SQLite schema11; remote_catalogue tam payload kalıcı. Frozen bootstrap,
atomik page+cursor, delta/tombstone, origin/generation/detail epoch, favorite
koruma ve encrypted notification cache. allListings projection tam metni tutar;
noticeText genel+her position.text/legacy conditions birleştirir. Favorite
silinen ilan metni offline korunur. Farklı native ID fingerprint ile elenmez.
Home/cache refresh/Asistan yalnız Worker API; otomatik source/detail/city fetch
ve condition backfill kaldırıldı. Eski Workmanager görevi iptal/no-op migration.
Kullanıcı resmî bağlantıyı kendisi açabilir. Kaynak durumu dürüst gösterilir.
Ayrıntı özgün seçilebilir metin ve alıntılı ayrı kadro koşulları sunar; yazı
ölçeği kalıcı. Asistan aynı cache metniyle açılır; boş metinde inference yok.
Dört atlanabilir onboarding, typed kriter editörü, ışık/koyu/responsive goldens,
7gün reklamsız deneme, Play aylık Pro ve mevcut reklam politikası korunur.
PRIVACY.md ve canlı privacy HTML5 Ekim sunucu/Qwen/aggregate token açıklamalı.

Yerel243 Worker/206 Flutter/208 core PASS, analyze temiz. Native1.1.8+13 signed
fresh APK API36 GooglePlay/x64 own5562 installed; cold5218ms (100ms hedef kabulü
sayılmaz), gerçek API home184, ilan2235014 D1 metni3498chars == bağlantı kapalı
native selectable text3498chars EXACT. Asistan seçili ilan/no automatic message.
Proof C:/Users/rubicon/.codex/builds/kamubul-1.1.8-{home,detail,offline,assistant}.png.
Owned5562 kapalı, kamubul_pb026 AVD resmi araçla silindi; kullanıcı5560 korundu.
Signed source b526eb1/version1.1.8+13; build C:/Users/rubicon/.codex/builds/kamubul-1.1.8.
APK package/cert/nondebuggable/ZIP16KB, AAB signature/12ELF/3ABI LOAD>=16KB PASS.
AAB60756830byte SHA2566139F648EF0379453A82C29E5A01A2C50F14673CB8EE5779D17461683F1990A9.
Son açık kullanıcı talimatıyla Play production1.1.8/code13 completed:
track update/validate/commit ve fresh API/hash PASS. Son açık kullanıcı
talimatıyla internal1.1.8/code13 update/validate/commit de PASS.
Fresh API iki kanal13; UI dahili13 test kullanıcıları tarafından kullanılabilir.
Download https://play.google.com/apps/internaltest/4701555814809167145;
proof C:/Users/rubicon/.codex/builds/kamubul-play-1.1.8-internal.jpg.
Play Console Yayın özeti üretim1.1.8 için otomatik ön kontrollerin başladığını
gösterir; managed publishing kapalı, kontrol+Google onayı sonrası sunulur.
Genel mağaza erişimi/onay henüz doğrulanmadı. Proof:
C:/Users/rubicon/.codex/builds/kamubul-play-1.1.8-submitted.jpg.
Kaynak tam-metin/kalite kapsamı yayın sonrası açık; eksiksiz kabul sayılmaz.

Yerel100/1000/10000 fanout check PASS: max15 SQL/match ve8/send;10k match15004SQL.
Günlük3000 Queue task örneğinde7996 send/2004 durable pending/9000normaloperations.
Cloudflare CPU/10k cihaz teslimi/SLA kanıtı değildir. Dashboard24h karışık sürüm
2.43k invocation/0 CPU-exceeded errors; CPU P90 7.15/P99 10.24ms, bazı zaman
pencereleri17ms. Yeni sürüme/tek stage'e ait başarı olarak kullanılmaz.

Kalan kabul: tüm kaynak metni +>=50 labeled/source precision>=.95/recall;
gerçek stage CPU/Qwen Credits kalibrasyonu/FCM fanout lifecycle;
Play server Pro doğrulaması, eski shared anahtarın owner rotation'ı,
post-trial real ad/Pro restore/AdMob store linkage; yeni Play release.
Deferred: iOS/APNs/sesli giriş/AI kişisel sıralama. Strateji docs/SERVER_INGESTION_STRATEGY.md;
aktif detay PB-026, kalan geçmiş kullanıcı maddeleri PB-024/025'te kaybolmadan tutulur.
