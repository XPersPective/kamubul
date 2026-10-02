# KamuBul — Cloudflare/FCM Geçiş Yol Haritası ve Devir Notu

2 Ekim 2026. Güncel çalışma yönü: ücretsiz merkezi backend + premium hesapsız Flutter. Bu belge başlangıç/sıra/kanıt rehberidir; tek ayrıntılı hedef `.project-brain/target.md`, tek mevcut mimari `.project-brain/current.md` içindedir. Eski local/Google mimarisini tamamlanmış yeni sistem gibi anlatmayın.

## 1. Önce okunacaklar

1. PROJECT_BRAIN.md §0 ve project-brain skill.
2. Git status/checkpoint; başka ajanın değişikliklerini ezmeyin.
3. `.project-brain/config.yaml`, `current.md`, `target.md`, `constraints.md`.
4. `decisions/ADR-001.md`, ardından `tasks/PB-016.md`.
5. İlgili source/caller/test; bütün geçmişi yeniden taramak gerekmez.

**30 Eylül başlangıcı (tarihsel):** Hello World/boş D1 vardı. Bu noktadan başlanmaz. Artık kalıcı API/D1/Cron/Queue ve Flutter v2 cache/FCM kodu vardır. Ayrıntı erişimi, kaynak çıkarım kalitesi, gerçek Queue CPU ve fiziksel cihaz teslimi açık kapılardır. Güncel doğrulanmış durum için `current.md` okunur; bağlanmış servis tamamlanmış ürün kanıtı değildir.

## 2. Kullanıcıya verilecek etiket modeli

Kullanıcı kendi aramasını isimlendirir; içerik typed ortak alanların kişisel kombinasyonudur. “Ankara mühendisi” isim, şehir+meslek+KPSS+yaş kriterler. Puan/yaş sayısal koşul; şehir/eğitim ortak kod, meslek/kurum bugün normalize metindir. Serbest sözcük keyword, global tag değildir. Kendi ismini yazmak AI çağrısı yaratmaz.

AI bütün kullanıcı profillerini okumaz. Yeni/değişmiş ilanı bir kez özetler ve koşul adaylarına ayırır. Aynı output bütün kurulumlar için ortak; server deterministic predicate hangi subscriptions eşleştiğini bulur. Kullanıcı sayısı model token sayısını artırmaz; fanout/FCM/D1 maliyeti ayrı büyür. Typed model, multi-kadro grupları, unknown politikası ve örnek target.md §3–6.

### Çalışan kriter sözleşmesi ve uyumluluk sınırı

`criteriaVersion=2`, `/api/v2/taxonomy` version1: şehirlerde81 sabit `city:` ID;
eğitimde `education:secondary/associate/bachelor/master/doctorate` ID'leri.
Türkçe label ve ilan edilen alias'lar aynı eşleşmeyi verir. Önlisans ve
Yükseklisans alias'tır; kullanıcı yazımı public taxonomy'ye eklenmez. ID anlamı
yeniden kullanılmaz; sonraki anlam değişimi taxonomy/criteria sürümü ve Dart–JS
ortak corpus güncellemesi gerektirir. Meslek/kurum için bugün semantik synonym
çıkarımı yoktur: normalize metin eşleşir, AI desteklenmeyen değeri uyduramaz.

Legacy SavedSearch dönüşümü mevcut Dart `SearchCriteria.fromLegacy` ve JS
`migrateFilters` ile yapılır; yeni ikinci filtre deposu kurulmaz:

| Eski alan | V2 alan / davranış |
| --- | --- |
| q | keyword, keywordScope=title |
| sehir / egitim | cities / education tek elemanlı dizi |
| kpss / kpssPuan | kpssType / kpssScore; puan tek başına kabul edilmez |
| yas / yasTarih | age / ageAsOf; tarih yoksa1970-01-01, yaş unknown kalır ve kullanıcı doğrular |
| kategori1/2/3 | işçi/personel/belediye;0 filtre yok |
| son30=1 | last30=true |

