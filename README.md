# KamuBul

Türkiye'deki resmî kamu iş ilanları için premium, Türkçe Flutter Android/iOS uygulaması. **Geliştirme/geçiş aşamasında; mağazaya hazır değildir.** Hesap açmadan kişisel profil, kriterlerle isimlendirilmiş kayıtlı aramalar, favori ve uygun yeni ilan bildirimi hedeflenir.

## Mimari ve mevcut durum

Yeni hedef **Cloudflare Workers Free + D1 + Free Workers AI + Firebase Cloud Messaging (Spark)**. Kaynak toplama, AI özet/kanıtlı koşul, kişisel eşleşme ve push kararı sunucuda; SQLite cache/profil/favori, premium UI, izin/token/OS bildirim gösterimi telefondadır.

Kalıcı Worker/D1 ve Cron yayında; resmî Kariyer RSS ilanları v2 API'den okunuyor. Mobil, API ayarlanmışsa SQLite cache + metadata/delta/bootstrap senkronizasyonunu kullanıyor. Kaynak ayrıntısı/AI ve gerçek cihaz FCM pilotu tamamlanmadığından telefonun eski kaynak çekme/Workmanager yolları hâlâ duruyor. `backend/` önceki native Dart referans kod/testleri; Worker'a deploy edilemez. PB-019 pilot kapıları geçince eski runtime kaldırılacak; offline cache/favoriler korunacak. Doğrulanmış kapsam ve açık eksikler Project Brain'dedir.

Etiket modeli: kullanıcı kendi arama adını verir; kriterler ortak typed alan/sözlük değerlerinden oluşur (KPSS türü+puan, yaş, şehir, eğitim, meslek vb.). AI yalnız yeni/değişen ilanın ortak koşul/özetini çıkarır; kullanıcı profillerini modelle eşleştirmez. Match deterministic ve unknown ayrı durumdur.

[Project Brain başlangıcı](PROJECT_BRAIN.md), [ayrıntılı hedef](.project-brain/target.md), [gerçek durum](.project-brain/current.md), [görev/devir yol haritası](docs/CLOUDFLARE_FCM_YOL_HARITASI.md) ve [ADR-001](.project-brain/decisions/ADR-001.md). İlk implementasyon görevi **PB-016**; Cloud Run/Firestore/Blaze/ücretli AI talimatları geçerli değildir.

## Yerel kontrol

```sh
flutter pub get
flutter analyze
flutter test
```

Ortak core/backend kendi klasöründe `dart pub get`, `dart analyze`, `dart test` ile kontrol edilir. `napp_core`, `napp_pro`, `napp_ads` Git etiketlerine bağlı; napp_kit repo erişimi gerekir. Backend testleri bulut/FCM/model kanıtı değildir.

Firebase client ayarları Git dışında. Yerel Android build için `--dart-define-from-file=.tmp/firebase-android.defines.json --dart-define=KAMUBUL_API=https://kamubul-api.devx8585.workers.dev` mevcut. Server private key/AI credential APK veya repoya girmez. AdMob test kimlikleri; gerçek signing/ad/contact ayarları release sahibindedir.

### Android üretim imzası

Release APK/AAB `android/key.properties` içindeki `storeFile`, `storePassword`,
`keyAlias`, `keyPassword` ile imzalanır; debug anahtarına fallback yoktur.
Eksik/boş alan veya standart `androiddebugkey` alias'ı release doğrulamasını
durdurur. Debug/profile geliştirme derlemeleri kendi debug imzasını kullanır.
Gerçek değerler yalnız gitignore'daki dosyaya girilir; örnek dosya
`android/key.properties.example`dir. `storeFile` mutlak yol veya `android/`
dizinine göre relatif yoldur. Windows'ta `/` ya da kaçışlı `\\` kullanılır.

İmza doğrulaması (JDK ayarlı terminal, `android/` içinde):

```sh
gradlew :app:checkReleaseSigning :app:validateSigningDebug :app:validateSigningProfile --continue
```

Anahtar yokken release'in hata vermesi ve debug/profile'ın geçmesi beklenir.
Anahtar varken AGP dosya/keystore doğrulamasını da yapar; gerçek APK/AAB
imzası ayrıca release artifact üzerinde doğrulanmalıdır. Anahtarı/parolaları
repo veya sohbete koymayın; repo dışında iki ayrı güvenli yedek tutun ve
mağazadaki mevcut upload-key kimliğini değiştirmeyin.

Release paketleme ayrıca `--dart-define=CONTACT_EMAIL=...` ister. Boş/hatalı
adres, example.com/net/org (alt alanları dahil) ve test/invalid/localhost
alanları reddedilir; debug/profile geliştirme akışı korunur. Bu yazım kontrolü
posta kutusunun sahipliğini veya çalıştığını doğrulamaz. Gerçek destek adresini
release sahibi doğrulamalıdır. JDK ayarlı PowerShell'de artefact/anahtar
üretmeden native kontrol: `powershell -File tool/check-release-contact.ps1`.

[Flutter Android yayın rehberi](https://docs.flutter.dev/deployment/android)
anahtar oluşturma ve Play App Signing ayrımını açıklar. Bu yapılandırma gerçek
anahtarın sağlandığı, yedeklendiği veya mağaza yayınının tamamlandığı kanıtı değildir.

Android güvenli depo kontrolü mevcut `integration_test/secure_push_store_test.dart` ve `test_driver/integration_test.dart` ile çalışır. Önce normal APK'yı ayrı yerde koruyun; integration build aynı çıktı yolunu kullanır. Dar depolamalı x64 emülatör için:

```sh
flutter build apk --debug --target-platform android-x64 --target integration_test/secure_push_store_test.dart
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/secure_push_store_test.dart --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk -d emulator-5556
```

Cihaz ID'sini `adb devices` sonucuna göre seçin. İlk manuel kurulum başarısızsa veri silen uninstall ile ilerlemeyin. Kontrol sonrası normal APK'yı `adb install -r` ile geri kurun. Kontrol native yazma/yeniden okuma/plaintext temizliğini kanıtlar; gerçek push, süreç yeniden başlatma, backup/restore veya iOS kanıtı değildir. Eski Workmanager kaydı test binary'sinde bulunmayan uygulama callback'ini çalıştırmayı deneyebilir; normal APK geri kurulmalıdır.

Kariyer Kapısı/SBB parserleri mevcut; Resmî Gazete kapsam dışı, İŞKUR/ilan.gov erişim kısıtları ve Cloudflare kaynak probe işi açıktır. [Kaynak kayıt defteri](docs/SOURCE_REGISTRY.md), [gizlilik](PRIVACY.md) ve [ortak standart](ORTAK_UYGULAMA_STANDARDI.md) geçerlidir. Gizlilik açıklaması Cloudflare kriter/token/arama adı ve silme akışıyla hizalandı; kaynak terms, gerçek destek iletişimi ve mağaza beyanları release öncesi ayrıca doğrulanacak.

Kod GPL-3.0; KamuBul adı ve logosu lisansa dahil değildir.
