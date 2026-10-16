# KamuBul — araştırma sonrası mağaza içerik sözleşmesi

16.10.2026, **LOCAL_DRAFT**. Bu metinler code17'nin doğrulanmış ürün kapsamını temel alır. Henüz gönderilmedi. [Strateji](STRATEGY.md), [kanıtlar](RESEARCH_2026-10-16.md). 15Ekim adayın API kaydı ile16Ekim public eski seti aynı sayma. Metin değişimi public görsel düzeltmesinin etkisini A/B testine karıştırmamalı.

## Ana listeleme

<!-- Title -->
KamuBul - Kamu İş İlanları
<!-- /Title -->

Başlık mevcut marka/kategoriyi korur. “Memur alımı” kısa/uzun açıklamada doğal betimleyici yer bulur; başlık/kısa metinde KPSS/ÖSYM/kurum adı C-060 nedeniyle yok. Başlık değişikliği Console açıklama deneyi değildir.

Karakter kontrolü (16 Ekim): başlık26/30, ShortA76/80, ShortB67/80, Full3240/4000; akademik26/30 ve73/80, belediye27/30 ve71/80. Sonraki metin değişikliğinde yeniden ölçülür.

### Short A — kategori ihtiyacı + açıklama faydası

<!-- ShortA -->
Memur alımı ve kamu iş ilanları; şartları Asistan ile madde madde inceleyin.
<!-- /ShortA -->

### Short B — ilan bulma + kişisel kayıt

<!-- ShortB -->
Kamu ilanını bulun, şartlarını Asistan’a sorun; aramanızı kaydedin.
<!-- /ShortB -->

A/B hipotezi: A kategori niyetini açıklar, B kullanıcı iş sırasını açıklar. Arama hacmi veya dönüşüm kazananı bilinmiyor. İki varyantı peş peşe güncellemek kontrollü A/B deneyi değildir.

### Full — tek ortak aday

<!-- Full -->
KamuBul ile memur alımı, kamu işçi alımı, sözleşmeli personel ve belediye ilanlarını inceleyin. Şehir ve eğitim gibi kriterlerle aramanızı daraltın; seçtiğiniz ilanın şartlarını KamuBul Asistan’a sorun.

KamuBul bağımsız bir uygulamadır; herhangi bir kamu kurumu, bakanlık veya ÖSYM ile bağlantılı değildir ve resmî devlet uygulaması değildir. Başvurudan önce güncel ve bağlayıcı ilan metnini kurumun resmî sayfasından kontrol edin. KamuBul sizin adınıza başvuru göndermez.

İlanı bulun, şartlarını anlayın
• Kurum veya meslek arayın; şehir, eğitim, yaş, KPSS puan türü ve puanı gibi kriterleri kullanın.
• Desteklenen kaynaklardaki memur, sözleşmeli personel, kamu işçisi, belediye ve akademik kadro ilanlarını takip edin.
• Kontenjanı, varsa kadroları, başvuru tarihini ve metinden çıkarılan koşulları birlikte inceleyin.
• Eksik veya doğrulanamayan koşullar kesin uygunluk olarak gösterilmez. Kriterle eşleşme, bütün başvuru şartlarını sağladığınız anlamına gelmez.

“Bu ilan bana uygun mu?” diye sorun
Seçili ilanın metni hazırsa Asistan’a yaş, öğrenim veya puan şartını sorun. Örneğin: “Lisans mezunuyum, 28 yaşındayım. Bu ilanın yaş ve eğitim şartları ne anlama geliyor?” Asistan koşulları açıklamaya ve verdiğiniz bilgileri metinle karşılaştırmaya yardımcı olur. Yapay zekâ yanıtları hata içerebilir; kesin başvuru uygunluğu veya işe yerleşme garantisi vermez.

