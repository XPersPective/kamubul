# KamuBul — Cloudflare/FCM Geçiş Yol Haritası ve Devir Notu

30 Eylül 2026. Güncel çalışma yönü: ücretsiz merkezi backend + premium hesapsız Flutter. Bu belge başlangıç/sıra/kanıt rehberidir; tek ayrıntılı hedef `.project-brain/target.md`, tek mevcut mimari `.project-brain/current.md` içindedir. Eski local/Google mimarisini tamamlanmış yeni sistem gibi anlatmayın.

## 1. Önce okunacaklar

1. PROJECT_BRAIN.md §0 ve project-brain skill.
2. Git status/checkpoint; başka ajanın değişikliklerini ezmeyin.
3. `.project-brain/config.yaml`, `current.md`, `target.md`, `constraints.md`.
4. `decisions/ADR-001.md`, ardından `tasks/PB-016.md`.
5. İlgili source/caller/test; bütün geçmişi yeniden taramak gerekmez.

**Başlangıç gerçeği:** Cloudflare Free test Worker Hello World, boş D1 DB binding, Firebase Spark FCM v1 ve Android client config hazır. Katalog/pipeline/AI/FCM sender sunucuda çalışmıyor. Mobilde local fetching+Workmanager ve native Dart reference backend var. Secret erişim grants, Workers AI Free pilotu ve real device checks eksik.

## 2. Kullanıcıya verilecek etiket modeli

Kullanıcı kendi aramasını isimlendirir; içerik statik/typed ortak alanların kişisel kombinasyonudur. “Ankara mühendisi” isim, şehir+meslek+KPSS+yaş kriterler. Puan/yaş sayısal koşul; şehir/meslek eğitim ortak kod; serbest sözcük keyword, global tag değil. Kendi ismini yazmak AI çağrısı yaratmaz.

AI bütün kullanıcı profillerini okumaz. Yeni/değişmiş ilanı bir kez özetler ve koşul adaylarına ayırır. Aynı output bütün kurulumlar için ortak; server deterministic predicate hangi subscriptions eşleştiğini bulur. Kullanıcı sayısı model token sayısını artırmaz; fanout/FCM/D1 maliyeti ayrı büyür. Typed model, multi-kadro grupları, unknown politikası ve örnek target.md §3–6.

## 3. Dışarıda yapılacak sıra

| Faz / görev | Sonuç | Çıkış kapısı |
| --- | --- | --- |
| PB-016 | TS/JS Worker runtime, v2 typed criteria/API/JSON parity, D1 schema/query plan | Free CPU pilotu, sözleşme fixture'ları, migration/index ölçümü |
| PB-017 | Resmî list/detail, contentHash/revision/processing, Workers AI, kanıtlı catalogue/change-log | Aynı içerik yeniden AI yok; kaynak erişimi/quality/neuron ölçümü |
| PB-018 | Kurulum registry, indexed candidates, exact matching, cursor/outbox, least-privilege FCM | Tek dev Android push + off/delete/retry/dedupe/quiet; no lost pending |
| PB-021 | Telemetry/quota/security/canary/release | Sentetik100→1k→10k worst-case, actual cloud/cihaz/terms/privacy kanıtı |

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

Pilot kaynak30dk kontrol; gerekli olduğunda cadence ölçülür. AI Free model+Türkçe precision ve metin/neuron metrikleri; paid provider fallback yok. Kota tükenince processing/outbox dayanıklı bekler/cache korunur, kullanıcı durumu görür. “Aynı içerik için bir kez” başarılı inference içindir; failed retry de kota tüketir. Çok geniş aramalarda teslim gecikmesi ölçülmeden instant garanti verilmez.

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

Yeni Worker test/dev/deploy komutları PB-016 gerçek proje kurulduğunda yazılacak; mevcut olmayan npm script'leri çalışıyor gibi yazmayın. Current.md test sonucu ile canlı bulut sonucu ayrıdır. Flutter baseline unnecessary_import uyarıları yeni regresyon değildir; ilgili future test düzenlemesinde giderin.

Bir sonraki ajan ilk önce PB-016 acceptance'ı refine eder, tek-source Free CPU/typed conformance check bırakır; Hello World'i gerçek API diye mobile'a bağlamaz. Görev tamamlanınca current reconcile, runnable checks, diff/secret review, checkpoint ve push, completed task silme. Kesilirse Verified/Incomplete/Failure/Next-action resume notes. Ücretli plan, gerçek private key/public grant veya store publish sınırına gelirse bu aşamada gerekli insan işlemini açık belirtir; teknik olarak henüz yapılmamış işi completed yazmaz.
