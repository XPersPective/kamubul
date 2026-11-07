# iOS yayını

7 Kasım 2026 geri okuması: iOS 1.2.4 (107) Ready for Distribution; Android 1.2.4 (19) Play üretiminde. Yeni reklam/Pro adayının sandbox ve mağaza beyanı kabulü tamamlanmadı; gönderilmez.

- App Store Connect uygulama numarası 6826592263; bundle ID com.crazypenguin.kamubul; Team 53X3279WA3. Yalnız iPhone, ücretsiz, yalnız Türkiye.
- iOS yerel köprüleri (`ios/Runner/AppDelegate.swift`): takvim düzenleyicisi (EventKit), son başvuru hatırlatmaları (UNUserNotificationCenter, Android sözleşmesiyle aynı), deneme süresi kimlik karması, sunucu bildirimi anahtarı (Keychain).
- Sunucu bildirimi: Firebase iOS uygulaması (1:1003012781397:ios:b1e2551cf6ba52d6ae2bdc), push yeteneği ve `Runner.entitlements`. **Eksik:** APNs anahtarı Firebase'e yüklenmeden iOS bildirimleri ulaşmaz.
- Reklam ve Pro iOS'ta mağaza hazırlığına bağlı (`lib/store_features.dart`): reklam `ADMOB_APP_ID_IOS` ve dört birim verilince, Pro `IOS_PRO=true` ile açılır. Paid Apps/banka/vergi Active; ürün `kamubul_pro_monthly` READY_TO_SUBMIT. AdMob kaydı doğru App Store ID'sine bağlı fakat incelemede/sınırlı sunumda.
- Derleme/yükleme: `.github/workflows/ios-release.yml`; mevcut ayarlar `IOS_DART_DEFINES`, beş iOS reklam kimliği ayrı `IOS_ADMOB_DEFINES` secret'ından birleşir. Açılış kontrolü: `ios-launch.yml`. İnceleme/mağaza yüklemesi için ayrıca `release_acceptance=true` gerekir; sırf test geçmesi sandbox veya metadata kabulünün yerine geçmez.
- Görseller: `ios-screenshots.yml` gerçek uygulamada 7 sahne çeker (Asistan yanıtı dahil); `tool/brand/ios_store_frames.py` Play araştırma setiyle aynı sıra ve başlıklarla çerçeveler.
- App Privacy: Cihaz kimliği ve Diğer kullanıcı içeriği; uygulama işlevi, kişiyle ilişkilendirilmez, takip yok.

## Yeni adayın güvenlik sınırları

- `tool/ios/ads_config.py`: debug/profile/simülatör/STORE_CAPTURE/ADMOB_TEST_MODE derlemelerinde Google test birimleri zorunludur. Üretim kimlikleri repoda tutulmaz. Sürümde kısmi/karışık birim ayarı reddedilir; sırsız sürüm önceki gibi reklamsızdır.
- Xcode Flutter aşaması test kimliklerini Dart'a verir; Thin Binary aşaması **derlenmiş** Info.plist'i aynı uygulama kimliğiyle, son kod imzasından önce eşler. IPA hattı arşiv plist'ini ve kod imzasını geri doğrular.
- Yerel `ad_consent.dart`: UMP güncelleme/form/istek izni tamamlanmadan ATT/SDK başlamaz; hata ve zaman aşımı reklamsız kalır. Ayarlar'da reklam gizlilik tercihleri giriş noktası vardır. ATT reddi uygulamayı kilitlemez.
- Yerel StoreKit köprüsü yalnız Apple'ın doğruladığı, süresi geçmemiş ve iptal edilmemiş aylık aboneliği kabul eder. Tanınmayan/başarısız doğrulama Pro açmaz ve işlemi bitirmez; çevrimdışı denetim mevcut önbelleği korur. Android mağaza bağdaştırıcısı değişmez.
- Bu yerel doğrulama, Worker'ın istemciden gelen `tier=pro` iddiasını doğrulamış sayılmaz. Sunucu mağaza yetkisi PB-038 ve gerçek Apple sandbox işlemleri açık yayın engelidir.
- Yayındaki sürümün reklam/IAP yok beyanı korunur. Reklamlı/abonelikli sürüm gönderilmeden Google SDK veri açıklamalarına göre App Privacy, ATT takibi, reklam yaş beyanı, satın alma geçmişi ve açıklama/inceleme notları güncellenip geri okunmalıdır. Mevcut beyan yeni adayı kapsamaz.
- İmzalı fakat yüklemesiz CI ve tüm kabul sonuçları PB-044 kaydındadır. Windows üzerinde gerçek iOS sandbox/ATT akışı gözlemlendiği iddia edilmez.
