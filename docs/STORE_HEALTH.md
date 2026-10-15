# KamuBul mağaza sağlığı

Hazırlık: 15.10.2026. Bu belge ölçüm ve destek rehberidir; Console ölçümlerinin veya sıralama artışının kanıtı değildir. Yetkili Console oturumu yok: mağaza CTR, Vitals, puan/yorum dağılımı ve abonelik dönüşümü **UNKNOWN**. Eksik veri sıfır olarak yazılmaz. SA-011 gerçek baseline ve takip görevidir.

## Haftalık ve aylık kayıt

Her kayıtta gözlem zamanı/saat dilimi, ölçüm başlangıç-bitişi, sürüm, ülke, dil, trafik kaynağı, listeleme kimliği, yeni/geri dönen kullanıcı ayrımı, ham pay/payda ve export/ekran kaynağı saklanır. Türkiye/tr-TR ana cohort'tur; farklı kaynakların oranları doğrudan karşılaştırılmaz. Toplam oran, günlük yüzdelerin ortalamasıyla değil aynı kapsamın toplam pay/paydasından hesaplanır. İki dönemin tanımı değişmişse ayrı seri açılır.

| Sıklık | Metrik | Kaynak ve payda | 15 Ekim durumu / sonraki işlem |
|---|---|---|---|
| Haftalık; aylık 28 günlük kıyas | Unique user Install CTR | Console Store performance > Conversion analysis; aynı filtrede benzersiz Install tıklayanlar / listeleme ziyaretçileri; Console'un tekilleştirme tanımı korunur | UNKNOWN. Ham visitors/clicks, tarih, cohort ve 28 günlük akran ortancası/25./75. yüzdelik kaydedilir |
| Haftalık | Gerçek edinim | Grow users / Statistics / Exports; exporttaki kullanıcı/cihaz tanımı ayrı yazılır | UNKNOWN. Install tıklaması tamamlanmış kurulum sayılmaz |
| Haftalık; sürüm sonrası günlük | Kullanıcı algılı çökme / ANR | Android Vitals; günlük etkin kullanıcılar içinde ilgili sorunu yaşayan kullanıcı payı; sürüm ve cihaz modeli kırılımı | UNKNOWN. Genel eşikler çökme %1,09, ANR %0,47; telefon modeli bazında ikisi %8. Eşiğe yaklaşmada kök neden ve sürüm planı açılır |
| Haftalık | Puan, yeni yorumlar, ilk yanıt süresi | Console Ratings & reviews; dönem yorum sayısı ve yanıtlanan yorum sayısı, yanıt süresi için yanıtlanan cohort | UNKNOWN. Hedef ilk insan yanıtı 24 saat; geç kalanlar ayrı sayılır |
| Haftalık | Asistan teknik hata oranı | Anonim sunucu sayaçları; teknik başarısız tamamlanan istek / aynı dönemdeki geçerli Asistan istekleri; rate limit ayrı | UNKNOWN. Mevcut token örneğinden çıkarılmaz; ölçüm eklenmeden oran raporlanmaz |
| Aylık | Asistan “Bilinmiyor” çıktısı | Etiketli örneklem veya tanımlanmış anonim sayaç; hangi şart/yanıtın sayıldığı ve örneklem büyüklüğü yazılır | UNKNOWN. Eksik kaynak/bilgi nedeniyle dürüst “Bilinmiyor”, teknik hata veya yanlış cevap sayılmaz |
| Haftalık | Kaynak ve ayıklama kapsamı | API health/meta anlık kayıtları; aktif ilan toplamı ve complete/partial/metinsiz sayıları | Aşağıdaki anlık gözlem; doğruluk precision/recall yerine geçmez |
| Haftalık | Bildirim kuyruğu | D1 outbox durum sayıları ve gözlem zamanı; kabul/iptal/bekleyen işler | Anlık 115 accepted / 3 cancelled / 22 pending; accepted cihaz teslimi değildir |
| Aylık | Pro dönüşümü / iptal | Console abonelik raporu; teklif gören, satın alan ve iptal eden cohort'ların kendi tanımlı paydaları | UNKNOWN. 15 Ekim API ürün kaydı: TRY 58,99, P1M aylık; fiyat değiştirilmedi, yıllık plan gözlenmedi |

Google'ın [mağaza performansı açıklaması](https://support.google.com/googleplay/android-developer/answer/9859173?hl=en) Temmuz 2026 geçiş notu ve Haziran başlangıç ifadesi içerir. Yeni seri benzersiz tıklama/CTR'dir; eski edinim CVR serisiyle birleştirilmez. Install, Open ve Pre-register ayrı ölçülür. Tekilleştirme günlük ve boyut bazlıdır; günlük ziyaretçilerin toplamını dönem boyunca tekil kişi sayısı diye adlandırmayın. Akran kıyası aynı filtre/dönemle okunur.

