# Kaynak kayıt defteri

Güncel işletim: kalıcı Cloudflare Worker `kamubul-api` + D1 `kamubul`.
Kaynak kodu `workers/src/sources.js`, merkezi toplama `workers/src/pipeline.js`.
Google Cloud Run veya eski `backend/` zamanlayıcısı işletim mimarisi değildir.
Son kontrol: 3 Ekim 2026. Cloudflare çıkışı ile geliştirme bilgisayarından alınan
sonuçlar ayrı kanıttır; yerel erişim sunucunun erişebildiğini göstermez.

| Kaynak | Merkezi getirme yöntemi | Canlı Cloudflare sonucu | Açık iş |
| --- | --- | --- | --- |
| Kariyer Kapısı | Public `ilan/GetIseAlimPage` JSON; başarısızsa resmî `/RSS`. Ayrıntı: `ilan/GetIlanPreviewPublic` ve `altilan/GetAltIlanInfoByIlanIdPublic` POST | RSS üzerinden23 gerçek ilan/46 immutable değişiklik. Güncel Cloudflare remote preview ayrıntı HTTP522; kaynak notu eksik ayrıntıyı belirtir | Kaynak ayrıntısına gerçek Worker erişimi, kullanım şartları, yeterli belge üzerinden model değerlendirmesi |
| Kamu İlanları SBB | `https://kamuilan.sbb.gov.tr/` GET WebForms token'ları + POST yıl; parser `parseSbbList`; sabit resmî ilanDetay.aspx PDF'si native AI.toMarkdown text okuyucusuna gider | Erişim engeli; `blocked` raporlanır. Kaynak başarıyla toplanmış kabul edilmez | Gerçek Worker PDF erişimi/dönüşümü/kalitesi/CPU ve sayfa sınırı, kullanım şartları |
| İŞKUR | Telefon (TR IP): `esube.iskur.gov.tr/Istihdam/AcikIsIlanAra.aspx` GET + "Kamu" filtresiyle tek WebForms POST (`lib/listings/iskur_feed.dart`). GET linkiyle filtre yok. Yalnız kamu satırları (onclick ve işyeri türü "Kamu"); filtre yoksa okuma yapılmaz. Ayrıntı `AcikIsIlanDetay.aspx?uiID=…&isyeriTuru=Kamu` girişsiz | 4 Ekim 2026: 9 kamu ilanı (belediyeler dahil), son başvuru tarihli. Sunucuda adaptör yok | Özel sektör ilanları KAPSAM DIŞI (kullanıcı kararı). robots.txt yalnız meslek popup'ını yasaklar; oturum/CAPTCHA aşılmaz |
| ilan.gov.tr | SUNUCU (5 Ekim): Cron kaynak aşaması `fetchIlanGovList` (≤10×20) + `fetchIlanGovDetail`; ilk anlık görüntü bildirim üretmez; işlenen ilan için kanonik şart ayıklaması (`canonicalConditions`, ADR-006 önbellek/kira/tavan). Telefon (`lib/listings/ilangov_feed.dart`) sunucu kaynağı `ok` ve 36 saatten taze olana kadar okumaya devam eder | Cloudflare çıkışı 200; ilk parti 162 ilan, tur başına 1 ilan (Free CPU) → ilk tam tur ~8–10 saat. Son başvuru yapılandırılmış değil → null. Sunucu ve telefon URL'leri birebir aynı (birleşir) | robots.txt yalnız tebligatı yasaklar. Dokümansız iç API; düzen değişirse `layout_changed`, tahmin yok |
| Resmî Gazete | Kapsam dışı; adaptör kaldırıldı | Yeni veri toplanmaz | Eski cihaz cache'i görülürse geçiş/retention kuralları uygulanır |
| Belediyelerin ayrı siteleri | Ayrı adaptör yok; belediye personel ilanları ilan.gov.tr (BİK) ve İŞKUR kamu işçi ilanlarıyla gelir | — | Belediye başına scraper eklenmez |

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
