# KamuBul: büyüme ve ürün boşlukları

Denetim: 2026-10-15. Kullanıcı hedefi: “storede üst sırada çıkmak” ve “kullanıcının ihtiyacı ve uygulamanın amacına uygun özellikler”. Rakip sayfaları ürün beyanıdır; rakiplerin cihazdaki akışları test edilmedi. Üst sıra veya belirli büyüme yüzdesi vaat edilmez.

## Karar

En güçlü teklif: hesabı zorunlu tutmadan kamu ilanını bul, resmî metni oku, şartların sana nasıl uygulandığını Asistan ile açıkla. Güvenilir kaynak kapsamı ve çalışan son tarih takibi, yeni bir sınav hazırlık modülünden önce gelir. Asistan avantajdır; üç durumlu şart karşılaştırması rakiplerde de bulunduğundan tek başına benzersizlik iddiası yapılmaz.

## Rakip karşılaştırması

| Ürün / kaynak | Doğrulanan teklif | Fiyat ve sınır | KamuBul için çıkarım |
|---|---|---|---|
| [Kamu Kadro — web](https://kamukadro.com/), [Play](https://play.google.com/store/apps/details?id=com.kamukadro.app), [koşullar](https://kamukadro.com/terms) | Profil eşleştirme; kadro bazlı şartlar; kaydetme; bildirim; son tarih uyarısı; takvime ekleme. Eşleşme/kayıt/bildirim için Google hesabı gerekir. | Web/koşullar: ücretsiz, reklamlı; abonelik/IAP yok. | Hesapsız kullanım korunmalı. “Bilinmiyor” çıktısı tek başına rakipsiz değil. Web akademik kadroyu dışlar, Play akademik ilanları listeler: kapsam çelişkili, akademik kapsamda kesin üstünlük iddia edilmez. |
| [Atama Bildirim — web](https://atamabildirim.com/), [Play](https://play.google.com/store/apps/details?id=com.atananben.atama_bildirim_app_final) | Profil filtreleri, yeni ilan ve son tarih bildirimleri. Web ayrıca puan hesaplama, çalışma planı, sınav takvimi, notlar ve CV araçları sunar; bunların mobilde olduğu varsayılmaz. Play 10K+ indirme, 10 Ekim 2026 güncelleme. | Web: indirme/bildirim ücretsiz, gelişmiş analiz Premium. Android tutarı kamuya açık sayfada doğrulanamadı. | Asistan değeri somut örnekle gösterilmeli; sınav araçları, ilan takibi ihtiyacından ayrı kapsamdır. Eski rapordaki geliştirici/güncelleme bilgileri güncel değil. |
| [İŞKUR Mobil — Play](https://play.google.com/store/apps/details?id=tr.gov.iskur.iskurapp&hl=tr) | Resmî uygulama; kamu/özel ilan arama, başvuru, favoriler, CV ve işveren hizmetleri. 5M+ indirme; 11 Ekim 2026 güncelleme. | İndirme ücretsiz görünüyor; abonelik fiyatı listelenmiyor. | Doğrudan başvuru/işveren panelini kopyalamak kapsamı ve sorumluluğu büyütür. KamuBul resmî bağlantıya yönlendirmeyi korumalı. |
| [Kamu Personeli Alımı — Play](https://play.google.com/store/apps/details?id=com.Kamu.Personeli.Alimi&hl=tr) | İlan/haber ve anlık bildirim; 1M+ indirme, görünen 4,7 / 12,4 bin yorum; 9 Eylül 2026. | İndirme ücretsiz; Android abonelik fiyatı doğrulanmadı. | Önceki raporda eksik kalan büyük doğrudan rakip. Haber hacmi yerine koşul doğruluğu ve başvuru takibiyle rekabet et. |
| [Kamu İş Personel Alımı — Play](https://play.google.com/store/apps/details?id=com.kamuiscomtr.app&hl=tr) | Genel ilan/haber/bildirim; reklamlı, 500+ indirme; görünen güncelleme 9 Haziran 2026. | İndirme ücretsiz; ücretli plan doğrulanmadı. | Önceki rapordaki 2023 tarihi güncel kaynakla uyuşmuyor. |
| KamuBul — kaynak kod + yetkili Play API | Kriterler, kayıt, çevrimdışı metin, açık/koyu tema, yazı ölçeği; kullanıcı isteğiyle Asistan. | Play subscriptions HTTP 200: `kamubul_pro_monthly`, `aylik`, ACTIVE, P1M, TR TRY 58,99. Tek dönen plan aylık; yıllık plan gözlenmedi. Kod: ücretsiz 10 / Pro 50 soru/gün, ilk 7 gün reklamsız. | Fiyat değiştirilmedi. Ücretsiz ilan erişimi ile ücretli Asistan/reklamsız fayda açık ayrılmalı. |

Sayısal mağaza değerleri görüntüleme ülkesine/zamana göre değişir. Webde “yok” ifadesi yalnız açıkça söylenen koşullara dayanır; belgede bahsedilmeyen özellik yok sayılmaz. Android fiyatı yerine iOS fiyatı kullanılmaz.

## Google Play: doğrulanan kurallar

- [Keşif ve sıralama](https://support.google.com/googleplay/android-developer/answer/9958766?hl=en): aramada sorguyla alaka; listelerde popülerlik; ayrıca teknik deneyim, kullanıcı geri bildirimi ve bağlam etkili. Tek sabit sıralama formülü yok. CTR'yi izlemek faydalı; yüksek CTR organik birincilik garantisi değildir.
- [Mağaza performansı](https://support.google.com/googleplay/android-developer/answer/9859173?hl=en): Temmuz geçiş notu ve Haziran başlangıç ifadesi aynı belgede bulunur. Yeni rapor benzersiz tıklamaları ve CTR'yi ölçer; gerçekleşen edinimler ayrı yüzeylerdedir. Eski Cloud Storage CSV'leri edinim metriğini korur. Install/Open/Pre-register CTR'leri birbirine karıştırılmaz. Türkiye/tr-TR/aynı trafik kaynağı ve 28 günlük akran karşılaştırması kaydedilir.
- [Deneyler](https://support.google.com/googleplay/android-developer/answer/12053285?hl=en): en çok iki varyant; hedef metrik Console'da seçilir. Önce tek değişken: sekizinci Pro ekranı var/yok. En az tam hafta ve Console güven aralığı; veri yetersizse kazanan ilan edilmez. Kısa açıklama aynı deneyde değiştirilmez.
- [Özel listelemeler](https://support.google.com/googleplay/android-developer/answer/9867158?hl=en): niyete/segmente özel metin ve görsel kullanılabilir; hedefleme seçenekleri hesapta doğrulanır. Önce akademik ve belediye sayfası hazırlanır; bunlar ayrı uygulamalar değildir.
- [Ask Play — Google, 13 Ekim](https://blog.google/products-and-platforms/platforms/google-play/google-play-updates-october-2026/): konuşarak öneri ve uygulama karşılaştırması duyuruldu. Türkiye/Türkçe yayılımı, KamuBul'a özel görünürlük veya açıklama ilk cümlesinin ağırlığı bu kaynaktan çıkarılamaz.
- [Çökme](https://developer.android.com/topic/performance/vitals/crash) / [ANR](https://developer.android.com/topic/performance/vitals/anr): kullanıcı algılı çökme ve ANR keşfedilebilirlikle ilişkilidir. Genel kötü davranış eşikleri %1,09 / %0,47; cihaz bazlı eşikler ayrıca izlenir. Test başarısı gerçek Android Vitals oranının yerine geçmez.
- [Görsel kuralları](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en): gerçek ürünü göster, küçük önizlemede faydayı okunur tut. “En iyi”, sıralama garantisi ve sahte başarı metni kullanma.

## Doğrulanamayan veya düzeltilen iddialar

1. “%2–3 anahtar kelime yoğunluğu” Google kuralı değil; yoğunluk hedefiyle metin şişirilmez. 4000 karakter bir üst sınırdır, doldurma hedefi değildir.
2. “İlk 2–3 ekran her sorguda Gemini” ve “Ask Play alaka skoru” için doğrulanmış evrensel kural bulunmadı. Web sitesi faydalı bir ürün/destek yüzeyidir; sıralama garantisi değildir.
3. 24 saat içinde yorum yanıtı iyi destek hedefidir; yanıt hızının doğrudan sıralama katsayısı olduğu doğrulanmadı. Kullanıcı yanıtı göndermeyi yetkilendirmedikçe cevaplar taslak kalır.
4. İŞKUR tek/asıl rakip değildir: Kamu Kadro ve Atama Bildirim görev açısından daha yakındır. “Bağımsız” uyarısı güven/politika açıklamasıdır, resmî olmanın karşısında otomatik avantaj değildir.
5. Yeni metadata'nın henüz görünmemesi tek başına yayın pipeline arızası kanıtı değildir; bekleyen inceleme veya değişikliğin hiç gönderilmemesi ayrı olasılıklardır. Dosya adlarının farklılığı da farklı görsel kanıtı değildir: hash/içerik karşılaştırılır.
6. en-US ve “ar-TR” önerisi mevcut yalnız Türkiye/Türkçe kararıyla uyuşmaz; yeni locale eklenmedi. Başlık/kısa açıklamada KPSS/ÖSYM geçmiş Google reddi nedeniyle kullanılmaz (C-060).

## Canlı ürün ve test gözlemi

2026-10-15 `/api/v2/health`: 212 aktif kayıt; 137 complete, 56 partial, 19 metinsiz; 12 AI katkılı. `/api/v2/meta`: ilan.gov ok; Kariyer önceki metni koruyan ayrıntı hatası; SBB blocked; İŞKUR HTTP 500 ve başarılı okuma yok. “Bütün kaynaklar eksiksiz” denmez. Kaynak engeli için IP/ülke nedeni veya aşma yöntemi varsayılmaz.

Kod izi: `lib/notifications/alert_service.dart:runAlertCheckOnce` yalnız eşitler; core `deadlineReminder` ve `markReminded` runtime çağrısına sahip değil. Eski Workmanager işi iptal edilir. Dolayısıyla mevcut reklam metnindeki kaydedilen ilan hatırlatması uçtan uca doğrulanmış bir özellik değildir.

`workers/src/assistant.js` Pro kotasını istemcinin `tier` iddiasıyla seçiyor; `lib/data/subscription_check.dart` istemci geri yüklemesi yapıyor. Sunucu Play doğrulaması açık güvenlik işi. Var olan daha geniş kotayı azaltmak ya da istemci abonelik işaretini güvenilir saymak çözüm değildir.

Worker: 294/294 test PASS. Flutter: tek koşum 194/194 PASS; ilk yanlışlıkla çakışan koşumda SQLite kilit hataları görüldü, eşzamanlı koşum sonlandırıldıktan sonra aynı kaynakla tekrar doğrulandı. Bu testler gerçek FCM/ödeme/reklam/mağaza onayı kanıtı değildir.

## Öncelik ve teslim ölçütleri

| Sıra | İş | Neden / bitiş kanıtı |
|---|---|---|
| P1 | Gerçek mağaza adayını kontrol et; Asistan öncelikli metin/görselleri gönder ve tekrar oku (SA-006) | Politikaya uygun başlık, doğru kotalar/kapsam; API gönderimi, Google incelemesi ve halka açık yayını ayrı kaydet. |
| P1 | Son başvuru takibini çalışır yap | Native takvim editörü kullanıcıya kayıt/onay bırakır, yeni izin/veri sunucusu gerektirmez. Otomatik yerel hatırlatma ayrı yaşam döngüsü kabulü ister; yalnız rozet bu açığı kapatmaz. |
| P1 | Pro sunucu doğrulama sözleşmesi | Aktif/iptal/sona erme/geri yükleme/tekrar oynatma vakaları; en az yetkili Play bağlantısı. Mevcut satın alanların hakları korunur. |
| P1 | Metinsiz 19 kayıt ve SBB/İŞKUR kaynak kabulü | Geçerli resmî yanıt ve sayım; hata/engel görünür. Eksik kaynak için pazarlama iddiası genişletilmez. |
| P2 | Başvuru takip durumu ve kullanıcı notu | “İnceleyeceğim / Başvurdum / Sonuç bekliyorum”; yalnız cihazda, resmî başvuru yapıldığı iddia edilmez. Veri migration/silme/backup testleri gerekir. |
| P2 | Çok kadrolu ilanda yalnız uygun kadrolar görünümü | Aynı kadro AND/alternatif OR mantığını yeniden kullan; unknown saklanmaz. Yeni AI çağrısı yok. |
| P2 | Tek değişkenli görsel deneyi, sonra kısa açıklama (SA-007/008) | Aynı trafik/dönem, Console güven aralığı ve install clicks. Sonuç için gerçek trafik gerekir. |
| P2 | Akademik/belediye niyet sayfaları (SA-009), mevcut alan adında landing (SA-010) | Yeni domain satın almadan mevcut ücretsiz host; aynı ürün ve kaynak uyarıları. |
| P2 | Destek/vitals/CTR sağlık kaydı (SA-011) | Gerçek Console baseline; veri yoksa UNKNOWN. Asistan hata oranı ile “bilinmiyor” birbirinden ayrılır: bilinmiyor dürüst çıktı olabilir. |
| P3 | Yıllık planı talep/iptal/veriyle değerlendir | Fiyat değişikliği bu denetimde yapılmaz; 58,99 aylık teyit edildi (SA-012). |

İlk sürüme sınav koçluğu, CV üretimi, işveren ilanı, haber akışı, yeni hesap sistemi veya kişisel AI sıralaması eklenmez: mevcut kullanıcı yolculuğunun başarı olasılığına kıyasla daha büyük kapsam ve veri maliyeti getirir. Yeni dil/ülke dağıtımı kullanıcı kararı gerektirir. Kalıcı hedef, uygun ilanı güvenilir biçimde buldurup başvuru süresini kaçırmamaktır.
