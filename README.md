# KamuBul

Türkiye'deki resmî kamu iş ilanlarını takip etmek için Flutter uygulaması. **Geliştirme aşamasında; mağazaya hazır değildir.** Kariyer Kapısı (liste + resmî RSS + ayrıntı) ve Kamu İlanları (SBB) canlı okunur; Resmî Gazete kapsam dışıdır. İŞKUR ve ilan.gov.tr kanıtlı biçimde engellidir (WAF/oturum; aşma yapılmaz) — ayrıntılar [kaynak kayıt defterinde](docs/SOURCE_REGISTRY.md). Yerel ilan veritabanı, süzgeçler, kayıtlı aramalar, yer imleri, bildirimler (anlık/günlük özet), bildirim merkezi ve JSON yedekleme tamamdır; serbest soru-cevap sohbeti [TD-001](.project-brain/target.md) kararını bekler. iOS cihaz doğrulaması ve mağaza yayını için Apple bilgisayarı ve mağaza hesabı gerekir.

## Mimari

```
resmî kaynaklar ─► backend/ (Cloud Run işi, günde ~3 kez) ─► Firestore + anlık görüntü
                                                            └─► FCM ─► bildirim
uygulama ◄── /v1/listings.json (CDN) ── backend/ API (arayüzsüz)
```

- `packages/kamubul_core`: uygulama ve sunucunun paylaştığı saf Dart çekirdek (ayrıştırıcılar, şart çıkarımı, tekilleştirme, etiket eşleştirme, anlık görüntü şeması, sağlayıcıdan bağımsız AI katmanı).
- `backend/`: arayüzsüz API ve çekim işi. Google öncelikli (Cloud Run + Firestore + FCM), aynı imajla her VPS'te taşınabilir. Kurulum ve sınırlar: [backend/README.md](backend/README.md).
- Uygulama: `--dart-define=KAMUBUL_API=https://...` verilirse kataloğu sunucudan okur; sunucu bir kaynağı sağlayamazsa yalnızca o kaynak cihazdan çekilir. Verilmezse eskisi gibi tamamen cihazda çalışır.

## Çalıştırma

Uygulama (Flutter 3.47+; `napp_kit` erişimi gerekir):

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Çekirdek paket ve arka uç (yalnızca Dart SDK 3.13+):

```sh
cd packages/kamubul_core && dart pub get && dart analyze && dart test
cd backend && dart pub get && dart analyze && dart test
cd packages/kamubul_core && dart run tool/eval_extraction.dart      # şart çıkarım ölçümü
cd packages/kamubul_core && dart run tool/check_live_feed.dart      # canlı okuma denemesi
```

Sunucu bildirimi için derlemeye `KAMUBUL_API` ile birlikte `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID` değerleri `--dart-define` ile verilir (repoya `google-services.json` girmez). Verilmezse sunucu bildirimi seçeneği görünmez.

`napp_core`, `napp_pro`, `napp_ads` Git etiketlerine sabittir. Ücretli AI anahtarı uygulamaya gömülmez. AdMob test kimlikleriyle açılır; gerçek kimlikler ve iletişim adresi yalnızca yayın yapılandırmasından gelir. `android/key.properties.example` örnektir, gerçek imza dosyası repoya girmez.

## Proje devamlılığı

Ürün hedefi, mevcut mimari ve sıralı görevler [Project Brain](.project-brain/target.md) içinde. [Ortak uygulama standardı](ORTAK_UYGULAMA_STANDARDI.md) geçerlidir. [Kaynak kayıt defteri](docs/SOURCE_REGISTRY.md) her resmî kaynağın getirme yöntemini, hız sınırını, atfını ve son sonucunu tutar. [Gizlilik açıklaması](PRIVACY.md) yalnızca mevcut geliştirme sürümünün davranışını anlatır; reklam ve AI özellikleri yayınlanmadan önce mağaza beyanları yeniden doğrulanacaktır.

Kod GPL-3.0 lisanslıdır. KamuBul adı ve logosu lisansa dahil değildir.
