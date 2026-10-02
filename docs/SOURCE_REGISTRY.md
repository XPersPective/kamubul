# Kaynak kayıt defteri

Güncel işletim: kalıcı Cloudflare Worker `kamubul-api` + D1 `kamubul`.
Kaynak kodu `workers/src/sources.js`, merkezi toplama `workers/src/pipeline.js`.
Google Cloud Run veya eski `backend/` zamanlayıcısı işletim mimarisi değildir.
Son kontrol: 2 Ekim 2026. Cloudflare çıkışı ile geliştirme bilgisayarından alınan
sonuçlar ayrı kanıttır; yerel erişim sunucunun erişebildiğini göstermez.

| Kaynak | Merkezi getirme yöntemi | Canlı Cloudflare sonucu | Açık iş |
| --- | --- | --- | --- |
| Kariyer Kapısı | Public `ilan/GetIseAlimPage` JSON; başarısızsa resmî `/RSS`. Ayrıntı: `ilan/GetIlanPreviewPublic` ve `altilan/GetAltIlanInfoByIlanIdPublic` POST | RSS üzerinden21 gerçek ilan/42 immutable değişiklik. Kayıtlı ayrıntı hatası HTTP522; kaynak notu eksik ayrıntıyı belirtir | Kaynak ayrıntısına gerçek Worker erişimi, kullanım şartları, yeterli belge üzerinden model değerlendirmesi |
| Kamu İlanları SBB | `https://kamuilan.sbb.gov.tr/` GET WebForms token'ları + POST yıl; parser `parseSbbList` | Erişim engeli; `blocked` raporlanır. Kaynak başarıyla toplanmış kabul edilmez | Worker erişimi ve resmî belge/PDF okuyucu, kullanım şartları |
| İŞKUR | Merkezi adaptör etkin değil; kayıtlı engel açık gösterilir | `blocked`; üretim kataloğuna veri sağlamaz | İzinli herkese açık veri erişimi; oturum/CAPTCHA/WAF aşılmaz |
| ilan.gov.tr | Merkezi adaptör etkin değil; kayıtlı engel açık gösterilir | `blocked`; üretim kataloğuna veri sağlamaz | İzinli herkese açık veri erişimi; engel aşılmaz |
| Resmî Gazete | Kapsam dışı; adaptör kaldırıldı | Yeni veri toplanmaz | Eski cihaz cache'i görülürse geçiş/retention kuralları uygulanır |
| Belediyelerin ayrı siteleri | Ayrı kaynak adaptörü yok | Veri sağlanmış kabul edilmez | Kullanıcı kapsamı/kaynak sözleşmesi olmadan yeni scraper eklenmez |

## Zamanlama ve güvenlik

- Tamamlanan kaynak turundan sonra30dk bekleme; tek kalıcı batch ve lease.
  Her source invocation en çok1 batch girdisi tüketir; üç-slot Cron'da
  source/AI, matching, send ayrı çalışır. Source slotu3dk olduğundan21 girdi
  yaklaşık63dk + tur sonu30dk bekleme gerektirebilir;30dk full-refresh SLA yok.
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

2 Ekim son cloud readonly kontrol: canlı API21 ilan/42change/detail/missing404/
meta304 başarılı. D1 Kariyer last_success2026-10-02T11:12:04.668Z, son not
ayrıntı yenilemesi başarısız/eski veri korunuyor; SBB blocked11:15:04.689Z.
21 ilanın tamamı detailState unavailable, full source text0;21 completed
processing işi source-only, AI koşul/özet başarısı sayılmaz. Sorgular yazma0.
Cloud success list toplama başarısıdır, tam detail başarısı değildir.

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
hedef mimari kabul edilmez. Kaldırma koşulları `.project-brain/tasks/PB-019.md`.

Önceki Dart fixture corpus sonuçları gerçek Workers AI doğruluk ölçümü
sayılmaz. Kaynak alıntısı olmayan koşul belirsizdir; AI alanlarının precision
kapısı kapalıdır. Free modelden en az50 etiketli örnek/kaynak, recall/precision,
neuron ve CPU ölçümü hâlâ yapılmalıdır. Kullanıcı profilleri modele gönderilmez.
