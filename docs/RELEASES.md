# KamuBul yayın kaydı

Tek kaynak: her yayından sonra bu dosya güncellenir. Ortak sürüm numarası `pubspec.yaml` (`version: x.y.z+build`); Android versionCode = build, iOS build numarası CI'da `100 + run_number`.

## Güncel durum (07.11.2026)

| Platform | Sürüm | Mağaza durumu | Not |
|---|---|---|---|
| Android (Google Play) | 1.2.5 (20) | Üretim kanalı, `completed` | Edit `17496769459339978662`, AAB SHA-256 `f769753a492a62b5896f556448e56c4c05d1e62f4623da90f1e5eb1ddc84e4c3`; Pro fayda metni 50 soru |
| iOS (App Store) | 1.2.4 (build 107) yayında / 1.2.5 (build 112) hazır | `READY_FOR_SALE` / `PREPARE_FOR_SUBMISSION` | 1.2.5 (`e53880c3-e5b5-4428-be98-ed0528919b31`) build `112` bağlı; App Privacy takip/satın alma beyanı ve ilk abonelik seçimi web arayüzünden bekleniyor |
| Worker (Cloudflare) | `f89990be` | Canlı, %100 | EVREN / `qwen3.8-flash-next`; ÖSYM kaynaklı P3/P93/P94 tanım düzeltmesi; model ve kotalar aynı |
| Site (GitHub Pages) | `site/` | https://xperspective.github.io/kamubul/ | Tanıtım, güncel iOS reklam/StoreKit gizlilik politikası (`run 42328465727`), destek (Türkçe) |

## Kimlikler

- Android paket: `com.crazypenguin.kamubul`; Play Console app id: `D:/AppPublishing/apps/kamubul/app-ids.env`.
- iOS bundle: `com.crazypenguin.kamubul`; App Store Connect app id `6826592263`; Team `53X3279WA3`; yayındaki sürüm `7cdd4a07-3f35-4977-948c-f690b09cb7c6` (1.2.4), yeni sürüm `e53880c3-e5b5-4428-be98-ed0528919b31` (1.2.5, build `112` / `af7bd0ba-3bd0-467b-890c-79670c8b144f`).
- Firebase proje `kamubul-3ae6e`; iOS app `1:1003012781397:ios:b1e2551cf6ba52d6ae2bdc`.
- iOS Pro: abonelik grubu `22513026`, ürün `kamubul_pro_monthly` (`6826881201`), 58,99 TRY/ay (175 bölge eşdeğer fiyat tablosu, güncel 47 karakter Türkçe açıklama ve reklamsız `pro-paywall.png` inceleme görüntüsü yüklü, durum `READY_TO_SUBMIT`), Türkiye.
- Görseller (25.10.2026): Google Play `tr-TR` 7 telefon ekran görüntüsü (`40220549808`, deneme rozetsiz gerçek uygulama çekimi) `edit 16344133390186283677` ile canlıya alındı; App Store `tr` 7 ekran görüntüsü (`a58c0899-970a-4ada-9e34-087e39958103`) ve SEO açıklamaları (`STORE_COPY.md`) 1.2.5 sürümünde bağlı.

## Nasıl yayınlanır

