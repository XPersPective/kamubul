# Hedef Mimari — KamuBul

## 1. Amaç ve kapsam

Premium görünümlü, Türkçe Android/iOS uygulaması; hesap açmadan resmî kamu ilanlarını okuma, profil ve kişisel kayıtlı kriterlerle filtreleme, yeni uygun ilana FCM bildirimi. Resmî veriyi toplama/işleme ve push kararları Cloudflare'da; telefon UI, yerel cache, favori, profil, eşleşme görünümü ve OS bildirim entegrasyonudur. 30 Eylül 2026 kullanıcı yönü önce Brain/mimariyi temizleyip ayrıntılı devredilebilir yol haritası oluşturmak; bu belge hedef, current.md gerçek durumdur.

Cloudflare Workers Free, D1, Cron, public edge cache ve Free erişimli Workers AI; Firebase Spark yalnız FCM. SQLite/sqflite ve napp_* korunur. Firestore, Cloud Run, Cloud Scheduler, Blaze, ücretli API ve VPS hedef dışı. Queue/R2/KV/ek arama altyapısı ilk sürüm şartı değildir; gerçek bir sınıra ve güncel ücretsiz erişime göre değerlendirilir.

## 2. Sorumluluk sınırı

| İş | Dışarıda / Cloudflare | İçeride / Flutter |
| --- | --- | --- |
| İlan | Kaynak listesi+ayrıntı çekme, normalizasyon, dedupe, deadline/state | Cache'ten liste/detay, resmi linki kullanıcı açar |
| AI | Yeni/değişen içerik için kanıtlı koşul+özet; ortak sonuç | Kaydedilmiş özet/alıntı gösterir, kullanıcı adına model çağırmaz |
| Kriter | Typed sözleşme, izinli taxonomy, abonelik doğrulama/index | Profil ve isimlendirilmiş arama düzenleme, yerel filtreleme |
| Bildirim | Yeni revizyon adayları, eşleşme, quiet/digest/cap, outbox, FCM send | İzin, token, foreground sunumu, OS background/terminated, event dedupe/tap |
| Veri | Authoritative katalog/change-log, private kurulum kaydı | SQLite cache/cursor, favori/profil, geçici kayıt retry |
| Hata | Önceki kataloğu koru, kaynak durumunu yayımla | Cache + son başarılı güncelleme; otomatik kaynak scraping yok |

FCM sunucunun kapalı telefonu sürekli çalıştırmasını sağlamaz. Kullanıcıya görünür notification+data gönderilir; veri eşitleme ayrıca açılışta yapılır. UI cihazda kalır. Yeni-ilan kararının iki tarafta aynı anda üretimi yok. Son-tarih hatırlatması v2'de server-owned; önce yerel reminder kapatılıp sonra aynı event türü devreye alınır.

## 3. Etiket/kriter kararı — ADR-001

**Hibrit:** uygulamanın yönettiği typed alanlar + sürümlü ortak değer sözlüğü + kullanıcının serbest isim verdiği kayıtlı aramalar. Her serbest isim yeni global etiket değildir. Kullanıcı istediği sayısal eşiği ve bilinen değer kombinasyonunu seçer; serbest sözcük araması da yapabilir. Filtre adını LLM ile yorumlamak yok.

