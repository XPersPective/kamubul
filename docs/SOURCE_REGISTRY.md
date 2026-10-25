# Kaynak kayıt defteri

Güncel işletim: kalıcı Cloudflare Worker `kamubul-api` + D1 `kamubul`.
Kaynak kodu `workers/src/sources.js`, merkezi toplama `workers/src/pipeline.js`.
Google Cloud Run veya eski `backend/` zamanlayıcısı işletim mimarisi değildir.
Son kontrol: 25 Ekim 2026 (`PB-030`). Cloudflare çıkışı ile geliştirme bilgisayarından alınan
sonuçlar ayrı kanıttır; yerel erişim sunucunun erişebildiğini göstermez.

| Kaynak | Merkezi getirme yöntemi | Canlı Cloudflare sonucu | Açık iş |
| --- | --- | --- | --- |
| Kariyer Kapısı (`kariyerkapisi`) | `workers/src/sources.js:95-130` (`fetchKariyerList`: `ilan/GetIseAlimPage` POST, hata durumunda `/RSS` `parseKariyerRss`; `fetchKariyerDetail`: `ilan/GetIlanPreviewPublic` + `altilan/GetAltIlanInfoByIlanIdPublic` POST) ve `workers/src/pipeline.js:37-56,119-166`. Test: `workers/test/kariyer-source.test.js` | RSS üzerinden gerçek ilan listesi (`status: ok` veya `processing`); Cloudflare egress'ten ayrıntı HTTP 522 döndüğünde `detailState: 'unavailable'` işaretlenir, önceki başarılı ayrıntı silinmez (`pipeline.js:132-136`) ve kaynak notunda eksik ayrıntı sayısı açıkça raporlanır (`pipeline.js:164-166`) | Cloudflare çıkışından ayrıntı API'sine kesintisiz erişim ve açık yeniden dağıtım lisansı doğrulaması |
| Kamu İlanları SBB (`sbb`) | `workers/src/sources.js:132-169` (`fetchSbbList` + `parseSbbList`) ve `workers/src/pipeline.js:19-36` (`readSbbDetail`: `ilanDetay.aspx?kod=...` PDF byte doğrulaması + `env.AI.toMarkdown`, günlük 20 PDF bütçesi, 3 MiB/45 sn/120 KB sınır). Test: `workers/test/sbb-source.test.js`, `workers/test/pdf-source.test.js` | Cloudflare çıkışında erişim engeli (HTTP 403/522) nedeniyle `state: 'blocked'` raporlanır (`pipeline.js:168`). Engelli kaynak hiçbir zaman tamamlanmış (`ok`) sayılmaz; mağaza metninde (`docs/growth/STORE_COPY.md`) SBB vaadi yer almaz | Gerçek Worker PDF erişimi/dönüşüm kalitesi ve kullanım şartları |
| İŞKUR (`iskur`) | Sunucu: `workers/src/sources.js:171-226` (`fetchIskurList` WebForms `kamuRadio` + 50 sayfa pager + `fetchIskurDetail` `ÖZEL ŞARTLAR`/`Genel Hususlar`). İstemci yedek yolu (TR IP): `lib/listings/iskur_feed.dart` (sunucu kaynağı `ok` ve taze değilken çalışır). Test: `workers/test/iskur-source.test.js` | Yalnız `Kamu` işyeri türü satırları kabul edilir (`sources.js:180`); özel sektör ilanları kapsam dışıdır. Cloudflare çıkışında HTTP 500/engel görülürse kaynak `failed`/`blocked` kalır ve istemci TR IP yedek yolu devreye girer | Özel sektör ilanları kapsam dışı (C-001). Oturum/CAPTCHA aşılmaz |
| ilan.gov.tr (`ilangov`) | Sunucu: `workers/src/sources.js:36-94` (`fetchIlanGovPage`, `fetchIlanGovList`, `fetchIlanGovDetail`, `privateEmployer` filtresi) ve `workers/src/pipeline.js:70-91` (tur başına 3×20 sayfalama, `source_detail_runs` 2 deneme tavanı). İstemci yedek: `lib/listings/ilangov_feed.dart`. Test: `workers/test/ilangov-source.test.js`, `workers/test/ilangov-pipeline.test.js` | Cloudflare çıkışı HTTP 200; tam metin (`detailState: 'available'`), tablo hücre sınırları (`plain()` `sources.js:25-33`), `son basvuru tarihi` ve `resmi gazete yayim tarihi` kanıtlı olarak ayrıştırılır (`sources.js:78-88`). Özel dernek/okul ilanları `privateEmployer` ile elenir (`pipeline.js:94-95,123`) | Dokümansız iç API; şema değişirse `layout_changed` hatası verir, tahmin yürütülmez |
| Resmî Gazete | Doğrudan adaptör kapsam dışı; ilan.gov.tr personel ilanlarındaki `resmi gazete yayim tarihi` üstverisi (`gazettePublishedAt`) korunur | Ayrı tarama yapılmaz | — |
| Belediyelerin ayrı siteleri | Ayrı adaptör yok; belediye personel ilanları `ilangov` (BİK) ve `iskur` kamu işçi ilanlarıyla gelir | — | Belediye başına scraper eklenmez |

