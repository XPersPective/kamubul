# KamuBul yayın kaydı

Tek kaynak: her yayından sonra bu dosya güncellenir. Ortak sürüm numarası `pubspec.yaml` (`version: x.y.z+build`); Android versionCode = build, iOS build numarası CI'da `100 + run_number`.

## Güncel durum (25.10.2026)

| Platform | Sürüm | Mağaza durumu | Not |
|---|---|---|---|
| Android (Google Play) | 1.2.4 (19) | Üretim kanalı, `completed` | Politika durumu: sorun yok; bekleyen beyan yok |
| iOS (App Store) | 1.2.4 (build 107) | `WAITING_FOR_REVIEW` (25.10.2026 12:56 UTC) | Yalnız iPhone, yalnız Türkiye, ücretsiz |
| Worker (Cloudflare) | `fc777585` | Canlı | Asistan: sağlayıcı düşünmesi kapalı, 2000 token, 1 yeniden deneme |
| Site (GitHub Pages) | `site/` | https://xperspective.github.io/kamubul/ | Tanıtım, gizlilik, destek (Türkçe) |

## Kimlikler

- Android paket: `com.crazypenguin.kamubul`; Play Console app id: `D:/AppPublishing/apps/kamubul/app-ids.env`.
- iOS bundle: `com.crazypenguin.kamubul`; App Store Connect app id `6826592263`; Team `53X3279WA3`; sürüm kaydı `7cdd4a07-3f35-4977-948c-f690b09cb7c6`.
- Firebase proje `kamubul-3ae6e`; iOS app `1:1003012781397:ios:b1e2551cf6ba52d6ae2bdc`.
- iOS Pro: abonelik grubu `22513026`, ürün `kamubul_pro_monthly` (`6826881201`), 58,99 TRY/ay, Türkiye.

## Nasıl yayınlanır

- **Android:** `flutter build appbundle --release --dart-define-from-file=D:/AppPublishing/apps/kamubul/credentials/firebase/android.defines.json` → `fastlane run upload_to_play_store package_name:com.crazypenguin.kamubul track:production release_status:completed aab:build/app/outputs/bundle/release/app-release.aab json_key:D:/AppPublishing/publisher/crazypenguin/credentials/google-play/service-account.json metadata_path:D:/AppPublishing/apps/kamubul/stores/google-play/metadata skip_upload_metadata:true skip_upload_images:true skip_upload_screenshots:true` (sürüm notu: `metadata/tr-TR/changelogs/<versionCode>.txt`).
- **iOS:** `gh workflow run ios-release.yml -f upload=true [-f ios_pro=true]` → build App Store Connect'te işlenince sürüme bağlanır ve App Store Connect API ile incelemeye gönderilir (`docs/IOS_RELEASE.md`). Ayarlar `IOS_DART_DEFINES` secret'ında.
- **Görseller:** iOS `ios-screenshots.yml`, Android `android-screenshots.yml` gerçek uygulamadan 7 sahne çeker; `python tool/brand/ios_store_frames.py <çekim> <çıktı> [--android]` Play araştırma setiyle (`docs/growth/STORE_COPY.md`) aynı sıra/başlıklarla, tek marka zemininde çerçeveler. Çıktılar `D:/AppPublishing/apps/kamubul/stores/{app-store/screenshots/tr,google-play/metadata/tr-TR/images/phoneScreenshots}`.
- **Worker:** `cd workers && npm test && npx wrangler deploy` (önce `wrangler deployments list` ile canlı sürümün depo HEAD'iyle aynı olduğunu doğrula).

## Mağaza beyanları (iOS)

- App Privacy: Cihaz kimliği + Diğer kullanıcı içeriği; uygulama işlevi; kişiyle ilişkilendirilmez; takip yok.
- Yaş derecelendirmesi: tüm içerik soruları "yok". Kategori: İş / Başvuru Kaynakları. Fiyat: ücretsiz.
- Business: Paid Apps sözleşmesi banka/vergi doğrulamasında (Processing); W-8BEN ve Foreign Status sertifikası Active. DSA tacir beyanı kullanıcı tarafından yönetiliyor; ajan bu bölüme dokunmaz.

## Açık işler

- PB-039 iOS APNs anahtarı (kullanıcı) → iOS sunucu bildirimi.
- PB-040 iOS Pro aboneliği (Paid Apps Active olunca).
- PB-041 iOS reklamları (AdMob iOS hesabı).
- PB-042 kararsız `saved_search_edit_test`.

## Geçmiş

- 25.10.2026 — Android 1.2.4 (19) üretim; iOS 1.2.4 (107) incelemeye. iOS: takvim, son başvuru hatırlatmaları, sunucu bildirimi altyapısı, bildirim izni, açılış çökmesi düzeltmesi. Asistan boş yanıt hatası düzeltildi (Worker).
- 24.10.2026 — iOS 1.2.3 (106) ilk gönderim; 1.2.4 için geri çekildi.
- 17.10.2026 — Android 1.2.3 (18) üretim.