- Sözlük: şehir, eğitim, KPSS puan türü, kurum, meslek ve ilan kategori kodları. Kodlar sabit kimlik, Türkçe label/alias ayrı; AI yalnız bilinen kodlara aday eşleme yapar. Yeni meslek/alias önerileri doğrulama sonrası sözlüğe girer. Hiçbir yeni ilan yeni global tag'ı otomatik yaratmaz.
- Kriter: şehir/kategori/meslek/kurum çoklu seçenekleri, eğitim düzeyi, aday yaş+referans tarihi, KPSS türü+puan(+gerekliyse sınav yılı), anahtar sözcük, tarih/deadline. Kaydedilmiş arama criteriaVersion=2, searchId, name, alertMode, createdAt, updatedAt, effectiveFromSeq.
- Grup içindeki kriterler AND; bir alandaki çoklu seçenekler OR; birden fazla kayıtlı arama ANY. İlanın ayrı kadro/pozisyon koşulları ayrı requirementGroups; en az bir grubun bütün kriterleri eşleşmeli. Bir kadronun eğitimini diğerinin KPSS'siyle birleştirme yok.
- q MVP'de deterministik Türkçe normalize başlık/kurum/meslek araması; mevcut yalnız başlık v1 davranışı migration'da version1 olarak korunur veya kullanıcıya açık biçimde güncellenir. Serbest etiket adı yalnız isim; semantik vektör araması ilk sürüm değil.
- Uygunluk üç durum: match / no_match / unknown. Required alan bilinmiyorsa unknown; otomatik strict push yok. Ayrı “Şartları kontrol et” listesinde kullanıcı opt-in gösterebilir. unknown, no_restriction ve KPSS not_required farklıdır. Yaş referansı geçmişse veya kaynak yaş hesabı/doğum sınırı desteklenmiyorsa unknown; yanlış kesinlik yok.
- KPSS aday puanı ilan tabanından >=, aynı puan türü ve gerektiğinde yıl/geçerlilik. KPSS istenmeyen ilanlar varsayılan aday KPSS bilgisi yüzünden elenmez; “yalnız KPSS şartlı” ayrı filtre.
- Profil verileri yerelde; bildirim açıkken yalnız aramanın gerekli kriterleri registry'ye gider. Yaş için age + ageAsOf ilk basit yol; doğum tarihi zorunlu değil. Tarih eskimesinde UI güncelleme ister, otomatik tahmin edilmez.

Örnek isim “Ankara teknik”: cityCodes=[06], occupationCodes=[engineer], educationCodes=[bachelor], candidateAge=28, ageAsOf=2026-09-30, kpss={type:P3,score:78}, mode=instant. İlan mühendis/P3>=70/maxAge35 aynı grubunda doğrulanmışsa match; mimar/P3>=80 no_match; puan eşiği belirsizse unknown. JSON field isimleri PB-016'da fixture ile sabitlenir; örnek sözleşme uygulanmış değildir.

## 4. Veri modeli — D1 migration tasarımı

Önce ihtiyaç kadar tablo; tablo listesi uygulanmış schema değildir. PB-016 gerçek migration/query planıyla doğrular.

| Tablo | Temel alanlar / bütünlük |
| --- | --- |
| sources | id, allowedHost, parserVersion, enabled, cursor/etag/lastModified, lastAttempt/lastSuccess, state, leaseUntil |
| listings | stable id, sourceId+externalId UNIQUE, canonicalId, officialURL, sourcePublishedAt, firstSeenAt, contentHash, revision, state, deadline, normalized fields, requirementsJSON, summaryJSON, extractionVersion |
| listing_aliases | source identity → canonicalId; doğrulanmış cross-source ilişki, belirsiz birleşme yok |
| processing_jobs | listingId+contentHash+extractionVersion UNIQUE, pending/leased/validated/failed/quota_wait, attempts, dueAt, leaseUntil, errorCode, modelRevision, inputHash, outputHash |
| catalogue_changes | seq INTEGER artan, listingId, revision, upsert/tombstone, immutable bounded payload, committedAt; job commit ile atomik |
| installations | id PK, secretHash, token, platform, notificationEnabled, prefsVersion, quiet/daily config, lastSeenAt; public API'de yok |
| saved_searches | installationId+searchId PK, criteriaVersion, name, criteriaJSON, criteriaHash, effectiveFromSeq, mode |
| search_facets | searchId+facet+value; coarse aday indeksi (unknown dahil güvenli superset), son karar full predicate |
| match_runs | eventId PK, listing/revision, current candidate cursor, started/end, state; interrupted fanout devam eder |
| notification_outbox | installationId+eventId+type UNIQUE, matchedSearchIds, preferencesVersion, pending/leased/accepted/failed/cancelled/expired, attempts, dueAt, leaseUntil, fcmMessageId |
| sync_runs / daily_usage | kaynak turu sayıları/hata; kota reservation+tüketim, UTC gün; sır/profil loglanmaz |