## Zamanlama ve güvenlik

- Tamamlanan kaynak turundan sonra30dk bekleme; tek kalıcı batch ve lease.
  Her source invocation en çok1 batch girdisi tüketir; üç-slot Cron'da
  source/AI, matching, send ayrı çalışır. Source slotu3dk olduğundan23 girdi
  yaklaşık69dk + tur sonu30dk bekleme gerektirebilir;30dk full-refresh SLA yok.
  Saatlik `:59` registry+katalog bakımına ayrılır. Bu sınırlar sağlayıcının
  ticari hız sınırı izni değildir; kullanım şartları doğrulaması açık kalır.
- Yeniden kontrol süresi kayıt başına başarılı akışta6saat, geçici ayrıntı
  hatasında30dk. Önceki başarılı ayrıntı/özet hata nedeniyle silinmez.
  Eksik/güncellenemeyen ayrıntı kaynak notunda belirtilir.
- HTTPS ve kaynak host allowlist, manuel redirect/redirect reddi,25s timeout,
 3MB yanıt sınırı. Private/isteğe bağlı key, oturum veya CAPTCHA aşma yok.
- Uygulama kartı kaynak adı ve resmî bağlantı gösterir. Kullanıcının resmî
  başvuru/belge bağlantısını açması otomatik scraping değildir.
- robots.txt, yeniden yayınlama/kullanım şartları ve source-specific izin/hız
  sözleşmeleri henüz doğrulanmadı. Başarılı GET, yeniden yayınlama izni kanıtı
  değildir; release kapısı açık kalır.

## Ayrıntı API'si kontrolü — 2 Ekim 2026

Geliştirme bilgisayarı resmî RSS'yi ve `IlanDetay` HTML/JavaScript'ini alabildi.
Public `Infrastructure` JavaScript'i API kökünü
`https://api.kariyerkapisi.gov.tr/api` olarak tanımlar; public `IlanDetayV1`
JavaScript'i Worker'da kullanılan aynı iki ayrıntı POST rotasını çağırır.
Adresler güncel site koduyla uyumludur; bu kontrol Worker'daki522'nin nedenini
veya oradan başarılı erişimi kanıtlamaz. IP/coğrafya nedeni tahmin edilmez.

Kontrol edilen RSS açıklaması başlığı tekrarlar; ayrıntı HTML'i API'den
sonradan doldurulan alanları içerir, doğrudan koşul metni vermez. Bunlardan
yaş/KPSS/eğitim koşulu ya da sahte ayrıntı üretilmez. Yeni bir izinli kaynak
kanıtı olmadan alternatif host/proxy eklenmez.

## Mobil geçiş ve çıkarım kanıtı

