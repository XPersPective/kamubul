# Mevcut Mimari — KamuBul

6 Ekim 2026. Bu dosya doğrulanmış mevcut durumu tutar; eski kontrol noktaları
Git geçmişindedir. Son kullanıcı yönü PB-027/C-054: mekanik önce, yeterlilik
kontrolü ve eksikse saklı tam metni okuyan Qwen. Telefon fallback koruması
ve eski CF-first model sırası geçersizdir. Tam üretim kabulü henüz tamamlanmadı.

## Sunucu ve kaynak verisi
Kalıcı Worker: https://kamubul-api.devx8585.workers.dev, son deployment
5b5763f5-fcd1-4b62-b6aa-1fe5acc60402; /api/v2/health200, AI/FCM configured.
D1 kamubul (371092dd-2cc7-487f-b971-84c2499bbc7d), migration0001–0029 remote.
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

Son canlı readonly02:10 UTC: aktif ilan.gov165/text165; Kariyer30/text0.
Önceki168/text168 içinden İstanbul/Tekirdağ/TÜBİTAK3 ilanı yeni kanıtlı bitiş
zamanı geçtiği için mevcut expiry politikasıyla inactive oldu; metinleri D1'de.
Bu kaynak veya kimlik atlama değildir. notice-12 saklı metin backfill'i sürer;
eski notice-8 full pass45complete/123partial artık güncel kalite sayısı değildir.
Tam bütün kaynak/kalite kabulü açık; complete non-vacancy duyurularını da içerir.
Kariyer sayfa/RSS200 ve güncel resmi JS APIURL/body/routes okuyucuyla aynı;
detay API'sinin geçerli ilan yanıtı henüz alınmadı. SBB/İŞKUR okuyucularının
geçerli liste yanıtı kabulü de açık. IP/ülke nedeni çıkarılmaz, kullanıcıdan
Worker adresi tekrar istenmez. Kaynak boşlukları ilan/AI başarısı sayılmaz.

## Ayıklama ve Asistan
Üretim EXTRACT_AI_PROVIDER=external, qwen3.8-flash/Token Plan/thinking kapalı
(6 Ekim kullanıcı: plandaki en ucuz model; A/B9 çağrı ~%51 maliyet, ~4x yavaş →
ayıklama timeout110s/lease150s; çıktısı alıntıyla doğrulanır). Asistan ASSISTANT_AI_MODEL=
qwen3.6-flash: 3.8 aynı soruda kullanıcının yazdığı yaş/puanı yok saydı ve sayı uydurdu.
Kaynağın kimlik/tarih/il/kontenjandan gelen alanları AI gerektirmez.
notice_extraction.js kaynak/native ve başlıklı tabloları mekanik ayıklar;
aynı tabloda iki gerçek satır sayılır, tekrar yayımlanan tablo sayılmaz.
Belirsiz satırda ara toplam yayımlanmaz. Tek payload quota/deadline/groups/
applicationPeriods/fieldEvidence/extraction kart, ayrıntı ve offline'a gider.
Mekanik backlog AI çağrıları başlamadan küçük partilerle boşaltılır.
AI yalnız yeterlilik denetimindeki eksiklere, saklı tam metinle devreye girer.
notice-12/x11, ayrı attempted/quality; kısmi JSON complete sayılmaz.
Başka pozisyon alıntısı terfi ettirilmez; tercihen eğitim zorunlu olmaz;
birlikte gereken dereceler OR eğitim dizisine çevrilmez. Göreli/multiple tarih
ham takvim olarak saklanır, tek son başvuru uydurulmaz.
Kadro/Pozisyon Adedi sütunları ve native KPSS puan türü/taban puanı okunur;
aynı takvim satırındaki sonuç tarihi başvuru tarihinin yerine alınmaz. Açık
numaralı pozisyon koşulları kendi satırında tutulur, genel şartlar yalnız
eksik konuya uygulanır. Tek eksik belirsiz takvimse gereksiz Qwen çağrısı yok.
KPSS yüzdesi/ağırlığı minimum puan sayılmaz; eski AI cache aynı kuralla
yeniden çağrı olmadan temizlenir. Bakanlık KPSS puanı olmayan adayları kabul
eder: 70 puan barajı yok, quota5/Java3/.Net2 mekanik complete.
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
Ayrıntı kompakt kontenjan/tarih, ayrı pozisyon sayısı/koşulları/tam satır,
özgün seçilebilir metin ve alıntılar sunar; AI katkısında küçük hata olabilir
ibaresi ve kısmi kalite bilgisi vardır. Başvuru takvimleri kaynak metniyle açıktır. Yazı
ölçeği kalıcı. Asistan aynı cache metniyle açılır; boş metinde inference yok.
Dört atlanabilir onboarding, typed kriter editörü, ışık/koyu/responsive goldens,
7gün reklamsız deneme, Play aylık Pro ve mevcut reklam politikası korunur.
PRIVACY.md ve canlı privacy HTML5 Ekim sunucu/Qwen/aggregate token açıklamalı.