Index: source identity, active+published/id, change seq, pending job state+dueAt, registry lastSeen, coarse facet value+searchId, candidate cursor, outbox state+dueAt+id, installation+event unique. D1 rows_read/rows_written ve indeks yazmaları ölçülür; JSON filtreyi bütün cihazlarda sürekli tarama hedef değildir. Her kayıtlı arama için küçük facet satırları sınırlı; max20 arama/kurulum mevcut sınır korunur. İlan kimliği URL değişince değişmez. Full migration eski v1 verisini kaybetmez.

D1 read replica ilk pilotta yok; commit sonrası read-after-write/delta tutarlılığı PB-016 testinde doğrulanır. Atomik batch için D1'nin desteklediği araç kullanılır; HTTP sırasında açık SQL transaction varsayılmaz.

## 5. Merkezi ingestion ve AI

1. Tek scheduler etkin kaynakları dueAt/cursor ile sınırlı işler; lease ile yarış önlenir. Başlangıç kaynak kontrolü 30 dk; 5 dk yalnız kaynak izinleri ve gerçek kota/CPU ölçümü sonrası. Fetch/list, detail/AI ve notify farklı bounded turlar; tarama sıklığı teslim süresi garantisi değil.
2. Kaynak listesi ETag/Last-Modified/cursor destekliyorsa incremental. Yoksa kısa liste parse edip source+externalId ile yeni/değişen aday belirle. Bilinmeyen değişiklikler için bounded round-robin detay revalidation gerekir; yalnız URL'yi “işlendi” yapmak yetmez.
3. Kaynak identity unique; raw fetch korunur/bounded; semantic text normalize ve contentHash hesapla. Sayfa navigation, reklam, sayaç/timestamp gürültüsü dışarıda. Semantic olmayan format değişimi AI çağırmaz; anlamlı şart/deadline düzeltmesi revision artırır. 304 güvenilirliği kaynağa özgü.
4. Yeni/değişmiş içerik → kalıcı processing job. İlan aynı hash+extractor/model revizyonuyla başarıyla işlenmişse AI tekrar çağrılmaz. Re-extraction version yükseltmesi sadece planlı bounded job, bütün arşiv otomatik işlenmez.
5. Native structured alan/deterministik çıkarıcı korunur; gerekli ilan metninin bounded bölümüne Free Workers AI ile tek extraction+summary çağrısı. Kaynak kişisel veri değil public notice; hiçbir installation/profile gönderilmez. Relevan pasaj kesimi coverage kaybını raporlar; eksik bölümden koşul uydurulmaz.
6. Strict JSON, types, date/range, source quote+value support, taxonomy whitelist, prompt injection sınırı, değerlendirme kapıları. Summary 3–5 kısa madde ve kanıt; kullanıcı için “AI özeti” etiketi. AI parser/layout değişikliğini sınırsız kendi kendine tamir etmez; drift algısı → source degraded → fixture/parser işi.
7. Başarılı sonuç kalıcı, listings+immutable change+match event atomik commit. Unknown alanlı ilan basic başlık/kaynakla yayınlanabilir, strict push olmayabilir; enrichment tamamlanınca eligibility event için bir kez eşleşme değerlendirmesi. Aynı ilan update'inde tekrar yeni-ilan bildirimi varsayılan yok; önemli düzeltme/deadline event türü ayrı.
8. Network timeout, 429/5xx bounded backoff/jitter; reservation, lease-expiry, quota_wait. Günlük AI bütçesi tükenirse job kalır, paid fallback yok. Detay/PDF için ayrı payload/page sınırı; scan/OCR Free CPU'ya sığmazsa honest unknown+official doc.