- **Android:** `flutter build appbundle --release --dart-define-from-file=D:/AppPublishing/apps/kamubul/credentials/firebase/android.defines.json` → Google Play Android Publisher API / Fastlane ile `production` kanalına (`release_status: completed`) yüklenir (sürüm notu: `metadata/tr-TR/changelogs/<versionCode>.txt`).
- **iOS:** `gh workflow run ios-release.yml -f upload=true -f ios_pro=true -f release_acceptance=true` → build App Store Connect'te işlenince sürüme bağlanır ve App Store Connect üzerinden incelemeye gönderilir (`docs/IOS_RELEASE.md`). Ayarlar `IOS_DART_DEFINES` ve `IOS_ADMOB_DEFINES` secret'larında.
- **Görseller:** iOS `ios-screenshots.yml`, Android `android-screenshots.yml` gerçek uygulamadan 7 sahne çeker; `python tool/brand/ios_store_frames.py <çekim> <çıktı> [--android]` Play araştırma setiyle (`docs/growth/STORE_COPY.md`) aynı sıra/başlıklarla, tek marka zemininde çerçeveler. Çıktılar `D:/AppPublishing/apps/kamubul/stores/{app-store/screenshots/tr,google-play/metadata/tr-TR/images/phoneScreenshots}`.
- **Worker:** `cd workers && npm test && npx wrangler deploy` (önce `wrangler deployments list` ile canlı sürümün depo HEAD'iyle aynı olduğunu doğrula).

## Mağaza beyanları (iOS ve Android)

- App Privacy: Yayındaki 1.2.4 beyanı Cihaz kimliği + Diğer kullanıcı içeriği (uygulama işlevi, kişiyle ilişkilendirilmez, takip yok). 1.2.5 (build 112) derlemesi `NSUserTrackingUsageDescription` içerdiği için App Store Connect API `reviewSubmissionItems` çağrısı `STATE_ERROR.BINARY_INDICATES_APP_TRACKS_USERS` döndürür; App Store Connect web arayüzünden **App Privacy** altında takip (`Tracking`) ve satın alma (`Purchases`) beyanlarının yayınlanması ve ilk aboneliğin (`kamubul_pro_monthly`) 1.2.5 sürüm sayfasına eklenerek incelemeye gönderilmesi gerekir.
- Yaş derecelendirmesi: `ageRatingDeclarations/80147f3d-28d0-4803-b502-cf4b4a2f744b` üzerinde `advertising: true` olarak güncellendi; diğer içerik soruları "yok". Kategori: İş / Başvuru Kaynakları. Fiyat: ücretsiz (uygulama içi Pro abonelik).
- Business (07.11.2026 geri okuması): Paid Apps, banka hesabı, W-8BEN ve Foreign Status sertifikası Active. Yeni sözleşme kabul edilmedi, banka/vergi verisi girilmedi. DSA tacir beyanı kullanıcı tarafından yönetiliyor.
- AdMob: Android `~6690717142` Hazır / reklam sunma etkin, doğru Play paketine bağlı. iOS `~2359389155`, App Store `6826592263` ile bağlı; dört birim etkin, uygulama incelemede ve reklam sunumu sınırlı. İki mevcut yönetici tüm uygulamalara etkin erişime sahip; yetkiler değiştirilmedi.
- `IOS_ADMOB_DEFINES` CI secret'ı yayıncıdaki beş mevcut iOS kimliğinden oluşturuldu; mevcut `IOS_DART_DEFINES` korunur. `ios-release.yml` koşusu `42328466180` ile 1.2.5 (build 112) IPA derlendi, imzası ve gerçek AdMob `GADApplicationIdentifier` plist değeri doğrulandı, App Store Connect'e yüklendi ve sürüm 1.2.5'e bağlandı.
- Play üretim 1.2.5 (20) `completed` (`edit 17496769459339978662`); aylık plan Active, 58,99 TRY. Ürün faydasındaki eski 100 soru vaadi canlı 50 soru sınırına düzeltildi; fiyat/plan değişmedi. Hesap genelindeki satıcı statüsü beyanının Şubat 2027'ye kadar tamamlanması gerekiyor; kullanıcıya ait beyan yapılmadı.

## Açık işler

- PB-039 iOS APNs anahtarı (kullanıcı) → iOS sunucu bildirimi.
- PB-040 iOS Pro: 1.2.5 (build 112) bağlı, ürün `READY_TO_SUBMIT`; App Privacy yayınlama + sürüm sayfasında ilk abonelik seçimi ve sunucu yetki doğrulaması (PB-038) bekleniyor.
- PB-041 iOS reklamları: 1.2.5 (build 112) yüklü, yaş beyanı `advertising: true`; AdMob incelemesi ve App Privacy takip beyanının web arayüzünden yayınlanması bekleniyor.
- PB-044 kaynak, model, kuyruk ve iOS/Android 1.2.5 yayın denetimi: `.project-brain/tasks/PB-044.md`.
- PB-042 kararsız `saved_search_edit_test`.

## Geçmiş

- 07.11.2026 — Android 1.2.5 (20) Google Play üretim kanalında yayınlandı (`completed`, AAB SHA-256 `f769753a492a62b5896f556448e56c4c05d1e62f4623da90f1e5eb1ddc84e4c3`). iOS 1.2.5 (build 112) `IOS_PRO=true` ve gerçek AdMob birimleriyle imzalanıp App Store Connect'e yüklendi ve sürüm `e53880c3-e5b5-4428-be98-ed0528919b31` kaydına bağlandı; mağaza açıklaması, sürüm notu, inceleme notu, yaş beyanı (`advertising: true`), abonelik açıklaması ve gizlilik politikası sayfası güncellendi. Worker `f89990be` ile KPSS P3/P93/P94 ÖSYM tanım düzeltmesi canlıya alındı.
- 06.11.2026 — iOS 1.2.4 (107) App Store'da onaylandı ve satışa açıldı (`READY_FOR_SALE`). Tanıtım sitesine (`xperspective.github.io/kamubul`) App Store indirme butonları ve bağlantıları eklendi.
- 25.10.2026 — Android 1.2.4 (19) üretim; iOS 1.2.4 (107) incelemeye. iOS: takvim, son başvuru hatırlatmaları, sunucu bildirimi altyapısı, bildirim izni, açılış çökmesi düzeltmesi. Asistan boş yanıt hatası düzeltildi (Worker).
- 24.10.2026 — iOS 1.2.3 (106) ilk gönderim; 1.2.4 için geri çekildi.
- 17.10.2026 — Android 1.2.3 (18) üretim.