[Android vitals](https://developer.android.com/google/play/vitals) ve [Console Vitals tanımları](https://support.google.com/googleplay/android-developer/answer/9844486) genel ve cihaz bazlı kötü davranış eşiklerini açıklar. Bu eşikler test geçme oranı değildir. Eşik altında kalmak sıralama garantisi vermez; gerçek üretim kullanıcı verisi gerekir. Kaynaklar 15.10.2026 yeniden kontrol edildi.

## 15 Ekim anlık ürün gözlemi

Kaynak: [büyüme denetimi](PLAY_GROWTH_AUDIT.md), `.store-automation/current.md` ve oturumun API/admin readback'i. Kesin gözlem saati bu özetten çıkarılamıyor; yeni kıyasta zaman damgalı export gerekir.

- Health: **212 aktif / 137 complete / 56 partial / 19 metinsiz / 12 AI katkılı**. İlk üç kalite durumunun toplamı 212'dir; AI katkılı 12 ayrı alt kümedir, toplama tekrar eklenmez.
- Meta: ilan.gov erişilebilir; Kariyer ayrıntı hatasında önceki metni koruyor; SBB blocked; İŞKUR HTTP 500 ve başarılı okuma yok. Bütün resmî ilanlar kapsanıyor iddiası yapılmaz.
- Token örneği: ölçülmüş **1 Asistan yanıtı 4099 token**, **6 ayıklama yanıtında ortalama 9041 token**. Bu küçük örnek maliyet, Credits, kullanıcı başı tüketim veya hata oranı değildir; model/cache/istek kapsamı aynı olmadan genellenmez.
- Outbox **115 accepted / 3 cancelled / 22 pending** anlık durumdur. Toplam 140 işin durumu gözlenmiştir; teslim oranı veya günlük gönderim hızı hesaplanmaz. Cihaz teslimi ayrı kanıt ister.
- Metadata ve website alanı API commit/readback ile doğrulandı; Google halka açık onay/yayılım **UNKNOWN / PUBLIC_PENDING**. Deneyler ve custom listing hedefleme/yayın/CTR için authenticated Console gerekir (SA-007/008/009/011). API commit, inceleme onayı sayılmaz.

## Yorumlara 24 saat hedefli yanıt

Her iş günü yeni yorumları gözden geçir; gün/sürüm/konu ve ilk yanıt zamanını özel destek kaydına yaz. Çökme/veri kaybı/yanlış uygunluk iddiasını teknik göreve bağla; küçük ekipte hafta sonu gecikmesini de dürüst kaydet. Sorunu doğrulamadan “düzeltildi” deme. Taslaklar insan kontrolünden sonra, kullanıcı açıkça gönderme yetkisi verirse yayımlanır; bu görev hiçbir yorum göndermedi.

Kamu yorumunda kimlik, telefon, e-posta, satın alma jetonu, başvuru belgesi veya profil isteme. Gerekirse kullanıcıyı isteğe bağlı özel destek kanalına yönlendir; orada da yalnız gerekli anonim ilan bağlantısı/sürüm/cihaz bilgisi alınır. Ödül, ücret, kota artışı karşılığında yorum yok; olumlu puan talebi veya olumsuz yorumu kaldırma baskısı yok. Yanıt hızı destek hedefidir, doğrulanmış sıralama katsayısı değildir.

| Konu | Yayımlanmamış Türkçe yanıt taslağı |
|---|---|
| Olumlu geri bildirim | “KamuBul'un işinize yaramasına sevindik. Deneyiminizi paylaştığınız için teşekkür ederiz. İlan şartlarını başvuru öncesinde resmî kaynaktan kontrol etmeyi sürdürün.” |
| Teknik sorun | “Yaşadığınız sorunu incelemek isteriz. İsterseniz uygulama sürümünü ve sorunun hangi adımda oluştuğunu destek adresimize iletebilirsiniz. Kişisel bilgi veya başvuru belgesi paylaşmanız gerekmez. İnceleme sonucunu doğrulamadan çözüm sözü vermek istemiyoruz.” |
| Sorunlu AI yanıtı | “Asistan yanıtı hatalı veya eksik olabilir; bağlayıcı olan resmî ilandır. Uygun görürseniz ilan bağlantısını ve hatalı görünen koşulu destek kanalında paylaşın. Kimlik, puan belgesi veya kişisel profil göndermeyin; örneği kaynak metniyle karşılaştıracağız.” |
| Eksik kaynak/ilan | “Bazı kaynaklarda erişim kesintisi veya metin eksikliği olabiliyor; tüm ilanların kapsandığını garanti etmiyoruz. İlanı kurumun resmî sayfasından kontrol edin. İsterseniz yalnız resmî ilan bağlantısını destek kanalına iletin; kapsam ve kaynak durumunu inceleyelim.” |

Destek: [e-posta](mailto:devcrazypenguin@gmail.com), [gizlilik](https://kamubul-api.devx8585.workers.dev/privacy/). Yeni kayıt şablonu: `gözlem zamanı | dönem | sürüm/cohort/kaynak | metrik tanımı | pay | payda | sonuç/UNKNOWN | export bağlantısı | takip görevi`.