İlgilendiğiniz ilanlara geri dönün
Aramalarınızı ve ilanları kaydedin; kayıtlı metinleri çevrimdışı açın. Bildirim tercihlerinizi kayıtlı aramalarınız için ayarlayın. Bildirimler cihaz iznine, bağlantıya ve sistem kısıtlarına bağlıdır. İlanın son başvuru tarihini ve kalan gün bilgisini görün; tahmini tarihler kesin son gün değildir.

Uzun metinleri daha rahat okuyun
Açık veya koyu temayı seçin, yazı boyutunu ayarlayın. Kadroları ayrı inceleyin; resmî ilan ve başvuru sayfasına bağlantıdan geçin. Kaynak erişiminde kesinti veya metin eksikliği olabilir; bütün ilanların eksiksiz kapsandığı garanti edilmez.

Ücretsiz kullanım ve isteğe bağlı Pro
Hesap açmadan başlayın. Temel ilan erişimi ve filtreler ücretsizdir. İlk 7 gün reklam gösterilmez; bu dönem kendiliğinden ücretli abonelik başlatmaz. Sonrasında ücretsiz kullanımda banner ve seyrek tam ekran reklamlar olabilir. Ücretsiz Asistan sınırı günde 10 sorudur.

KamuBul Pro aylık aboneliği reklamları kaldırır ve Asistan sınırını günde 50 soruya çıkarır. Abonelik aylık otomatik yenilenir. Güncel fiyat ve koşullar satın almadan önce Google Play’de gösterilir; aboneliğinizi Google Play > Abonelikler bölümünden yönetebilir ve iptal edebilirsiniz.

Kaynaklar ve gizlilik
İlanlar desteklenen resmî kaynaklardan derlenir: https://kariyerkapisi.gov.tr/isealim, https://www.ilan.gov.tr/, https://esube.iskur.gov.tr/ ve https://kamuilan.sbb.gov.tr/. Her kaynağın kapsamı ve erişimi farklı olabilir. Nihai bilgi ilanın resmî metnidir.

Kaydedilen ilan ve aramalar cihazda tutulur; bildirim açıldığında hizmet için gerekli kriterler sunucuya iletilir. Asistan’a gönderdiğiniz mesaj ve gerekli ilan bağlamı yanıt üretmek için işlenir. Kimlik veya başvuru belgesi paylaşmayın. Ayrıntılar: https://kamubul-api.devx8585.workers.dev/privacy/

KamuBul GPL-3.0 lisanslı açık kaynaklıdır: https://github.com/XPersPective/kamubul
<!-- /Full -->

## Özel listeleme kısa adayları

İki özel sayfa aynı uygulamadır; arama kelimesi hedefleme/hesap uygunluğu Console'da doğrulanır. Tam açıklamada ana adayın kaynak/ücretsiz/Pro/AI uyarıları korunur. Akademik ve belediye ekranları gerçekten o niyete ait ilan göstermeli; genel örneğe akademik etiketi ekleme. Mevcut `docs/CUSTOM_LISTING_DRAFTS.md` tam metinleriyle birleştirilecek; kör yeniden gönderme yok.

<!-- AcademicTitle -->
KamuBul - Akademik İlanlar
<!-- /AcademicTitle -->
<!-- AcademicShort -->
Akademik kadroları bulun; ilan şartlarını Asistan ile birlikte inceleyin.
<!-- /AcademicShort -->
<!-- MunicipalityTitle -->
KamuBul - Belediye İlanları
<!-- /MunicipalityTitle -->
<!-- MunicipalityShort -->
Belediye ilanlarını şehre göre bulun; şartlarını Asistan ile inceleyin.
<!-- /MunicipalityShort -->

## Yedi görsel: üretim brief'i

Tüm dosyalar gerçek yayımlanmış uygulamadan;1080×1920, opakPNG/JPEG. Başlık/alt başlık toplam alanı≤%20; düğme/çıktı kesilmez, tek sahnede tek fayda. Pro/abonelik/satın al/deneme rozetini gösteren kadraj kullanılmaz. Geçmiş tarihli ilanı geleceğe boyayarak değiştirme; gerçek yeni örnek yakala veya tarih merkezli olmayan uygun kadraj seç. Bu brief'i okumak yeni görsel üretildiği anlamına gelmez.