LLM tüm kullanıcı özelliklerini okuyup push kararı vermez. Maliyet yaklaşık yeni/değişen ilan × metin/model maliyeti; kullanıcı sayısı yalnız deterministic matching/FCM işini büyütür. Koşul aynı ilan için tüm kullanıcılara ortak.

## 6. Kişisel eşleşme ve FCM

İlan event'inin coarse category/city/occupation facetlerinden aday saved_search'ler indeksle bulunur; facet yok/unknown olduğunda ilgili adayları yanlış elememek gerekir. Typed predicate son söz; Flutter gösterimiyle aynı JSON conformance fixtures. Benzer criteriaHash aramalarında predicate sonucu paylaşılabilir; kullanıcının farklı name/quiet/push tercihi ayrıca uygulanır. Tek turda 10.000 cihaz tarayıp push yok; match_run cursor ve ölçülen batch limitleriyle sürdürülür.

Aynı kurulumda iki arama uyan aynı yeni ilan bir event, matchedSearchIds listesi. Yeni arama created/effectiveFromSeq öncesi ilanları push yapmaz; mevcutlar UI'da görünür. Günlük digest pilotu İstanbul18:00/sessiz saat, kurulum başına bir/gün ve en çok10 ilan; kalan kuyrukta sonraki güne, deadline geçmişse explicit expired. Digest anlık günlük cap'ten ayrı sayılır. Büyük backlog tavanı Free CPU/D1 ölçümü sonrası ayarlanır. Sessiz saat/digest/daily cap sunucuda; dueAt ve tarih YYYY-MM-DD, timezone Europe/Istanbul pilot. Eski cihaz offset modelinden yeni sözleşmeye açık migration; cihaz saati authoritative değil.

Commit → outbox → lease → preference/token/izin tekrar kontrolü → FCM HTTP v1 → accepted işaretle. Fail tekrar, invalid token pasifleştir, silme/opt-out pending işleri iptal eder. FCM response timeout belirsiz: retry tekrar oluşturabilir; eventId OS tag/client event geçmişi ile azaltılır, exactly-once iddiası yok. Normal iş başarısız diye global pending listesini boşaltma yok. Süresi geçmiş iş silent deletion yerine expired/digest kayıtlı politikası; neden ölçülür.

FCM notification+data: eventId, listingId, revision, catalogueSeq, type; private kriter yok. Push metni lock-screen'de yaş/puan/profil ifşa etmez. Foreground onMessage aynı event'i UI/history'ye geçirir; Android/iOS presentation kontrollü. Background/terminated OS gösterir; tap detail by stableID, cache boşsa API detay; kaldırılmış ilan için açık durum. Push sync transport değil; açılış/manual delta kaçan push'tan bağımsız.

Notification history sunucuda retained outbox event'lerinden authenticated bounded page, cihazda local cache; FCM accepted/received/opened durumları karıştırılmaz. Foreground/background kayıt kapasitesi sınırlı; notification-only push callback gelmese de açılışta event feed reconciles. Tarihçe için ayrı telemetry zorunlu değil, opened tracking MVP'de yok.

## 7. API ve sync sözleşmesi

V1 mevcut referans; v2 ayrı schema. İlk compatibility snapshot pilotu v1'i kırmadan sunabilir. Yeni uygulama v2'ye geçtiğinde deprecated v1 cache/snapshot ancak aktif eski client politikasına göre kaldırılır.

