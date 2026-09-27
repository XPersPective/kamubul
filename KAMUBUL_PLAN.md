# KamuBul — ürün ve uygulama planı

**Durum:** Araştırma ve plan; uygulama henüz oluşturulmadı. 27 Eylül 2026.

## 1. Depodaki gerçek durum

`master` şu anda `napp_app_template` içeriyor: `tool/new_app.dart` ile Flutter uygulaması üretme betiği, Android/iOS için ortak ürün standardı, marka görseli ve örnek yapılandırma dosyaları var. `pubspec.yaml`, `lib/`, çalışan ilan toplama kodu, veri tabanı, uygulama ekranları ve otomatik testler yok. `PROJECT_BRAIN.md` de bu depoyu şablon olarak tanımlıyor. Bu plan bir uygulamanın çalıştığı iddiası değildir. Üretime başlamadan önce şablonun uygulamaya dönüştürülmesi ve Project Brain durumunun gerçek koda göre güncellenmesi gerekir.

## 2. Ürün kararı

İlk sürüm, **hesapsız ve cihazda saklanan tercihleri olan bir ilan takipçisi** olmalı. Ana değer: doğrulanmış resmî bağlantı, son başvuru tarihi, kaynak ve ilgili koşulları kolay bulma. İlk bilgi mimarisi: **Tümü / Kamu personeli / Kamu işçisi (İŞKUR) / Belediyeler**; ilan.gov.tr ve Resmî Gazete kaynak filtresidir, ayrı birer iş türü değildir. Belediye ilanı hem personel hem işçi kategorisinde bulunabilir; kategoriler birbirini dışlamaz.

İlk sürümde yalnızca gerçekten erişimi ve yeniden kullanım koşulları doğrulanmış kaynaklardan otomatik veri alınır. Diğer kaynaklar için resmî arama sayfasına bağlantı sunulur ve otomatik kapsama iddiasında bulunulmaz. “Anlık bildirim” ve “günde kesin iki kontrol” vaadi kullanılmaz. Bildirim yalnızca başarılı yenilemede bulunan yeni, ilgili ilana gönderilir.

## 3. Kaynak uygunluğu

