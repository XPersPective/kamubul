# Ürün Çalışma Zamanı Kabul ve Sınır Doğrulaması (PB-032 — 25 Ekim 2026)

Bu rapor, KamuBul mobil uygulamasının (`1.2.4+19`) 7 günlük reklamsız deneme süresi, KamuBul Pro abonelik geri yükleme/sonlanma geçişleri ve reklam görünürlük sınırlarını (`lib/store_features.dart`, `lib/ui/pro_page.dart`, `test/ads_state_test.dart`, `test/pro_store_test.dart`) belgeler.

## 1. Kod ve Otomatik Test Doğrulaması (`[machine]`, `[architecture]`)

1. **7 Günlük Deneme ve Reklam Koruması (`test/ads_state_test.dart`):**
   - Kurulum gününden itibaren 7 günlük reklamsız deneme süresi (`onboarding marker`, oturum sayısı ve reklam koruma süresi) yeniden başlatmalar arasında korunur (`test/ads_state_test.dart:1-85`).
   - Mağaza ekran görüntüsü çekim modunda (`STORE_SCREENSHOTS=true`) deneme rozeti gizlenir (`03bcb06`).
2. **KamuBul Pro Abonelik ve Reklam İzolasyonu (`test/ads_state_test.dart`, `test/pro_store_test.dart`, `lib/store_features.dart`):**
   - Aktif Pro abonesi olan kullanıcıdan hiçbir koşulda banner, geçiş (`interstitial`), uygulama açılış (`app_open`) veya ödüllü (`rewarded`) reklam istenmez (`test/ads_state_test.dart:Pro kullanıcıdan hiçbir reklam istenmez`).
   - Abonelik süresi dolduğunda veya geri yükleme (`restorePurchases`) boş döndüğünde sahte başarı mesajı gösterilmez; Pro durumu temizlenir (`test/pro_store_test.dart`).
3. **Platform Bazlı Mağaza Özellik Kapıları (`lib/store_features.dart`):**
   - **Android (`1.2.4+19`, Google Play üretimde `completed`):** `proAvailable = true` (`kamubul_pro_monthly`), `adsAvailable = true` (`ca-app-pub-0258900763816899~6690717142`).
   - **iOS (`1.2.4` build `107`, App Store `WAITING_FOR_REVIEW`):** Apple Paid Apps sözleşmesi (`Processing`) ve iOS AdMob hesap tanımlaması tamamlanana kadar `IOS_PRO=false` ve `adsAvailable=false` ile güvenli biçimde kapatılmıştır (`PB-040`, `PB-041`). Paywall (`lib/ui/pro_page.dart`) `adsAvailable=false` iken reklam kaldırma vaadi göstermez (`345c989`).

## 2. Açık Kalan Fiziksel Cihaz / Sandbox Kapıları

Birim ve widget testleri (`222/222` yeşil) gerçek Google Play Billing / StoreKit sandbox satın alma akışının veya fiziksel cihaz TalkBack ekran okuyucu davranışının yerine geçmez (`C-006`):
- **Android Fiziksel Cihaz / Play Billing Sandbox (`PB-032`, `PB-038`):** Gerçek Play lisans test hesabıyla abonelik satın alma, iptal/süre dolumu ve sunucu tarafı makbuz doğrulaması (`PB-038`) açık kapıdır.
- **iOS Sandbox ve Sunucu Bildirimi (`PB-039`, `PB-040`, `PB-041`):** Paid Apps sözleşmesi `Active` olduğunda (`PB-040`), APNs `.p8` anahtarı Firebase'e yüklendiğinde (`PB-039`) ve iOS AdMob birimleri tanımlandığında (`PB-041`) gerçek iPhone üzerinde doğrulanacaktır.