| API hedefi | Davranış |
| --- | --- |
| GET /api/v2/meta | schemaVersion, taxonomyVersion, latestSeq, oldestRetainedSeq, source status/staleness; public ETag |
| GET /api/v2/taxonomy | stable codes/labels/aliases, version, public shared cache |
| GET /api/v2/listings?cursor&limit | summary pages; server-generated bounded cursor, max50; first full sync active window |
| GET /api/v2/listings/{id} | full canonical detail, revision, evidence, officialURL; removed durum |
| GET /api/v2/changes?after&cursor&limit | frozen watermark, immutable changes <=watermark, nextCursor, appliedThrough; cursor expired → full sync required |
| PUT/DELETE /api/v2/installations/{id} | anonymous bearer own-record only, registry version, criteria limits/validation; private no-store |
| GET /api/v2/installations/{id}/notifications | auth, bounded retained event history/cursor; private no-store |

Timestamp sourcePublishedAt/firstSeenAt/sourceUpdatedAt/fetchedAt farklı; yalnız timestamp ile sync yok. Monoton seq authoritative. Change log immutable payload; canlı listings tablosundan son değeri çekip watermark sonrası değişiklikleri eski sayfaya sızdırma yok. Full snapshot ilk sayfada frozen watermark/revision; tüm sayfalar aynı snapshot (materialized veya eşdeğer revision store). Yarıda sync aynı snapshot'tan sürer veya baştan; stable paginate sadece id/time ile güncellemeyi kaçırmaz.

SQLite upsert ve cursor tek transaction; explicit null eskiden çıkarılmış koşulu temizler; kişisel favori/arama flags değiştirilmez. Tombstone ilanı current listeden kaldırır, favoriyi unavailable yapar. Min retained seq'den eski cursor full snapshot gerekir; yerel bookmark/profile/arama durur. Full snapshot bittiğinde görünmeyen unsaved remote records reconcile edilir. Per-page ETag key watermark/cursor ile; bütün meta latestSeq ileri diye tamamlanmamış sayfayı atlama yok.

Açılış: cache → meta conditional → gerekli change pages → cache UI. İzinli manuel refresh aynı repository. Profil/filtre değişikliği cached ilanları yerel predicate ile anında süzer; sadece registry criteria diff gönderilir, kaynakları yeniden çekmez. Sunucu unavailable: cache+stale badge, typed retry; telefon scraping fallback yok. Shared catalogue cache keys kriter/kurulum ID içermez. Worker Cache API bölgesel avantajdır; bütün dünyada tek hit varsayılmaz. Kullanıcı sayısı maliyetini küçük meta, bounded delta ve app refresh aralığıyla kontrol et.

## 8. Free kapasite ve ölçüm kapısı

30 Eylül 2026 resmi doğrulama: Workers Free günlük 100.000 request, HTTP/Cron 10ms CPU, 50 dış subrequest, 6 eşzamanlı bağlantı; D1 5 milyon read row/gün, 100.000 write row/gün, toplam5GB. Workers AI 10.000 neuron/gün, Free kotası sonrası hata; bazı modeller ücretli erişimlidir. Günü UTC ile reset et. Cron'un uzun wall-time hakkı CPU bütçesini büyütmez.

Kaynaklar: [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/), [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/). Dağıtımda yeniden kontrol edilir. Free WAF özellikleri/queues bütün özellikleri var diye kabul edilmez.

Başlangıç batch limitleri küçük config, telemetry ile ayar; kaynak+AI+OAuth+FCM hepsi subrequest sayılır. Request hesabı aktif kurulum × günlük meta+delta/detail+registry + scheduler+send, worst-case cache-miss. Örnek 10.000 aktif × 8 HTTP =80.000/gün; 12 istek120.000 aşar. Cache hit ve304 Worker request sayısını yok etmez. D1 fanout10.000 recipient×insert+lease+accepted en az30.000 row mutation/event, indeks/retry hariç; birkaç geniş ilan ücretsiz write kotasını tüketebilir. Topic genel broadcasts personalized exact match'in yerine konmaz.