| Kaynak | Doğrulanan kamusal işlev | Otomatik kullanım kararı |
| --- | --- | --- |
| [Kariyer Kapısı](https://kariyerkapisi.gov.tr/isealim) | Aktif ilanlar, kurum, tür, il, son tarih ve arama ekranı; kurumlar başvuruyu platformda yürütüyor. [Kurumsal açıklama](https://www.cbiko.gov.tr/projeler/kariyer-kapisi). | Kamuya açık ekran var. Belgelenmiş genel API, toplu veri lisansı ve kararlı ilan bağlantısı **doğrulanmadı**. İlk kaynak adayı; yazılı izin/API veya şart incelemesi ve örnek ilan testi gerekiyor. |
| [İŞKUR](https://esube.iskur.gov.tr/) | Kamu işçisi ilanlarına başvuru resmî internet şubesinde; [kamu ilan rehberi](https://media.iskur.gov.tr/37951/kamu-i-lanlarina-bas-vuru-rehberi-002.pdf) kamu filtresini anlatıyor. | Başvuru için kullanıcıyı İŞKUR'a gönder. Herkese açık, onaylı toplu ilan API'si **doğrulanmadı**; erişim/izin kapısı geçilmeden otomatik tarama vaadi verme. |
| [ilan.gov.tr](https://www.ilan.gov.tr/) | Resmî ilan portalında personel alımı kategorisi var. | Kategori görünürlüğü veri yeniden kullanım izni anlamına gelmez. API, kullanım şartı, ayrıntı ve başvuru URL'si doğrulanmalı. |
| [Resmî Gazete](https://resmigazete.gov.tr/fihrist) | Tarih ve “İlan” alanıyla resmî arama var; [günlük sayı](https://resmigazete.gov.tr/) çeşitli ilanlar içeriyor. | Genel iş ilanı akışı değildir. İlanın gerçek başvuru yeri ayrıca tespit edilmeli. API/yeniden kullanım izni doğrulanmadan toplu çekme açılmamalı. |
| Belediye ve kurum siteleri | Kuruma göre farklı duyuru sayfaları ve bazen Kariyer Kapısı/İŞKUR başvurusu. | Tek bir belediye API'si varsayma. Kurum bazlı pilot liste, kullanım izni, yayın biçimi ve bozulma izlemesi gerekir. |

**Kaynak kabul kapısı:** kaynak sahibi ve şartları, programatik erişim izni, hız sınırı, veri alanları, benzersiz kimlik, son tarih, başvuru bağlantısı, değişen/silinen ilan davranışı ve üç gerçek ilan üzerinde doğrulama. Giriş veya CAPTCHA aşma yok. Sayfa ayrıştırma yalnızca izinli ve sürdürülebilir kaynakta son seçenek. Kaynak çalışmazsa son başarılı güncelleme zamanı gösterilir; eski bilgi yeniymiş gibi sunulmaz.

## 4. Telefon arka planı ve bildirimler

[Android WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work) periyodik işi en az 15 dakika arayla tanımlar; yürütme saati sistem koşullarına bağlıdır ve gecikebilir. [Apple BGTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate) için istenen tarih yalnızca en erken başlangıçtır, çalışma garantisi değildir. Dolayısıyla günde 1–2 kontrol **hedeflenebilir**, garanti edilemez. Kaynak sayısı ve ağ maliyetine göre daha seyrek periyot seçilir; uygulama açılışı ve elle yenileme güvenilir ana yoldur. Gerçek zamanlı, uygulama kapalıyken garantili uyarı için merkezi izleyici ve push altyapısı gerekir; bu, sunucusuz hedefi değiştirir.

Yenileme akışı: kaynak için koşullu istek/hız sınırı → doğrulama → benzersiz kaynak kimliği veya kanonik URL ile eşleştirme → yerel veritabanına işlem içinde yazma → izlenen kategoride gerçekten yeni ilanı bulma → izin verilmişse yerel bildirim. Ağ hatası mevcut kayıtları silmez. Bildirim kimliği kalıcıdır; tekrar bildirim yok. İzin reddinde uygulama normal çalışır. Süresi dolan ilanlar aktif listeden çıkar; kayıtlı ilanlar erişilebilir arşivde tutulabilir, diğer eski kayıtlar örneğin 30 gün sonra temizlenir. Bu süre ürün varsayımıdır, ölçümle değişebilir.

## 5. Asistan seçenekleri ve öneri

| Seçenek | Değerlendirme |
| --- | --- |
| Yerel kural/filtre | İlk sürüm için önerilir. Meslek, il, eğitim, ilan metninde **açıkça yazan** KPSS ve yaş şartı filtrelenir. Eşleşme “uygun olabilirsiniz” düzeyindedir; başvuru hakkı kararı verilmez. Sunucu ve API maliyeti yok. |
| Cihazda küçük model | Gizlilik avantajı var; Türkçe ilan/PDF koşullarında doğruluk, cihaz kapsamı, boyut ve pil kullanımı gerçek cihazlarla ölçülmeden vaat edilmez. |
| Uygulama içi ücretli API | Soru-cevap için mümkün; gizli fatura anahtarı mobil uygulamada korunamaz. Kendi anahtarıyla merkezi hizmet için sunucu, kota, kötüye kullanım koruması ve ayrı gizlilik tasarımı gerekir. Sunucusuz ilk sürüme uymaz. |
| Kullanıcının API anahtarı | Teknik olarak sunucusuz, ancak kullanıcı deneyimi zayıf ve anahtar saklama/gösterme riski yüksek; ilk sürüme alınmaz. |
| Dış asistana paylaş | Kullanıcı açıkça seçerse ilanın resmî URL'sini sistem paylaşım menüsüyle göndermek mümkündür. Dış uygulamada otomatik sohbet veya sesli mod açılacağını vaat etme. |

Asistan için isim önerisi: **İlan Rehberi** (tercih), **Başvuru Rehberi**, **İş Rehberim**. Başvuru koşullarını açıklayan gelecekteki asistan her yanıtta kaynak ilan paragrafına/bağlantısına dayanmalı; bulunmayan şart için “İlanda belirtilmemiş” demeli. Kullanıcı profili yalnızca cihazda, silinebilir ve dışa aktarılabilir olmalı. Üçüncü taraf modele gönderim ayrı, açık kullanıcı işlemi gerektirir.

Sesli yazdırma sonraki aşamada işletim sistemi desteğiyle denenebilir: [Android konuşma tanıma](https://developer.android.com/reference/android/speech/SpeechRecognizer) cihazda tanımanın kullanılabilirliğini kontrol eder; [iOS Speech](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition) için cihazda tanıma desteği dil/cihaza bağlıdır. Sürekli karşılıklı sesli sohbet ilk sürüm kapsamında değildir.

## 6. 10.000 aylık aktif kullanıcı için maliyet deneyi

Bugünkü [GPT-5.6 Luna metin fiyatı](https://developers.openai.com/api/docs/models/gpt-5.6-luna): 1 milyon giriş tokenı **$0,20**, çıkış tokenı **$1,20**. [gpt-4o-mini-transcribe](https://developers.openai.com/api/docs/pricing) tahmini **$0,003/dakika**. Aşağıdaki rakamlar yalnızca API kullanımıdır; vergi, ödeme, kur, ek araç çağrıları, ağ/işletim, destek ve sunucu maliyetini içermez. Gerçek ilan örnekleriyle token sayısı ölçülmeden bütçe sayılmaz.

| Aylık senaryo | Kullanıcı başı soru | Soru başı giriş/çıkış | Metin hesabı | %20 kullanıcıya soru başı 0,5 dk ses | API toplamı |
| --- | ---: | ---: | ---: | ---: | ---: |
| Düşük | 2 | 1.000 / 200 | 20.000 × (1.000×0,20 + 200×1,20)/1.000.000 = **$8,80** | $6 | **$14,80** |
| Orta | 10 | 2.000 / 400 | 100.000 × (2.000×0,20 + 400×1,20)/1.000.000 = **$88** | $30 | **$118** |
| Yüksek | 50 | 4.000 / 800 | 500.000 × (4.000×0,20 + 800×1,20)/1.000.000 = **$880** | $150 | **$1.030** |

Kullanıcı başı API tutarı sırasıyla yaklaşık **$0,00148 / $0,0118 / $0,103**. Ses hesabı `10.000 × %20 × soru sayısı × 0,5 dk × $0,003` varsayımıyla yapıldı. 10.000 cihaz günde iki kez bir kaynağa bakarsa o kaynağa **20.000 istek/gün** gider; kaynak kapasitesi ve şartları ayrıca belirleyicidir. Reklam geliri doğrulanmış bir fiyat değildir: `gelir = gösterim / 1.000 × gerçekleşen eCPM`. Örneğin ayda toplam 100.000 gösterim ve varsayımsal $0,10 / $1 / $3 eCPM için brüt $10 / $100 / $300 çıkar; doluluk, ülke ve onay bunu değiştirebilir. Ömür boyu Pro'nun net katkısı `satış × mağaza fiyatı × (1 − geçerli mağaza kesintisi) − vergi/iade` ile hesaplanmalı. Tek seferlik gelir sınırsız, devamlı API tüketimini güvenle finanse etmez. Pro için reklamsız kullanım ve gerçekten cihazda çalışan kalıcı özellikler seçilmeli; sınırsız AI vaat edilmemeli.

## 7. Ekranlar ve veri modeli

Akış: kısa ve atlanabilir tanıtım → kategori/il tercihleri → Tümü listesi → filtreler → ilan ayrıntısı → **resmî başvuru sayfasını dış tarayıcıda aç**. Ayrıntıda son kontrol zamanı, kaynak, başvuru bitişi, açıkça belgelenen koşullar, kaydet/paylaş ve “kaynağı görüntüle” bulunur. Ayrı “Kaydedilenler”, bildirim tercihleri, ayarlar, Pro ve Hakkında/lisans/gizlilik ekranları şablon standardıyla uyumlu olur. Büyük yazı, ekran okuyucu, Türkçe/İngilizce ve RTL denetimi kapsamda kalır; 71 dil hedefi ayrı çeviri doğrulama işi olarak planlanır.

Yerel kayıt: `source_id`, `source_item_id`, `canonical_url`, `application_url`, `title`, `issuer`, `categories[]`, `location`, `published_at`, `deadline_at`, `requirements_text`, `requirements_source_url`, `fetched_at`, `last_verified_at`, `status`, `content_hash`. Ayrı tablolar: izlenen kategori/konum, kayıtlı ilan, bildirim geçmişi ve kaynak yenileme durumu. Her alan için bilinmiyor durumu mümkündür; son başvuru tarihi çıkarılamazsa tarih uydurulmaz. Başvuru bağlantısı yalnızca HTTPS ve izinli resmî alan adlarına yönlenir; dış kaynaktan gelen URL doğrulanır. Aynı ilanın birden çok kaynağı varsa kaynak kökeni korunarak tek kartta birleştirme sonraki aşamada ölçülür.

## 8. Sıralı geliştirme işleri

1. **Kaynak kanıtı:** En az bir kaynağın programatik kullanım iznini, erişim yolunu ve üç örnek ilanı doğrula. Kabul: kimlik, tarih, başvuru URL'si ve değişiklik davranışı belgeli; izin belirsizse otomatik kaynak özelliği başlamaz.
2. **Şablonu uygulamaya dönüştür:** `tool/new_app.dart` ile uygulama kimliği/markası oluştur; Project Brain durumunu gerçek kaynak yapısına göre güncelle. Kabul: temiz analiz, test ve Android sürüm derlemesi; sır yok.
3. **Yerel ilan temeli:** sürümlü veritabanı, kaynak kaydı ve güvenli yenileme. Kabul: bozuk yanıt mevcut veriyi silmez; yinelenen ilan oluşmaz; göç testi geçer.
4. **Liste ve başvuru akışı:** kategori, tarih/konum filtresi, ayrıntı ve resmî sayfa açma. Kabul: açık/kapalı/bilinmeyen son tarih net; geçersiz URL açılmaz; erişilebilirlik kontrolü yapılır.
5. **Bildirim ve arka plan:** elle yenileme, uygulama açılışında yenileme, Android/iOS fırsatçı arka plan yenilemesi. Kabul: tekrar bildirim yok; izin reddi ve ağ kesintisi güvenli; cihaz testinde gerçek çalışma kaydı alınır, kesin saat vaadi yok.
6. **Ürün standardı:** tema/dil, gizlilik, Pro satın alma/geri yükleme, reklam politikası, lisanslar ve mağaza metni. Kabul: şablondaki ilgili testler ve sürüm uygulaması doğrulaması geçer; reklam başvuru akışını bölmez.
7. **AI kararı için pilot:** en az 100 çeşitli gerçek ilan ve kullanıcı sorusuyla koşul çıkarma doğruluğu, yanıt dayanağı, gecikme ve gerçek token maliyeti ölçülür. Kabul: açıklanmamış şartı uydurma oranı ve bütçe eşiği ürün sahibi tarafından belirlenir; aksi halde yerel filtre + paylaşım kalır.

## 9. Karar gerektiren sınırlar

- Otomatik kaynak izni alınamazsa ilk sürüm yalnızca resmî sayfalara yönlendiren arama/kaydetme ürünü olabilir. Kapsamı geniş göstermemek gerekir.
- Kesin zamanlı bildirim veya merkezî AI istenirse sunucusuz hedef değişir; ayrıca altyapı, gizlilik, güvenlik ve işletme bütçesi kararı gerekir.
- Gerçek uygulama adı, paket kimliği, ikon ve mağaza hesapları uygulama üretiminden önce belirlenir. Bu planda hiçbir kimlik veya sır uydurulmadı.

## Doğrulama notu

Bu belge kaynakların kamusal ekranlarını ve platform/fiyat belgelerini doğrular; kaynaklardan otomatik veri alma hakkını veya üretimde çalışan ayrıştırıcıyı doğrulamaz. Fiyatlar ve platform kuralları uygulama kararı öncesi yeniden kontrol edilmelidir.