| Sıra | Kısa başlık | Gerçek ekran / kabul şartı | Altmetin adayı |
|---|---|---|---|
| 1 | Kamu ilanlarını bulun | Açık ilan listesi, anlaşılır arama ve şehir; ilk kartın başlığı/alanı okunur. Yenileme tarihi ve ilan sayısı sahte güncellenmez; deneme rozeti kadraj dışında. | KamuBul ilan listesinde kurum veya meslek araması ve şehir süzgeci. |
| 2 | Bu şart ne anlama geliyor? | Seçili gerçek ilan başlığı + kısa soruya madde madde doğru Asistan yanıtı. Kaynak koşulu kanıtlı, unknown gizlenmiyor; hata uyarısı kalır. Güncel100/30 veya Pro ekranı yok. | Seçili ilanın yaş ve eğitim şartlarını açıklayan Asistan; bilinmeyen koşul ayrıca belirtiliyor. |
| 3 | Kadroları ayrı inceleyin | Aynı ilanın iki gerçek pozisyonu; şart/kontenjan ayrımı. Başlık/yer alanı tekrar etmiyor; henüz code17'de olmayan SA-017 filtre chip'i yok. | Aynı ilandaki farklı kadroların koşulları ayrı kartlarda gösteriliyor. |
| 4 | Aramanız size göre olsun | Şehir/eğitim/puan formunun sade, anlamlı bölümü; kişiye ait gerçek veri yok. Uygunluğu garanti eden rozet veya hayali sonuç sayısı yok. | Şehir, öğrenim ve puan kriterleriyle kayıtlı arama hazırlama ekranı. |
| 5 | Kaydedin, yeniden okuyun | Kayıtlı ilan ve gerçek çevrimdışı okunabilir metin; temiz okunur kadraj. Sunucu yokken tüm katalog erişimi vaat edilmez. | Kaydedilen ilan metni çevrimdışı okunabiliyor. |
| 6 | Başvuru tarihini görün | Gerçek kesin gün/tahmin ayrımı ve varsa kalan gün; geçmiş tarihli örnek yok. Otomatik hatırlatıcı/takvim yayınlanmadan gösterilmez. | İlanın son başvuru tarihi ve varsa tahmini tarih açıklaması. |
| 7 | Rahat okuyun | Aynı gerçek ilan açık/koyu temada veya yazı boyutu ayarında; sağ/sol yazı küçülerek okunmaz hale gelmez. | Açık ve koyu tema ile ayarlanabilen yazı boyutu. |

Kontrol ilk sırası1→2; RA-1 varyantı2→1; diğerleri aynı. Güvenlik/politika düzeltmesi olan eski Pro görselini kontrol olarak tutma. Her görsele kısa altmetin girilebiliyorsa Console'da ekle. Küçük Play kartında başlığı gören kullanıcı ne yapacağını söyleyebilmeli; bunu beş kullanıcıyla test etmek plan, yapılmış görüşme değil.

## Yayın öncesi içerik kapısı

- Başlık/kısa/full karakter sınırları; Türkçe yazım; bağımsızlık/kaynaklar/AI sınırı/ücretsiz ve aylık yenileme açık.
- Yayınlanmış sürümün gerçek özellikleri; güncel10/50 kota; Pro güvenli hak doğrulaması ve gerçek reklam/FCM kabulü teknik görevlerde ayrıca kapanır.
- Yedi yeni dosyanın yerel+remote sırası/hash'i aynı; yanlış public8 eski100/30 kalmamış. Eski adayın bekleyen incelemesini okumadan tekrar gönderme.
- Metin/görsel/destek/privacy/website aynı kapsamı anlatıyor; yayın tarihi ve review state kaydı var. Public görünüm ayrı gözlenmiş.
- Bu dosya otomatik yayın, takip veya deney başlatmaz. Metinler mevcut kanıta dayalı adaydır; Google onayı veya sıralama kazanımı değildir.