6 Ekim 1.2.0+15 (source d3e5bfb): 276 Worker/187 Flutter/211 core PASS, analyze temiz.
AAB C:/Users/rubicon/.codex/builds/kamubul-1.2.0-15.aab SHA256 e849c13cc10ce7c1276135b7790e6e2848
7e03be341be39da23fd2b2265f68c8; imza+kalıcı sertifika+12ELF/3ABI 16KB PASS. Play edit
13106827503238177928: internal+production 1.2.0/15 completed, yeni tr-TR metin (kaynak adı yok,
en altta zorunlu kaynak notu), 8 çerçeveli görsel ve featureGraphic (tool/brand/store_frames.py).
Konsol: production 1.2.0 hızlı kontrol→inceleme; Google onayı ayrı. Emülatör (flutter_emulator)
yeni arayüz/Pro/Hakkında/silme/İlkokul akışları PASS; kullanıcının tema/süzgeç durumu geri yüklendi.
Önceki 1.1.9+14 kaydı:
PB-027:269 Worker/213 Flutter/208 core/30 targeted mobile PASS; analyze temiz.
Signed1.1.9+14 source3ea2e20, build C:/Users/rubicon/.codex/builds/kamubul-1.1.9;
AAB SHA2562ef80a7bf29ea1734244d4c0acef5948b073c780b07018e5efd10db6dab2607b.
APK v2 signature/ZIP16KB, AAB signature/12ELF/3ABI LOAD>=16KB ve kalıcı cert PASS.
Own API36 GooglePlay/x64 emulator5562 fresh14/cold3900ms; home194 initial API
cache, Sabancı card/detail quota1+16Oct eşit, son server revision education yalnız
Lisans. Network kapalı force-stop/cold restart native original4324chars EXACT.
Proof C:/Users/rubicon/.codex/builds/kamubul-1.1.9-{card,detail-current,offline}.png.
Play production+internal14 update/validate/commit ve fresh API AAB hash PASS.
UI internal1.1.9/code14 "Dahili test kullanıcıları tarafından kullanılabilir";
production14 "İncelemede"; Google onayı/genel mağaza erişimi ayrı ve bekliyor.
Download https://play.google.com/apps/internaltest/4701555814809167145;
proof C:/Users/rubicon/.codex/builds/kamubul-play-1.1.9-current.jpg.
Gerçek metadata-mode Qwen fallback/cache replay doğrulandı; canlı ağırlık70
yanlış yorumu ortak doğrulamada düzeltildi. Native Malazgirt notice-5 hybrid
partial halinde AI/hata olabilir ve eksik bilgi ibareleri görüntülendi.
notice-6 sonrası aynı ilanda mekanik quota4/dört kadro1/P3 minimum60; native
kart ve ayrıntı parity PASS. Proof kamubul-1.1.9-{hybrid-warning,malazgirt-notice6}.png
aynı dış build dizininde. Günlük/saatlik model bütçesi sıfırlanmadı/artırılmadı.
notice-8 gerçek kaynaklarda Isparta26 (14Oct17:30), Bitlis10/P94 60/P93 65/
maxAge34 ve Yaşar2 canlı. Akademik sütunlar Van86/Yıldız19/Çanakkale28/
Boğaziçi3; derece sütunları sayılmaz. Son adres/takvim rowspan ve sonraki
takvim tablosu ayrılır. Yazılı otuz beş, otuz/beş sayısı olarak doğrulanmaz.
Birlikte gerekli ayrı eğitim cümleleri OR'a dönüşmez. İptal ve mesleki
sertifika sınavları kadro veya iş bildirimi sayılmaz, inference kullanmaz.
Own test emulator5562 kapalı/AVD ini kaldırıldı; avdmanager dizin silmede
hata verdi. Kalan yalnız owned AVD dizini silme komutu automatic policy ile
reddedildi; kullanıcı ortamına ilişkin başka silme denenmedi.

