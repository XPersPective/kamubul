# Kaynak kayıt defteri

Yalnızca resmî kaynaklar (C-001). Her satır, hedefteki "Source registry"
gereği getirme yöntemi, ayrıştırıcı, hız sınırı, atıf ve son sonucu
kayıt altına alır; bilinmeyenler "kayıt yok"tur, uydurulmaz. Son doğrulama:
2026-09-28.

| Kaynak | Getirme yöntemi | Ayrıştırıcı | Hız sınırı (öz-kısıt) | Atıf | Son sonuç | robots / coğrafya | Kullanım şartları |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Kariyer Kapısı (`kariyerkapisi.gov.tr`) | Herkese açık `GetIseAlimPage` JSON liste çağrısı; yayın tarihi resmî RSS'den zenginleştirilir; liste düşerse RSS'ye düşüş | `lib/listings/kariyer_feed.dart`, ayrıntı: `kariyer_detail.dart` | Yenileme başına tek liste çağrısı; planlı kontrol 12 saatte bir (Workmanager), manuel yenileme kullanıcı eliyle | Her kartta kaynak adı + resmî ilan URL'i | 2026-09-28 başarılı: 26 kayıtlı ilan; iki "Yurt Dışı Eğitim" duyurusu iş ilanı olmadığı için ayıklandı; 5 gelecek tarihli kayıt yalnızca yayın gününde listelenir | robots.txt incelemesi: kayıt yok; coğrafi kısıt: kayıt yok | TD-002: yayın öncesi şartlar doğrulanacak |
| Kamu İlanları SBB (`kamuilan.sbb.gov.tr`) | Sunucu taraflı WebForms liste (GET token, POST yıl); resmî ayrıntı PDF | `lib/listings/sbb_feed.dart` | Yenileme başına tek liste akışı; planlı kontrol 12 saatte bir | Her kartta kaynak adı + resmî belge URL'i | 2026-09-28 başarılı: kurum, başlık, kategori, kontenjan ve tarih aralığı alanları geliyor; resmî ayrıntı PDF olarak açılıyor | TR dışı IP'leri engelleyebilir (2026-09-27 TD-002 notu); robots.txt incelemesi: kayıt yok | TD-002: yayın öncesi şartlar doğrulanacak |
| Resmî Gazete (`resmigazete.gov.tr`) | Günlük dizin + arşiv `/eskiler/YYYY/MM/YYYYMMDD.htm` (legacy markup), windows-1254; TLS için herkese açık CA zinciri paket içinde (`rg_certificates.dart`, doğrulama asla kapatılmaz) | `lib/listings/rg_feed.dart` | Günde tek istek (adaptör notu); planlı kontrol 12 saatte bir | Her kayıtta kaynak adı + resmî gazete URL'i | 2026-09-28: el sıkışma cihazda başarılı; son 7 günde dizinlenen eskiler belgelerinde sıfır "personel al" duyurusu — alım ilanları artık RG gövdesinde görünmüyor; adaptör yeniden belirirse gösterir | robots.txt taramayı yasaklamıyor (2026-09-27 doğrulandı); coğrafi kısıt: kayıt yok | TD-002: yayın öncesi şartlar doğrulanacak |
| İŞKUR (`esube.iskur.gov.tr`) | YOK — WAF oturum akışı; anon istek "Request Rejected — İŞKUR Bilgi İşlem Dairesi Başkanlığı" yanıtı veriyor | yok | — | — | 2026-09-27 başarısız (kanıtlı engel); oturum/CAPTCHA aşma yasak (C-001) | WAF: anon istek reddi | Engel notu geçerli; veri kaynağı değil |
| ilan.gov.tr | YOK — `/api/services/app/Ad/AdsByFilter` doğrudan çağrıda Kong üzerinden 404; oturum akışı tersine mühendisliği yeni kapsam | yok | — | — | 2026-09-27 başarısız (kanıtlı engel) | Oturum/kapı: doğrudan çağrı 404 | Engel notu geçerli; veri kaynağı değil |
| Belediyeler | Yok (kapsam dışı) | — | — | — | — | — | — |

## Notlar

- Planlı aralık, uygulamanın kendi 12 saatlik Workmanager denetimidir;
  kaynak başına ayrı bir ticari hız sınırı sözleşmesi **kayıt yok**tur —
  yayın öncesi (TD-002) her kaynak için kullanım şartları tek tek
  doğrulanacaktır.
- Yarışma/derleyici siteler veri kaynağı değildir (C-001); yalnızca özellik
  araştırması için incelenebilir.
- Yapısal alan (yaş, KPSS, eğitim vb.) çıkarımı yalnızca kaynak cümlesiyle
  yapılır; kanıt yoksa alan "belirtilmemiş" kalır (`extract_conditions.dart`,
  `tool/eval_extraction.dart` ile 55 Kariyer + 55 SBB örneklikte 1.000
  precision/recall).
