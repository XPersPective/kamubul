# Uluslararası örüntüler ve tekrarlı kalite kabulü

16.10.2026. Kullanıcı: “ilk, en iyi ve en çok indirilen uygulama ... mükemmel ... uluslararası dillerde de araştırma ... dar kapsamlı düşünme, geniş düşün.” Araştırma kapsamı ülke/dille sınırlanmaz; uygulama ve mağaza yalnız Türkçe/TR. Bu belge ilk genişleme turudur, küresel pazar araştırmasının tamamı değildir. Kaynakları farklı dillerde okumak tek başına bağımsız kanıt sayısını artırmaz.

## Resmî kaynaklarda görülen örüntüler

| Kaynak / dil | Belgelenen davranış | KamuBul için karar / kuyruğu |
|---|---|---|
| [LinkedIn iş uyarıları](https://www.linkedin.com/help/linkedin/answer/a511279/job-alerts-on-linkedin) / İngilizce | Aramadan uyarı oluşturma, günlük/haftalık sıklık, e-posta/uygulama kanalı; en fazla20 uyarı. | Kayıtlı arama → bildirim döngüsünün anlaşılır olması önemli. Mevcut FCM ve tercihler korunarak SA-005 cihaz/izin/tekrar/geri dönüş kabulü; rakibin sayısal sınırı veya e-postası aynen kopyalanmaz. |
| [LinkedIn koşul eşleşmesi](https://www.linkedin.com/help/linkedin/answer/a7120158) / İngilizce | Profil/özgeçmiş ile gerekli/tercih edilen koşulların açıklaması; Premium'da ek eşleşme seviyesi. | Koşul nedeninin anlaşılması, tek skor etiketinden daha somut karşılaştırma alanı. SA-004 kanıtlı alan doğruluğu, SA-017 kadro ayrımı ve SA-024 yanlış AI yanıtını bildirme. Kamu şartı sosyal profil tahminiyle karıştırılmaz. |
| [USAJOBS uyarıları](https://help.usajobs.gov/how-to/search/job-alerts) / İngilizce | Adlandırılan filtreli arama, günlük/haftalık/aylık/hiç,10 uyarı ve güncellenmezse1 yıl ömür. | Aramayı tanıma/düzenleme/durdurma, kullanıcı kontrolü ve yaşam döngüsü doğrulanmalı. KamuBul'a süre/sayı limiti kanıtsız eklenmez; mevcut120gün saklama kuralıyla ürün açıklaması tutarlı tutulur. |
| [USAJOBS başvuru görünümü](https://help.usajobs.gov/how-to/application/view) / İngilizce | Aktif/arşiv, kapanış tarihine göre sıralama, kaydedilen/başlanan ilanın kapanmasına3gün kala isteğe bağlı e-posta. | Son tarih hatırlatması SA-015 ve kişisel durum/not SA-018 için somut örüntü. Bizde henüz yayımlanmadığı için mağazada gösterilmez. |
| [USAJOBS iş ve başvuru durumu](https://help.usajobs.gov/how-to/application/status) / İngilizce | İlanın işe alım durumu ile kişinin başvuru durumu ayrı; güncel başvuru durumu kurum sistemine bağlantıyla açılır. | SA-018 yerel “başvurdum” kaydı kurumun kabul/işe alım sonucu değildir. Resmî veri entegrasyonu olmadan sunucu kendiliğinden başvuru sonucu üretmez. |
| [Indeed uyarı rehberi](https://www.indeed.com/career-advice/finding-a-job/how-indeed-job-alerts-help-job-seekers) / İngilizce | Tercihlere göre uyarıyı daraltma/değiştirme; daha ilgili fırsat ve zamanlama önerisi. | Bildirim adedi yerine alaka ve kullanıcı kontrolünü değerlendirme hipotezi; indirme/işe alınma artışının KamuBul için kanıtı değil. |
| [Google A/B deneyleri](https://support.google.com/googleplay/android-developer/answer/12053285?hl=ja) / Japonca | Metin/görsel varyantı, yerelleştirilmiş deney kapsamı, hedef metriğe göre sonuç. | Mevcut SA-007/008 doğrulamasıyla uyumlu; çeviri ayrı sıralama hilesi değil. Eksik örneklem için keyfi süre sonunda kazanan seçilmez. |
| [Android kalite](https://developer.android.com/quality), [çekirdek değer](https://developer.android.com/quality/core-value) / İngilizce | Kullanıcı değeri, UX, teknik kalite, güvenlik; pazarlama varlığı ve kullanıcı metrikleri birlikte değerlendirilir. Edinim tek başına çekirdek değer ölçüsü değildir. | “En iyi” hedefi yalnız yükleme sayısına indirgenmez. Kaynak doğruluğu/ilan görevi/geri dönüş/reklam/ödeme/güvenlik, mağaza metni kadar önceliklidir. |

Rakip yardım belgeleri beyan edilen tasarımı gösterir; uygulamalar bu oturumda cihazda test edilmedi. Ücret/ülke erişimi/etkinlik kazanımı bu kaynaklardan çıkarılmaz. Uluslararası rakibin davranışı Türkiye'deki kamu işe alım prosedürünü değiştirmez.

## Kaliteyi sertleştirme döngüsü

1. **Kanıtlı boşluk:** Kullanıcı görevi ve başarısız senaryo yazılır; rapordaki iddia CLAIM/OBSERVED/UNKNOWN olarak ayrılır. “Rakipte var” tek başına yapma nedeni değildir.
2. **Hedefli uygulama:** Mevcut mimariyi kullan; doğru ortak noktayı düzelt. Bir özelliğin yanında veri doğruluğu, izin, çevrimdışı, tekrar, büyük yazı ve geri dönüş senaryolarını kapsa.
3. **Gerçek doğrulama:** Kod/test, görsel/etkileşim, cihaz, sunucu, Play API/public ve gerçek trafik birbirinin yerine geçmez. Görevin Acceptance türüne uygun kanıt gerekir.
4. **Eleştirel inceleme:** İşlev/güvenlik/politika/kullanıcı başarısı/kalıcılık/erişilebilirlik açısından bulguları önem ve yeniden üretim adımıyla kaydet. HIGH/MEDIUM kabulünde uygulayıcıdan bağımsız reviewer gerekir.
5. **Düzelt ve yeniden dene:** Yeni bulgu için kök neden düzeltmesi ve etkilenen kontroller; kanıt bağlandığı içerik değiştiyse tazelenir. Aynı sonucu yeniden çalıştırmak kalite artışı değildir.
6. **Kabul ve yeniden öğrenme:** Açık kritik/yüksek bulgu veya başarısız gerekli kapı varken bitmiş sayma. Yayın sonrası elde tutma/kayıp, görev başarısı, şikâyet ve teknik sağlık yeni kanıt verirse yeni tur açılır. Yetersiz veri UNKNOWN olarak kalır. Süre veya tur sayısı başarı garantisi değildir.

Bu, mevcut kullanıcı tarafından başlatılan çalışmanın yürütme yöntemi; heartbeat/cron veya periyodik takip kurulmaz. Hedef geniştir; sonsuz kontrol tekrarından çok yeni kanıtla en önemli boşluğu kapatmaya çalışılır.

## Rapor → uygulama kapsamı

| Alan | Açık iş / kanıt |
|---|---|
| Türkçe mağaza / doğal anahtar kelimeler / güncel görseller | SA-025/021; ardından SA-011/007/008/009; public/deney sonuçları ayrı. |
| Veri kapsamı / ayıklama / kaynak metni | SA-003/004; örneklem ve alan precision/recall; eksik kaynak açık. |
| Gerçek ilk fayda / kolay kullanım / yaşam döngüsü | SA-005 ve SA-017; cihazda offline/izin/7gün/restore/geri dönüş/FCM. |
| Kişisel takip / son tarih / başvuru notu | SA-015/018; kullanıcı kaydı ile resmî sonuç ayrımı. |
| AI fayda / yanlış yanıt / gizlilik / güvenlik | SA-024/016/004; veri minimizasyonu ve entitlement. |
| Web SEO / dağıtım / kullanıcı araştırması | STRATEGY dağıtım bölümü ve SA-002 kapsam incelemesi; Search Console erişimi/index UNKNOWN. Uygulanacak bağımsız parçaları ayrı executable göreve ayır, eksik işi sessizce tamamlandı sayma. |

Sonraki araştırma turunda Türkiye dışındaki işe alım araçlarının erişilebilir mobil akışları ve kullanıcı şikâyetleri incelenebilir; fiyat/özellik beyanı cihaz gözlemiyle ayrılmalı. Türkçe gerçek kullanıcı görev testleri uluslararası örneklerin yerine geçmez, onları yerel bağlamda sınar.
