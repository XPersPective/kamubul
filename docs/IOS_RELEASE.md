# iOS yayını

24 Ekim 2026: KamuBul iOS 1.2.3 (build 106) App Store incelemesine gönderildi (WAITING_FOR_REVIEW). Onaydan sonra otomatik yayınlanır.

- App Store Connect uygulama numarası: 6826592263; bundle ID com.crazypenguin.kamubul; Team 53X3279WA3.
- Yalnız iPhone, ücretsiz, yalnız Türkiye. iOS sürümünde reklam ve abonelik yok (lib/main.dart, lib/home_page.dart).
- Derleme ve yükleme: `.github/workflows/ios-release.yml` (imzalı IPA, App Store Connect API anahtarı GitHub Secrets'ta).
- Ekran görüntüleri: `.github/workflows/ios-screenshots.yml` gerçek uygulamayı simülatörde çeker; `tool/brand/ios_store_frames.py` çerçeveler.
- Açılış kontrolü: `.github/workflows/ios-launch.yml`.
- App Privacy: Cihaz kimliği (Asistan günlük sınırı için rastgele kurulum kimliği), uygulama işlevi, kişiyle ilişkilendirilmez, takip yok.
- iOS'ta gizlenenler: takvime ekle (köprü yok), sunucu bildirimi (Firebase iOS ayarı yok).