3 Ekim yeniden kontrolünde aynı resmî adaptörün Cloudflare çıkışında Kariyer
ayrıntısı HTTP522/20115ms, SBB `blocked`/416ms verdi. TKGM'nin
[28 Eylül tarihli resmî duyurusundaki](https://www.tkgm.gov.tr/duyurular/tapu-ve-kadastro-genel-mudurlugu-sozlesmeli-bilisim-personel-alim-ilani)
[orijinal PDF](https://cms-api.tkgm.gov.tr/media/101807/view) geliştirme
bilgisayarında HTTP200/application/pdf/215635 byte ile açıldı; aynı sabit URL
Cloudflare no-binding preview'da HTTP522/19476ms verdi. Preview kapatıldı,
üretim verisi/AI/FCM değişmedi. Bu aday çalışan sunucu adaptörü veya yeniden
yayınlama izni sayılmaz; yerel PDF üretime yüklenmedi. Engelin IP/coğrafya
nedeni doğrulanmadı; üçüncü taraf proxy/WAF aşma eklenmedi.

Son kalıcı Workere284e590;162 native/dry-run/deploy ve canlı46change/23catalogue/
applied46/detail/missing404/meta304 geçti. SBB native PDF okuyucusu binary
hash+reader version ile başarılı metni cache'ler;20 UTC günlük atomik dönüşüm
rezervasyonu,3MiB fetch/45s conversion/120KB UTF-8 output sınırı vardır.
Metadata-only PDF değişimi aynı metin için yeni summary işi açmaz. Sayfa-count
ve OCR yok; boş/hatalı belge unknown ve eski başarılı metin korunur.
AI-only native remote preview supported() PDF=true/28 format doğruladı ve
kapatıldı. Belge dönüşümü yapılmadı; bu sonuç SBB egress/kalite/CPU kanıtı
değildir. Yerel PDF testlerinde byte fixture/converter stub vardır, üretim
verisine eklenmez. Gerçek kaynak erişimi ve AI precision kapıları açıktır.

Son kalıcı Worker58d0511e,158 native/dry-run/deploy ve canlı46change/23catalogue/
applied46/detail/missing404/meta304 kontrolü geçti. SBB parser mevcut resmî
kayıtlı HTML'deki `class ='black'` boşluğu yüzünden layout_changed veriyordu;
iki satır şablonunda attribute boşlukları düzeltildi. Aynı55 etiketli liste
satırında kurum/başlık/kategori/start/deadline gold eşitliği geçti. Başlangıç
Türkiye00:00, son tarih Türkiye23:59:59; implicit yıl geçişi/leap day, açık
çelişkili yıl ve geçersiz tarihte unknown kontrolleri var. Bu liste çıkarımıdır;
AI yaş/KPSS/eğitim veya PDF precision kapısını karşılamaz.

Son readonly D1 kaynak: Kariyer last_success17:21:08.812Z/ayrıntı failure notu,
SBB blocked last_attempt17:24:08.873Z;23/23 unavailable. SELECT4+23read,
0written/changed=false. SBB Web aracı aynı resmî kökte403 gördü; bunun
Cloudflare egress ölçümü veya yeni kaynak izni olduğu varsayılmaz. Yerel corpus
üretime aktarılmadı, fixture/push/AI çağrısı oluşturulmadı.

16:33UTC yeni diagnostic: binding'siz resmî Wrangler remote preview üzerinde
aynı kaynak adaptörü/izinli adres çağrıldı. Kariyer detail20.240ms HTTP522,
SBB579ms blocked. Yanıt HTTP200 diagnostic envelope'dir; kaynak başarı değildir.
Preview process kapatıldı, production deploy/D1 write/AI/FCM yapılmadı. Aynı
an production readonly Kariyer processing/last_attempt16:18:04.655Z,
last_success15:45:04.670Z;23/23 unavailable. SELECT4+23rows,0write/changed=false.
Resmî kullanım şartı araması hâlâ kaynak-specific izin doğrulamadı; arama
sonucu yokluğu izin/yasak kanıtı değildir.

2 Ekim son cloud readonly kontrol: canlı API23 ilan/46change/detail/missing404/
meta304 başarılı. D1 Kariyer last_success2026-10-02T15:45:04.670Z, son not
ayrıntı yenilemesi başarısız/eski veri korunuyor; SBB blocked15:48:04.711Z.
23 ilanın tamamı detailState unavailable, full source text0;23 completed
processing işi source-only, AI koşul/özet başarısı sayılmaz. Sorgular yazma0.
Cloud success list toplama başarısıdır, tam detail başarısı değildir.
SourceFetch unread HTTP/oversize response'ları iptal eder; cleanup hatası veya
gecikmesi retry'ı durdurmaz.149 native test/dry-run ve5dbc7649 deploy geçti.
3MiB actual streamed cap, HTTP classification, bodyless response/stream error
ve allowlist kontrolleri vardır. Yeni sürümde başarılı detail/AI/CPU kanıtı
değildir. Son inline readonly D1 sonuçları0written/changed_db=false; fixture yok.

Son Windows readonly kontrol: aynı resmî detail adaptörü ile
12c5b0ac-cd05-4316-9d7c-39ed4d06a358 için273ms'de main7113 karakter/11 kadro
ve2026-10-19T14:00:00Z deadline alabildi. D1 aynı ilanda eski kayıtlı
detail_error=source_http_522 /detail_state=unavailable taşıyor; son source
notu ayrıntı başarısızlığını koruyor. Bu eski payload hata kodu son denemenin
tam HTTP sonucunu kanıtlamaz. Yerel ayrıntı üretime aktarılmadı, proxy yok.
Windows robots.txt GET Kariyer ve SBB'de404: bunun yeniden yayınlama izni
olduğu varsayılmaz; kullanım şartları/release kapısı açık. Web aracı bu iki
URL'yi alamadı, resmî kullanım şartı araması sonuç vermedi; yokluk kanıtı değil.
ADB envanteri yalnız emulator-5554/5556; fiziksel cihaz teslimi doğrulanmadı.

Telefonun eski fetch/Workmanager yolları yalnız pilot tamamlanmadığı için
geçiş kodunda durur; hedef30dk merkezi sunucu çekimidir. Kodun hâlâ çalışması
hedef mimari kabul edilmez. Telefon okuyucusu 5 Ekim'de kaldırıldı; kalan kabul `.project-brain/tasks/PB-029.md`.

Önceki Dart fixture corpus sonuçları gerçek Workers AI doğruluk ölçümü
sayılmaz. Kaynak alıntısı olmayan koşul belirsizdir; AI alanlarının precision
kapısı kapalıdır. Free modelden en az50 etiketli örnek/kaynak, recall/precision,
neuron ve CPU ölçümü hâlâ yapılmalıdır. Kullanıcı profilleri modele gönderilmez.

## 5 Ekim ayıklama ve kaynak kontrolü
Cloudflare çıkışında ilan.gov.tr filtreli personel listesi HTTP200 (20/162),
aynı adapter resmi2244449 ayrıntısını23186karakter okudu. Kod:
workers/src/sources.js fetchIlanGovPage/fetchIlanGovDetail. Cron'a henüz bağlı
DEĞİLDİR; source status hâlâ blocked. Merkezi sayfalama/ilk tarama push
bastırma/50 örnek kalite/Free CPU kapıları PB-029'da. İŞKUR arama GET aynı
preview'da HTTP500 verdi; Kamu filtresine ulaşılamadı, özel sektör okunmadı.
Preview DB/FCM binding içermez. Bu sonuç eski ilan.gov erişilemiyor varsayımını
kaldırır; full server-only cutover veya resmî yeniden yayın izni ispatı değildir.

## 6 Ekim 2026 — yeniden dağıtım kabulü

PB-029 kaynak kullanım incelemesi: **izin kapısı açık**. Basın İlan Kurumu'nun
[kendi yayımladığı İlan Portalı Yönetmeliği](https://bik.gov.tr/wp-content/uploads/2021/10/bik-ilan-portal-yonetmeligi.pdf)
madde 9 kullanım koşullarını Genel Müdürlüğe bırakır; madde 10, Kurumun telif
hakları kapsamındaki içeriklerin çoğaltılması/işlenmesi/dağıtılması için açık
izin öngörür. Bu bulgu, her kamu ilanının hukuki statüsü hakkında bir karar değildir;
KamuBul'un tam metin saklama/API/offline dağıtımının izin kapsamında olduğu
henüz kanıtlanmadı. Kaynak linki veya robots erişimi tek başına izin kanıtı sayılmaz.

[Kariyer Kapısı](https://kariyerkapisi.gov.tr/) ve [İŞKUR](https://www.iskur.gov.tr/)
ana sayfalarında KamuBul'un kullanımına ilişkin açık yeniden dağıtım lisansı
doğrulanamadı; [SBB](https://kamuilan.sbb.gov.tr/) inceleme isteği 403 döndü.
Arama sonucu yokluğu izin/yasak sayılmaz; iskur.org resmî İŞKUR değildir.
Sahip: proje sahibi, kaynak izni veya kullanımın hukuki dayanağını doğrular.
Bu kayıt hedef mimariyi veya mevcut ingestion davranışını değiştirmez.

## 25 Ekim 2026 — PB-030 Kaynak Kapsamı, Kalıcı Tam Metin ve Mağaza Uyumu

1. **Mağaza metni (`docs/growth/STORE_COPY.md`) ile gerçek kaynak kapsamı uyumu:**
   - Mağaza açıklamalarında yalnızca doğrulanmış kapsamdaki kaynak/ilan türleri ("Kariyer Kapısı, İŞKUR kamu işçi ilanları, ilan.gov.tr ve belediye/üniversite personel duyuruları") anılır; Cloudflare çıkışında `blocked` olan `sbb` (`kamuilan.sbb.gov.tr`) için mağazada erişim vaadi verilmez.
2. **Kalıcı tam metin (`detailState`) ve hata izolasyonu (`workers/src/pipeline.js`):**
   - `readNoticeDetail` (`pipeline.js:37-56`) her ilan için `source_detail_runs` tablosunda `input_key` başına en fazla 2 okuma denemesi (`attempts<2`) ve 6 saatlik bekleme (`later(360)`) uygular.
   - Ayrıntı okunamadığında (`detailState: 'unavailable'`), önceki başarılı `text` ve `summary` asla silinmez (`pipeline.js:132-136`); yeni ilanlarda `detailState` açıkça `'pending'` veya `'unavailable'` olarak kalır ve kaynak durumunda (`sources.note`) eksik ayrıntı sayısı açıkça raporlanır (`pipeline.js:164-166`).
   - HTTP 401/403/429 yanıtları `SourceError('blocked')` üretir (`sources.js:11`) ve `sources.state = 'blocked'` olarak kaydedilir (`pipeline.js:168`); engelli kaynak hiçbir koşulda `ok` sayılmaz.
3. **Odaklı kaynak test kapsamı (9 test dosyası, tamamı yeşil):**
   - `workers/test/source-fetch.test.js` (HTTPS/host allowlist, 3 MiB akış sınırı, 401/403/429 `blocked` sınıflandırması)
   - `workers/test/kariyer-source.test.js` (`parseKariyerIndex`, `/RSS` yedeği, `parseKariyerDetail` kadro/kontenjan ayrıştırması)
   - `workers/test/ilangov-source.test.js` ve `workers/test/ilangov-pipeline.test.js` (sayfalama, `privateEmployer` elemesi, tablo hücre koruma, `son basvuru tarihi` / `resmi gazete yayim tarihi`)
   - `workers/test/iskur-source.test.js` (`kamuRadio` zorunluluğu, yalnızca `Kamu` satırlarının alınması, pager, `parseIskurDetail`)
   - `workers/test/sbb-source.test.js` ve `workers/test/pdf-source.test.js` (`parseSbbList`, `%PDF-` doğrulaması, `pdf_daily_budget`, `blocked` durumunun korunması)
   - `workers/test/contracts.test.js` ve `workers/test/pipeline.test.js` (uçtan uca D1/API sözleşmeleri ve kısmi/engelli kaynak davranışları)
