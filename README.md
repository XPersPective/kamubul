# KamuBul

Türkiye'deki resmî kamu iş ilanlarını takip etmek için Flutter uygulaması. **Geliştirme aşamasında; mağazaya hazır değildir.** Şu an Kariyer Kapısı'nın herkese açık RSS akışından ilanlar okunur. İŞKUR, ilan.gov.tr, Resmî Gazete ve belediye tarayıcıları; yerel ilan veritabanı, bildirimler ve API asistanı henüz tamamlanmadı.

## Çalıştırma

Flutter 3.47+ ile:

```sh
flutter pub get
flutter run
flutter analyze
flutter test
dart run tool/check_live_feed.dart
```

`napp_core`, `napp_pro`, `napp_ads` Git etiketlerine sabittir. Ücretli AI anahtarı uygulamaya gömülmez. AdMob test kimlikleriyle açılır; gerçek kimlikler ve iletişim adresi yalnızca yayın yapılandırmasından gelir. `android/key.properties.example` örnektir, gerçek imza dosyası repoya girmez.

## Proje devamlılığı

Ürün hedefi, mevcut mimari ve sıralı görevler [Project Brain](.project-brain/target.md) içinde. [Ortak uygulama standardı](ORTAK_UYGULAMA_STANDARDI.md) geçerlidir. [Gizlilik açıklaması](PRIVACY.md) yalnızca mevcut geliştirme sürümünün davranışını anlatır; reklam ve AI özellikleri yayınlanmadan önce mağaza beyanları yeniden doğrulanacaktır.

Kod GPL-3.0 lisanslıdır. KamuBul adı ve logosu lisansa dahil değildir.
