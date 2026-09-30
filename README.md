# KamuBul

Türkiye'deki resmî kamu iş ilanları için premium, Türkçe Flutter Android/iOS uygulaması. **Geliştirme/geçiş aşamasında; mağazaya hazır değildir.** Hesap açmadan kişisel profil, kriterlerle isimlendirilmiş kayıtlı aramalar, favori ve uygun yeni ilan bildirimi hedeflenir.

## Mimari ve mevcut durum

Yeni hedef **Cloudflare Workers Free + D1 + Free Workers AI + Firebase Cloud Messaging (Spark)**. Kaynak toplama, AI özet/kanıtlı koşul, kişisel eşleşme ve push kararı sunucuda; SQLite cache/profil/favori, premium UI, izin/token/OS bildirim gösterimi telefondadır.

Şu an test Worker yalnız Hello World ve D1 boş; Firebase Android/FCM hazırlığı yapılmış. Mobil hâlâ local kaynak çekme/Workmanager ve isteğe bağlı v1 remote snapshot fallback kullanıyor. `backend/` önceki native Dart referans kod/testleri; Worker'a deploy edilemez. Eski Google/VPS deployment reçeteleri kaldırıldı. Gerçek server pilotu doğrulanınca PB-019 telefondaki fetch/scheduler ve kullanılmayan legacy runtime'ı kaldıracak; offline cache/favoriler korunacak.

Etiket modeli: kullanıcı kendi arama adını verir; kriterler ortak typed alan/sözlük değerlerinden oluşur (KPSS türü+puan, yaş, şehir, eğitim, meslek vb.). AI yalnız yeni/değişen ilanın ortak koşul/özetini çıkarır; kullanıcı profillerini modelle eşleştirmez. Match deterministic ve unknown ayrı durumdur.

[Project Brain başlangıcı](PROJECT_BRAIN.md), [ayrıntılı hedef](.project-brain/target.md), [gerçek durum](.project-brain/current.md), [görev/devir yol haritası](docs/CLOUDFLARE_FCM_YOL_HARITASI.md) ve [ADR-001](.project-brain/decisions/ADR-001.md). İlk implementasyon görevi **PB-016**; Cloud Run/Firestore/Blaze/ücretli AI talimatları geçerli değildir.

## Yerel kontrol

```sh
flutter pub get
flutter analyze
flutter test
```

Ortak core/backend kendi klasöründe `dart pub get`, `dart analyze`, `dart test` ile kontrol edilir. `napp_core`, `napp_pro`, `napp_ads` Git etiketlerine bağlı; napp_kit repo erişimi gerekir. Backend testleri bulut/FCM/model kanıtı değildir.

Firebase client ayarları Git dışında. Yerel Android build için `--dart-define-from-file=.tmp/firebase-android.defines.json` mevcut. KAMUBUL_API gerçek ilan servisi hazır olduğunda verilir; Hello World adresi kullanılmaz. Server private key/AI credential APK veya repoya girmez. AdMob test kimlikleri; gerçek signing/ad/contact ayarları release sahibindedir.

Kariyer Kapısı/SBB parserleri mevcut; Resmî Gazete kapsam dışı, İŞKUR/ilan.gov erişim kısıtları ve Cloudflare kaynak probe işi açıktır. [Kaynak kayıt defteri](docs/SOURCE_REGISTRY.md), [gizlilik](PRIVACY.md) ve [ortak standart](ORTAK_UYGULAMA_STANDARDI.md) geçerlidir. Kaynak terms/privacy/store beyanları yeni server kriter/token akışı için release öncesi yenilenecek.

Kod GPL-3.0; KamuBul adı ve logosu lisansa dahil değildir.