Koşullar aynı kadroda AND, alternatif kadrolarda OR'dur; unknown uygunluk
onayı değildir. Yeni arama server latestSeq ile effective_after alır, geçmiş
ilanlar yeni-ilan push'ına dönüşmez. Mevcut arama güncellenirken baseline korunur;
preference version artışı pending eski payload'ları iptal eder.

`/v1/listings.json` geçiş endpoint'i en fazla5000 aktif ilanı tek snapshot olarak
sunar; v2 delta/tombstone veya çoklu-kadro uygunluk garantisi taşımaz. Legacy
maxAge yalnız tek kadro ve tamamlanmış-yıl semantiğinde gösterilir; tarihli veya
çoklu kadro koşulları null kalır. Mobil v2 sync bu snapshot metodunu çağırmaz;
reference `CatalogueClient.fetchListings` uyumluluk için tutulur. V1 route ve
telefon kaynak/scheduler kaldırılması PB-019 gerçek pilot kapılarına bağlıdır.
Sadece yeni API yayında diye eski client/cache veri migration'ı silinmez.

Kullanıcı isteği ADR-002/PB-022: elle düzenlemeye ek AI kriter asistanı aynı
SavedSearch için create/update/delete taslağı üretir; Uygula/İptal ve stale-version
kontrolüyle çalışacaktır. Ingestion fallback ile assistant ayrı bütçelidir.
Sağlayıcı/model/güvenli secret ve ayrı bütçeler eksik olduğundan henüz etkin
değildir; profil başına ingestion inference veya sahte sohbet açılmaz.

## 3. Dışarıda yapılacak sıra

| Faz / görev | Sonuç | Çıkış kapısı |
| --- | --- | --- |
| PB-016 | TS/JS Worker runtime, v2 typed criteria/API/JSON parity, D1 schema/query plan | Free CPU pilotu, sözleşme fixture'ları, migration/index ölçümü |
| PB-017 | Resmî list/detail, contentHash/revision/processing, Workers AI, kanıtlı catalogue/change-log | Aynı içerik yeniden AI yok; kaynak erişimi/quality/neuron ölçümü |
| PB-018 | Kurulum registry, indexed candidates, exact matching, cursor/outbox, least-privilege FCM | Tek dev Android push + off/delete/retry/dedupe/quiet; no lost pending |
| PB-021 | Telemetry/quota/security/canary/release | Sentetik100→1k→10k worst-case, actual cloud/cihaz/terms/privacy kanıtı |
| PB-022 | Kullanıcının sağlayıcısıyla Free-kota fallback ve kriter asistanı | Gerçek provider/key/ayrı bütçeler, taslak onayı ve manual parity |

Cron tüm ilanı modelde tekrar okumaz: source cursor/identity→aday detay→semantic hash→yeni/değişmiş revision job→tek successful inference. Kaynağın eski ilan düzeltmeleri bounded revalidation ile bulunur. Detay değişimini tespit etmeden yalnız ID'ye güvenmek yeterli değildir. Parser drift AI ile kontrolsüz düzeltilmez; kaynağı degraded işaretleyip fixture güncellenir.

## 4. İçeride yapılacak sıra

| Faz / görev | Sonuç | Çıkış kapısı |
| --- | --- | --- |
| PB-016 | Yeni kriter/model/fixture sözleşmesine mobil karşılık | Eski SavedSearch v1 migration örnekleri |
| PB-019 | cache-first remote sync, full snapshot watermark/delta/ETag/tombstone/null; FCM UI/token/tap | Crash/offline/bookmark migration, real Android, no outbound source scrape |
| PB-020 | Premium profil/search editor, özet/kanıt/kadro ve notification center | Golden/responsive/contrast/semantics ve release cihaz görsel+tepki testi |
| PB-021 | iOS/APNs, izin/privacy/store purchase/restore/release | Android+iOS real-device ve store sandbox/signing sahibi |

