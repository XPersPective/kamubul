# Kaynak kayıt defteri

Güncel işletim: kalıcı Cloudflare Worker `kamubul-api` + D1 `kamubul`.
Kaynak kodu `workers/src/sources.js`, merkezi toplama `workers/src/pipeline.js`.
Google Cloud Run veya eski `backend/` zamanlayıcısı işletim mimarisi değildir.
Son kontrol: 2 Ekim 2026. Cloudflare çıkışı ile geliştirme bilgisayarından alınan
sonuçlar ayrı kanıttır; yerel erişim sunucunun erişebildiğini göstermez.

| Kaynak | Merkezi getirme yöntemi | Canlı Cloudflare sonucu | Açık iş |
| --- | --- | --- | --- |
| Kariyer Kapısı | Public `ilan/GetIseAlimPage` JSON; başarısızsa resmî `/RSS`. Ayrıntı: `ilan/GetIlanPreviewPublic` ve `altilan/GetAltIlanInfoByIlanIdPublic` POST | RSS üzerinden20 gerçek ilan/40 immutable değişiklik. Ayrıntı API'si HTTP522; kaynak notu eksik ayrıntıyı belirtir | Kaynak ayrıntısına gerçek Worker erişimi, kullanım şartları, yeterli belge üzerinden model değerlendirmesi |
| Kamu İlanları SBB | `https://kamuilan.sbb.gov.tr/` GET WebForms token'ları + POST yıl; parser `parseSbbList` | Erişim engeli; `blocked` raporlanır. Kaynak başarıyla toplanmış kabul edilmez | Worker erişimi ve resmî belge/PDF okuyucu, kullanım şartları |
| İŞKUR | Merkezi adaptör etkin değil; kayıtlı engel açık gösterilir | `blocked`; üretim kataloğuna veri sağlamaz | İzinli herkese açık veri erişimi; oturum/CAPTCHA/WAF aşılmaz |
| ilan.gov.tr | Merkezi adaptör etkin değil; kayıtlı engel açık gösterilir | `blocked`; üretim kataloğuna veri sağlamaz | İzinli herkese açık veri erişimi; engel aşılmaz |
| Resmî Gazete | Kapsam dışı; adaptör kaldırıldı | Yeni veri toplanmaz | Eski cihaz cache'i görülürse geçiş/retention kuralları uygulanır |
| Belediyelerin ayrı siteleri | Ayrı kaynak adaptörü yok | Veri sağlanmış kabul edilmez | Kullanıcı kapsamı/kaynak sözleşmesi olmadan yeni scraper eklenmez |

## Zamanlama ve güvenlik

- Kaynak liste kontrolü30dk; tek kalıcı batch ve lease. Her source invocation
  en çok4 ilanı işler; üç-slot Cron'da source/AI, matching, send ayrı çalışır.
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

Telefonun eski fetch/Workmanager yolları yalnız pilot tamamlanmadığı için
geçiş kodunda durur; hedef30dk merkezi sunucu çekimidir. Kodun hâlâ çalışması
hedef mimari kabul edilmez. Kaldırma koşulları `.project-brain/tasks/PB-019.md`.

Önceki Dart fixture corpus sonuçları gerçek Workers AI doğruluk ölçümü
sayılmaz. Kaynak alıntısı olmayan koşul belirsizdir; AI alanlarının precision
kapısı kapalıdır. Free modelden en az50 etiketli örnek/kaynak, recall/precision,
neuron ve CPU ölçümü hâlâ yapılmalıdır. Kullanıcı profilleri modele gönderilmez.