Native14 seçili Asistan boş/no-auto-question; gerçek Qwen sorusu "Bu ilanda kac
kisi alinacak?" → "İlan metnine göre kontenjan 1 kişidir." PASS. Server Asistan
saklı metni kullanır, kaynak refetch yok. Cold launch100ms hedefi karşılanmış
sayılmaz; fiziksel telefon/genel premium kabulü emulator kanıtından ayrı.

Yerel100/1000/10000 fanout check PASS: max15 SQL/match ve8/send;10k match15004SQL.
Günlük3000 Queue task örneğinde7996 send/2004 durable pending/9000normaloperations.
Cloudflare CPU/10k cihaz teslimi/SLA kanıtı değildir. Dashboard24h karışık sürüm
2.43k invocation/0 CPU-exceeded errors; CPU P90 7.15/P99 10.24ms, bazı zaman
pencereleri17ms. Yeni sürüme/tek stage'e ait başarı olarak kullanılmaz.

Kalan kabul: PB-027 kalan tablo/metin biçimleri ve kalite corpus'u; tüm kaynak metni
ve >=50 labeled/source precision>=.95/recall;
gerçek stage CPU/Qwen Credits kalibrasyonu/FCM fanout lifecycle;
Play server Pro doğrulaması, eski shared anahtarın owner rotation'ı,
post-trial real ad/Pro restore/AdMob store linkage; Google production14 onayı.
Deferred: iOS/APNs/sesli giriş/AI kişisel sıralama. Strateji docs/SERVER_INGESTION_STRATEGY.md;
aktif ayıklama PB-027, kaynak kapsamı PB-026, kalan geçmiş kullanıcı maddeleri PB-024/025'te kaybolmadan tutulur.

PB-027 son ek: applicationDeadline ortak mekanik/AI doğrulaması; Türkçe ay,
aralık SON tarihi ve saniye/saat İstanbul kabul edilir. Başlangıç/itiraz/sonuç/
belge teslimi/ödeme tarihi son başvuru değildir; aynı gün farklı saatler scoped.
Eski cache deadline/quota aynı alıntı kuralıyla inference olmadan temizlenir;
x11 cache anahtarı korunur. Sınava çağrılacak800 aday quota800 sayılmaz.
Düzce dikey İlanNo/PozisyonAdı/Adedi gerçek metinde3 (2+1); Özelleştirme14;
Adalet150; GİB860 açık istihdam cümlesinden. Live backfill kabulü PB-027'de.
Kariyer server Browser Run iki timeout, hiçbir fulltext kanıtı yok; desktop
resmi Bitlis DOM yalnız debugging. Geçerli server source yanıtı açık.
Brain aynı anda yalnız PB-027 IN_PROGRESS; diğer unfinished görevler PLANNED,
PB-026 kaynak yanıtı BLOCKED. Eski phone fallback/13/provider-yok günlükleri
Git geçmişinde; kullanıcı geri bildirimleri PB-024/025 korunur.