AI kapasitesi modelin gerçek input/output neuron tüketiminden N= floor(dailyBudget / measuredPerNotice); uzun notice, batch/retry payı ayrı. Free model Türkçe doğruluk barını geçmezse daha güçlü ücretli modele sessiz geçiş yok; AI alanları kapalı, basic sourced catalogue ve honest unknown ile ürün sınırı kaydedilir.

CPU p95+p99, request, D1 scan/write, cache, neuron, outbox age/retry, source lag ve wide-match dağıtımı pilotta ölçülür. Kota rezervasyonu dayanıklı ve ölçülen billing ile karşılaştırmalı; uygulama counters provider limitini birebir garanti etmez. Limit yaklaşırken yeni ingestion/AI/fanout hızını düşür, pending işi koru; receiver sayısı+deadline kapalı varsayımlarla hiçbir ücretsiz 10k teslim SLA sözü yok.

## 9. Mobil premium ekranları

- Ana ekran / Sizin için: cache hemen, son update/stale, sekmeler+arama, kriter chip'leri, doğrulanmış eşleşme ve ayrı kontrol-gereken listesi.
- Profil / Etiketler: skippable kısa onboarding, kullanıcı isimli search, sayı/puan validasyonu, ortak seçeneklerde arama, düzenle/sil/instant-digest-off, canlı cache sonuç sayısı. Rastgele kelime etiketi q davranışı açık.
- İlan: kurum/pozisyon/yer/deadline, kısa AI summary, requirementGroups ayrı kartlar, alıntı kaynağı, unknown açıklaması, sticky resmi başvuru; favori offline kalır.
- Bildirim merkezi: stable eventId, bir ilana uyan aramalar, accepted ile opened ayrımı, cache boş detail fetch, opt-out/delete.
- Ayarlar/kaynaklar: sunucunun kaynak sağlık durumu, erişim kısıtı ve son başarı; cache refresh kaynağı direkt scrape değil. İzin+sunucuya aktarılacak kriter açıklaması yüksek niyet anında.

Mevcut Pro/reklam, tema, skeleton, motion, favori/backup ve Türkçe korunur. UI visual review telefon/tablet/dark/light/1.3x, release cihazda <100ms görünür tepki hedefi; performance server sync bekletmez.

## 10. Geçiş ve bitiş koşulları

Görev sırası PB-016 → PB-017 → PB-018 → PB-019 → PB-020 → PB-021. PB-020 tasarım/mock işi sözleşme sonrası paralel değil bağımsız ilerleyebilir; tek aktif uygulama görevi yeterli.

Önce runtime/typed contract/Free viability, sonra data+AI, matching+FCM, mobile sync+cutover, premium UX, security/load/release. Telefon local ağ yolları ve Workmanager ancak remote katalog+detail+city coverage/push/offline+cache migration kanıtından sonra kaldırılır. Eski backend adapters/models önce reference, ardından used parts+fixtures korunarak Google/runtime deploy kodu silinir. Bütün caller'lar rg ile taranır; yalnız named path'te düzeltme yok.

Başarı: resmî kaynaklar server tarafından merkezi çekilir veya honest blocked; aynı içerik tekrar AI yok; bir kadro tutarlı eşleşir; kişisel isimli arama typed kriterdir; unknown push yok; sync crash/tombstone null/favori korunur; offline cache; cihazdan scrape yok; foreground/closed-app/tap real Android ve iOS; izin/off/delete/token; wide-match kapasite ve maliyet guardrails; premium/accessibility; source terms/privacy/store checks. Kodun varlığı tamamlandı demek değildir.

Açık/deferred: Free model seçimi pilotla, server kaynak erişimi, Windows dışı iOS/APNs, gerçek 10k Free kapasite. Serbest AI sohbet/ses phase2, ücretli bağımlılık varsayılmaz. “ALH” anlamı belirsiz; yeni anlam icat edilmez. Store üyelik/yayın maliyetleri işletim Free hedefinden ayrı insan/release sınırıdır.
