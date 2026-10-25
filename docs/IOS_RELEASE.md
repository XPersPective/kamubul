# iOS yayını

25 Ekim 2026: KamuBul iOS 1.2.4 (build 107) App Store incelemesine gönderildi (WAITING_FOR_REVIEW); onaydan sonra otomatik yayınlanır. Android 1.2.4 (19) Play üretiminde.

- App Store Connect uygulama numarası 6826592263; bundle ID com.crazypenguin.kamubul; Team 53X3279WA3. Yalnız iPhone, ücretsiz, yalnız Türkiye.
- iOS yerel köprüleri (`ios/Runner/AppDelegate.swift`): takvim düzenleyicisi (EventKit), son başvuru hatırlatmaları (UNUserNotificationCenter, Android sözleşmesiyle aynı), deneme süresi kimlik karması, sunucu bildirimi anahtarı (Keychain).
- Sunucu bildirimi: Firebase iOS uygulaması (1:1003012781397:ios:b1e2551cf6ba52d6ae2bdc), push yeteneği ve `Runner.entitlements`. **Eksik:** APNs anahtarı Firebase'e yüklenmeden iOS bildirimleri ulaşmaz.
- Reklam ve Pro iOS'ta mağaza hazırlığına bağlı (`lib/store_features.dart`): reklam `ADMOB_APP_ID_IOS` (ve iOS reklam birimleri) verilince, Pro `IOS_PRO=true` ve App Store abonelik ürünü satışa hazır olunca açılır. **Eksik:** Paid Apps sözleşmesi (banka/vergi), AdMob iOS uygulaması.
- Derleme/yükleme: `.github/workflows/ios-release.yml`; ayarlar `IOS_DART_DEFINES` secret'ından. Açılış kontrolü: `ios-launch.yml`.
- Görseller: `ios-screenshots.yml` gerçek uygulamada 7 sahne çeker (Asistan yanıtı dahil); `tool/brand/ios_store_frames.py` Play araştırma setiyle aynı sıra ve başlıklarla çerçeveler.
- App Privacy: Cihaz kimliği ve Diğer kullanıcı içeriği; uygulama işlevi, kişiyle ilişkilendirilmez, takip yok.