Kişi filtre değiştirince kaynak+model tekrar çalışmaz; yerel catalogue eşleşmesi ve küçük registry update yeterli. Bildirimi OS cihazda gösterir, matching/scheduling/send server'dadır. FCM kaçarsa açılış delta sync ve authenticated event history toparlar.

## 5. Eski yapıyı kaldırma sınırı

Bu hizalamada eski PB-004/005/006/008/010–015 görevleri aktif ağaçtan kaldırıldı, kalan kabul işleri yeni görevlere aktarıldı. Cloud Run/Blaze/VPS/Docker deployment scaffolding silindi. Native Dart kaynak/testleri yalnız geçiş referansı; shared core mobil için gerekli.

Eski görevlerin devam karşılığı: PB-004/013→018+019; PB-005 AI summary→017, serbest chat/speech deferred; PB-006→021; PB-008→020+021; PB-010→016+017; PB-011→019; PB-012→017; PB-014/015→021 ve yeni sıradaki canlı kapılar. Tamamlanmış geçmiş Brain'de arşiv klasörüne kopyalanmadı, Git'te.

Yerel runtime silme PB-019'da: refreshCatalogue fallback, refreshKariyerCity, home şehir yenileme, ListingGuide detail fetch, main registerBackgroundAlerts, Workmanager callback, runAlertCheckOnce discovery/digest/state. **Bütün caller'ları bulun.** API list kadar city/detail de karşılamalı. Notification rendering/tap/favori/export/SQLite ve core fixtures kalır; eski scheduler görevini cancel etmeyi unutmayın. Telefon fallback source blocker'ı gizleyen hedef değil.

## 6. Ücretsiz kullanım kapısı

10.000 kurulum ücretsizliği garanti değil. Güncel resmi limit ve hesap senaryoları target.md §8. En kritik: Free HTTP/Cron CPU10ms; broad fanout'da outbox write+lease+accepted+index+retry, source list değişmeden yapılan reads;304/cache hit request kotası. Eski native25parallel send planı Worker'a kopyalanamaz.

Kaynak cadence30dk ayarı tam tur30dk garantisi değildir; tek girişlik aşama batch'i daha yavaş tamamlar. AI Free model+Türkçe precision ve metin/neuron metrikleri ölçülür. ADR-002 kapsamındaki kendi-provider fallback PB-022 ayarları doğrulanana kadar kapalıdır. Kota tükenince processing/outbox dayanıklı bekler/cache korunur. “Aynı içerik için bir kez” başarılı inference içindir; failed retry de kota tüketir. Kalıcı Queue max4 instant recipient/task ve shared3000 günlük rezervasyonla çalışır; matching aynı bütçeyi paylaşır. Gerçek throughput için `docs/FANOUT_CAPACITY.md`; geniş aramada instant/aynı-gün garantisi verilmez.

## 7. Doğrulama/devir koşulları

Baseline komutlar (depo kökünden ilgili working-directory ile):

```sh
cd packages/kamubul_core
dart analyze
dart test
cd ../../backend
dart analyze
dart test
cd ..
flutter analyze
flutter test
```

Worker kontrolleri `workers/` içinde `npm test`, `node tool/check-fanout.js` ve
`npx wrangler deploy --dry-run` ile çalışır. Deploy/migration mevcut güvenli
Wrangler oturumuyla yapılır; secret dosyası/logu üretmeyin. Kapasite aracı
in-memory SQL/injected sender kullanır, gerçek Queue/FCM/CPU kanıtı değildir.
Current.md test sonucu ile canlı bulut sonucu ayrıdır.

Bir sonraki ajan current/task Resume'deki ilk doğrulanmamış kapıdan devam eder;
kalıcı altyapıyı yeniden kurmaz. Görev tamamlanınca current reconcile, runnable
checks, diff/secret review, checkpoint ve push, completed task silme. Kesilirse
Verified/Incomplete/Failure/Next-action resume notes. Mevcut canlı kurulum
yetkisini korur; credential/store/ücret sınırında olmayan işi tekrar onaya
götürmez. Teknik olarak henüz yapılmamış işi completed yazmaz.
