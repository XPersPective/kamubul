# Kaynak kayıt defteri

Yalnızca resmî kaynaklar (C-001). Her satır, hedefteki "Source registry"
gereği getirme yöntemi, ayrıştırıcı, hız sınırı, atıf ve son sonucu
kayıt altına alır; bilinmeyenler "kayıt yok"tur, uydurulmaz. Son doğrulama:
2026-09-28.

| Kaynak | Getirme yöntemi | Ayrıştırıcı | Hız sınırı (öz-kısıt) | Atıf | Son sonuç | robots / coğrafya | Kullanım şartları |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Kariyer Kapısı (`kariyerkapisi.gov.tr`) | Herkese açık `GetIseAlimPage` JSON liste çağrısı; yayın tarihi resmî RSS'den zenginleştirilir; liste düşerse RSS'ye düşüş | `lib/listings/kariyer_feed.dart`, ayrıntı: `kariyer_detail.dart` | Yenileme başına tek liste çağrısı; planlı kontrol 12 saatte bir (Workmanager), manuel yenileme kullanıcı eliyle | Her kartta kaynak adı + resmî ilan URL'i | 2026-09-28 başarılı: 26 kayıtlı ilan; iki "Yurt Dışı Eğitim" duyurusu iş ilanı olmadığı için ayıklandı; 5 gelecek tarihli kayıt yalnızca yayın gününde listelenir | robots.txt incelemesi: kayıt yok; coğrafi kısıt: kayıt yok | TD-002: yayın öncesi şartlar doğrulanacak |
| Kamu İlanları SBB (`kamuilan.sbb.gov.tr`) | Sunucu taraflı WebForms liste (GET token, POST yıl); resmî ayrıntı PDF | `lib/listings/sbb_feed.dart` | Yenileme başına tek liste akışı; planlı kontrol 12 saatte bir | Her kartta kaynak adı + resmî belge URL'i | 2026-09-28 başarılı: kurum, başlık, kategori, kontenjan ve tarih aralığı alanları geliyor; resmî ayrıntı PDF olarak açılıyor | TR dışı IP'leri engelleyebilir (2026-09-27 TD-002 notu); robots.txt incelemesi: kayıt yok | TD-002: yayın öncesi şartlar doğrulanacak |
| Resmî Gazete (`resmigazete.gov.tr`) | KAPSAM DIŞI (2026-09-29): son günlerde personel alım ilanı vermedi; adaptör ve sertifika zinciri sunucudan ve uygulamadan kaldırıldı | — | — | — | Eski önbellek satırları budanana kadar görünebilir | — | — |
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

## Sunucu çekimi (2026-09-29 tasarımı)

- Sunucu (`backend/`) Kariyer Kapısı ve SBB'yi günde ~3 kez (08:00, 13:00, 18:00 TR) okur; kaynak başına istek sayısı ve gecikmesi ayarlıdır (`REQUEST_DELAY_MS`, `DETAIL_FETCH_LIMIT`). İŞKUR ve ilan.gov.tr için `PROBE_SOURCES=1` yalnızca herkese açık ana sayfaya çalışma başına **tek anonim GET** atar ve sonucu `sources.json` durumuna (`blocked` / `disabled` = erişilebilir ama ayrıştırıcı yok / `failed`) yazar; oturum, CAPTCHA ya da WAF aşılmaz.
- **Sunucu IP'sinden gerçek okuma sonucu: kayıt yok.** Sunucu henüz Google Cloud'da çalıştırılmadı. Bu geliştirme oturumunun çıkış vekili tüm resmî adresleri 403 ile reddetti; bu sonuç kaynakların davranışı hakkında hiçbir şey söylemez ve kayda alınmamıştır.
- Google Cloud'da Türkiye bölgesi yoktur (planlı 2028–2029). SBB yurt dışı IP'leri reddederse sunucu SBB'yi `failed`/`blocked` raporlar ve uygulama yalnızca SBB'yi cihazdan çeker.
- Yayın öncesi (TD-002): ilanların sunucudan yeniden yayınlanması için her kaynağın kullanım şartları doğrulanacaktır.
