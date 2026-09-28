# KamuBul

Türkiye'deki resmî kamu iş ilanlarını takip etmek için Flutter uygulaması. **Geliştirme aşamasında; mağazaya hazır değildir.** Kariyer Kapısı (liste + resmî RSS + ayrıntı) ve Kamu İlanları (SBB) canlı okunur; Resmî Gazete adaptörü bağlıdır (son günlerde alım ilanı çıkmıyor). İŞKUR ve ilan.gov.tr kanıtlı biçimde engellidir (WAF/oturum; aşma yapılmaz) — ayrıntılar [kaynak kayıt defterinde](docs/SOURCE_REGISTRY.md). Yerel ilan veritabanı, süzgeçler, kayıtlı aramalar, yer imleri, bildirimler (anlık/günlük özet), bildirim merkezi ve JSON yedekleme tamamdır; serbest soru-cevap yapay zekâsı [TD-001](.project-brain/target.md) kararını bekler. iOS cihaz doğrulaması ve mağaza yayını için Apple bilgisayarı ve mağaza hesabı gerekir.

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

Ürün hedefi, mevcut mimari ve sıralı görevler [Project Brain](.project-brain/target.md) içinde. [Ortak uygulama standardı](ORTAK_UYGULAMA_STANDARDI.md) geçerlidir. [Kaynak kayıt defteri](docs/SOURCE_REGISTRY.md) her resmî kaynağın getirme yöntemini, hız sınırını, atfını ve son sonucunu tutar. [Gizlilik açıklaması](PRIVACY.md) yalnızca mevcut geliştirme sürümünün davranışını anlatır; reklam ve AI özellikleri yayınlanmadan önce mağaza beyanları yeniden doğrulanacaktır.

Kod GPL-3.0 lisanslıdır. KamuBul adı ve logosu lisansa dahil değildir.
