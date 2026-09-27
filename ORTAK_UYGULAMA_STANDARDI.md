# ORTAK UYGULAMA STANDARDI — Flutter (Android + iOS)

Bu dosya her yeni uygulamanın başında yapay zekâya verilen tam prompttur.
Aşağıdaki kuralların hepsi zorunludur. Projeye özel istekler bunların ÜSTÜNE
eklenir, hiçbirini zayıflatmaz. Emin olmadığın yerde en güvenli seçeneği seç ve
kararını gerekçesiyle PROJECT_BRAIN.md'ye yaz.

---

## 0. PROJE AYARLARI — ÖNCE BUNU OKU

Aşağıdaki üç ayar bu uygulamanın nasıl kurulacağını belirler. Varsayılanlar
yazılıdır. Sahip bir ayarı değiştirmek isterse değerini değiştirir ya da o
bölümü siler; **silinmiş bir bölüm varsayılan değerinde kabul edilir, "HAYIR"
değil.** Bir özellik kapatılmak isteniyorsa değer açıkça `HAYIR` yazılır.

| Ayar | Değer | Anlamı |
|---|---|---|
| **REKLAM** | `EVET` | `EVET`: bölüm 5.2'deki reklam modeli uygulanır. `HAYIR`: hiçbir reklam paketi projeye EKLENMEZ; reklam, onay formu (UMP), ATT ve ödüllü reklam kodu yazılmaz; bölüm 5.2 tamamen atlanır. |
| **PRO (ömür boyu)** | `EVET` | `EVET`: bölüm 5.1'deki tek seferlik Pro satın alma uygulanır. `HAYIR`: satın alma paketi eklenmez, paywall yoktur, "Pro'ya özel" hiçbir özellik kilitlenmez. |
| **VERİ** | `YEREL` | `YEREL`: bölüm 6.1 uygulanır, bölüm 6.2 atlanır. `BULUT`: bölüm 6.2 uygulanır (6.1'deki cihaz içi kurallar da geçerlidir). |

Kurallar:
- REKLAM = `HAYIR` ve PRO = `EVET` ise Pro'nun faydaları "reklamsız" olarak
  anlatılamaz; yalnızca gerçek Pro özellikleri satılır.
- REKLAM = `HAYIR` ve PRO = `HAYIR` ise gelir modeli yoktur; uygulama tamamen
  ücretsizdir. Gizlilik politikası ve mağaza formları buna göre doldurulur.
- Bu tabloda bulunmayan bir ayar varsayma; sor.

---

## 1. GÜVENLİK — GitHub'a ve dışarıya hiçbir sır gitmez

### 1.1 İlk commit'ten önce
- `.gitignore` İLK commit'ten ÖNCE kurulur ve en az şunları içerir:
  ```
  .env
  .env.*
  *.env
  !.env.example
  android/key.properties
  android/local.properties
  *.jks
  *.keystore
  *.p12
  *.pfx
  *.pem
  *.key
  *.p8
  *.mobileprovision
  *.cer
  google-services.json
  GoogleService-Info.plist
  **/firebase_options.dart
  service-account*.json
  *-credentials.json
  fastlane/report.xml
  fastlane/*.json
  fastlane/.env*
  ios/Pods/
  build/
  .dart_tool/
  coverage/
  *.log
  .idea/workspace.xml
  .vscode/settings.json
  *.symbols
  ```
  Aklıma gelmeyen bir sır türü çıkarsa `.gitignore`'a EKLE. `.gitignore`'dan
  hiçbir satır çıkarılmaz, hiçbir kural zayıflatılmaz.
- Örnek dosyalar repoda durur, gerçekleri durmaz: `.env.example`,
  `android/key.properties.example`, `google-services.json.example`
  (içlerinde yalnızca sahte değerler).
- İlk commit'ten önce `git status` ve `git diff --cached` gözle kontrol edilir.

### 1.2 Sırların kullanımı
- Gerçek anahtar, kimlik ya da şifre KODA YAZILMAZ. Değerler derleme sırasında
  `--dart-define` ile verilir ve tek bir yerde okunur
  (`lib/core/config/env_config.dart`).
- Repoda yalnızca Google'ın resmi TEST reklam kimlikleri ve açıkça sahte yer
  tutucular (`PLACEHOLDER-...`) bulunur. Gerçek sanılabilecek sahte değer
  yazılmaz.
- Uygulama hiçbir sır olmadan derlenip çalışmalıdır (test değerlerine düşer).
- Uygulamaya gömülen her şeyin çıkarılabileceği varsayılır: bir mobil
  uygulamanın içinde gizli sunucu anahtarı, yönetici şifresi ya da ücretli API
  anahtarı TUTULMAZ. Böyle bir anahtar gerekiyorsa bölüm 6.2'ye göre sunucu
  tarafında tutulur.
- İmza anahtarı (keystore), şifreleri ve Apple sertifikaları repo dışında en az
  iki ayrı yerde yedeklenir. README'de nasıl yedeklendiği anlatılır; değerleri
  asla. Keystore kaybı uygulamanın bir daha güncellenememesi demektir.

### 1.2.1 Reklam ve satın alma kimlikleri
Bu kimlikler şifre değildir (yayınlanan uygulamanın içinden okunabilirler), ama
GitHub'a konmazlar: kimliğin yayında olması başkasının onu kopya uygulamalarda
kullanmasına, sahte trafik üretip AdMob hesabının kapatılmasına ve hesabın
kime ait olduğunun görünmesine yol açar.
- **AdMob uygulama kimliği** (`ca-app-pub-…~…`):
  - Android: `AndroidManifest.xml`'e sabit yazılmaz; `android:value="${admobAppId}"`
    yer tutucusu kullanılır. Değer `build.gradle.kts` içinde, gitignore'daki
    `android/key.properties` dosyasının `admobAppId` satırından okunur; dosya
    yoksa Google'ın resmi test kimliğine (`ca-app-pub-3940256099942544~3347511713`)
    düşer.
  - iOS: `Info.plist`'te `GADApplicationIdentifier` = `$(ADMOB_APP_ID)`;
    değer gitignore'daki bir `.xcconfig` dosyasından gelir, yoksa Google'ın iOS
    test kimliği.
- **Reklam birimi kimlikleri** (banner, geçiş, ödüllü, açılış): koda yazılmaz;
  `--dart-define` ile verilir, `env_config.dart` yoksa Google'ın test
  birimlerine düşer.
- **Satın alma ürün kimliği** (`<uygulama>_pro_lifetime`): gizli değildir, kodda
  durabilir (mağaza dışında hiçbir işe yaramaz). Ama mağaza hesap numaraları,
  Partner Center yayıncı kimliği, lisans anahtarları (Play "Base64 lisans
  anahtarı" vb.) ve servis hesabı dosyaları koda ve repoya GİRMEZ.
- Örnek dosyalarda (`key.properties.example` vb.) yalnızca `XXXX` yer tutucuları.
- Doğrulama: sürüm derlemesinin manifest'i okunur (`aapt2 dump xmltree`), gerçek
  kimliğin derlemede, test kimliğinin sırsız derlemede olduğu kontrol edilir.
- Yanlışlıkla commit edilmişse: koddan kaldırılır; geçmişten temizlemek
  (`git filter-repo` + zorla push) proje sahibinin onayıyla yapılır. Reklam ve
  ürün kimlikleri iptal edilemez; kopya uygulamada kullanıldığı görülürse AdMob'a
  bildirilir.

### 1.3 Sızıntı önleme
- `gitleaks` pre-commit kancası kurulur; CI'da da `gitleaks` çalışır.
- GitHub'da "Secret scanning" ve "Push protection" açılır. Dependabot (pub,
  gradle, github-actions) açılır.
- Commit mesajlarına, loglara, ekran görüntülerine, hata raporlarına ve issue'lara
  anahtar, e-posta, telefon, adres ya da kişisel bilgi yazılmaz. Proje sahibinin
  kişisel bilgileri hiçbir dosyada yer almaz.
- Sızıntı olursa sıra: 1) anahtar HEMEN iptal edilir ve yenisi üretilir,
  2) sonra geçmişten temizlenir. Yalnızca geçmişten silmek yeterli değildir;
  GitHub'a giden bir sır ele geçmiş sayılır.

### 1.4 Uygulama içi güvenlik
- Sürüm derlemesi: `--obfuscate --split-debug-info=<repo dışı klasör>`;
  sembol dosyaları repoya girmez, yedeklenir.
- Android: `usesCleartextTraffic=false` (yalnızca HTTPS). iOS: App Transport
  Security açık, istisna yok.
- Android yedekleme: `dataExtractionRules` / `fullBackupContent` ile yalnızca
  güvenli ayarlar yedeklenir; hassas veri ve anahtarlar yedeğe girmez.
- Hassas küçük veriler (belirteçler, şifreli veritabanı anahtarı)
  `flutter_secure_storage` ile Android Keystore / iOS Keychain'de tutulur;
  SharedPreferences'ta tutulmaz.
- Dışarıdan gelen her veri doğrulanır: içe aktarılan dosyalar (sürüm alanı, tip
  kontrolü, sınırlar), deep link'ler, kopyala-yapıştır kodları, ağ yanıtları.
  Geçersiz veri uygulamayı çökertmez, veri kaybettirmez.
- Deep link'ler yalnızca beklenen yollara izin verir; beklenmeyen parametreyle
  işlem yapmaz.
- WebView kullanılırsa: JavaScript yalnızca gerekirse, dosya erişimi kapalı,
  yalnızca kendi alan adları.
- Loglarda kişisel veri yok; sürüm derlemesinde debug çıktısı yok.
- Android: dışa açık (`exported`) bileşen yalnızca gerçekten gerekiyorsa; her
  `PendingIntent` `FLAG_IMMUTABLE`; yayınlar `setPackage` ile açık.
- İzinler en az düzeyde: kullanılmayan izin manifest'te olmaz. Her izin
  kullanıcıya nedeniyle anlatılır; reddedilirse uygulama çökmez, anlaşılır mesaj
  verir.
- Korsan Pro'ya karşı: satın alma doğrulaması mağazanın kendi mekanizmasıyla
  yapılır. Sunucu yoksa (VERİ = YEREL) bunun bir tavanı vardır; bu tavan
  PROJECT_BRAIN.md'de dürüstçe yazılır, uydurma "koruma" eklenmez.

---

## 2. LİSANS VE BAĞIMLILIKLAR

- Proje lisansı: **GNU GPL-3.0** — resmi, açık kaynak topluluğunca (OSI, FSF)
  kabul edilen bir açık kaynak lisansı. DoctorFilter ile aynı lisans. `LICENSE`
  dosyası GNU'nun resmi tam metnidir.
- GPL-3.0'ın anlamı (Hakkında sayfasında ve README'de doğru anlatılır): kod
  herkese açıktır; herkes okuyabilir, değiştirebilir, dağıtabilir. Kodu ya da
  değiştirilmiş hâlini dağıtan, KAYNAK KODUNU da aynı GPL-3.0 lisansıyla açmak
  zorundadır; kodu kapalı bir ürüne çeviremez. Metinlerde "ticari kullanım
  yasak" gibi lisansın söylemediği bir iddia yazılmaz.
- Proje sahibi tek telif hakkı sahibi olarak kendi uygulamasını mağazalarda
  yayınlayabilir, Pro satabilir, reklam gösterebilir. Dış katkı kabul edilirse
  bu hakkı korumak için katkıcıların katkılarını proje sahibine lisansladığı
  kısa bir katkı sözleşmesi (CONTRIBUTING.md) kullanılır.
- Kopyalara karşı asıl koruma marka: uygulama adı ve logosu için marka tescili
  önerilir. GPL kopyalamaya izin verir ama başkası senin adını ve logonu
  kullanamaz; adı/logoyu kullanan kopyalar mağazaya marka şikâyetiyle
  bildirilir. README'de ad ve logonun lisansa dahil olmadığı yazılır.
- Tüm bağımlılıklar ÜCRETSİZ, TİCARİ KULLANIMA AÇIK ve GPL-3.0 ile UYUMLU
  olmalı: MIT, BSD-2/3, Apache-2.0, Zlib, ISC, LGPL; fontlarda SIL OFL 1.1;
  ikon ve görsellerde benzeri. AGPL / SSPL / "non-commercial" / ücretli /
  kaynağı belirsiz paket ve varlık KULLANILMAZ. Her paket eklenmeden önce
  lisansı kontrol edilir.
- `THIRD_PARTY_LICENSES.md`: her paket, font, ikon ve görsel için ad, ne için
  kullanıldığı, lisansı.
- Kullanılmayan paket, font ve görsel projede tutulmaz.

---

## 3. ZORUNLU EKRANLAR VE ÖZELLİKLER

### 3.1 Çok dil
- En az Türkçe ve İngilizce; hedef 71 dil (JSON çeviri dosyaları, her dilde aynı
  anahtarlar, eksik anahtarı yakalayan test).
- Hiçbir ekranda çevrilmemiş metin yok; native tarafta görünen metinler
  (bildirim, widget, kısayol) de uygulama dilinde.
- Sağdan sola diller (ar, fa, he, ur, ps) doğru yönde; sayı + birim ("2700 K",
  "%40") RTL paragrafta ters dönmez (Unicode LTR isolate).
- Saat, tarih ve sayı biçimi yerel ayardan gelir; elle "PM" yazılmaz.
- Dil uygulama içinden seçilebilir; ilk açılışta cihaz dili.
- Çeviriler doğal ve kültüre uygun; makine çevirisi kontrol edilmeden bırakılmaz.

### 3.2 Tema
- Açık / Koyu / Sistem; kullanıcı seçer, seçim kalıcıdır.
- İki tema tek bir tema üreticisinden çıkar; bileşenlerde sabit renk yazılmaz
  (tema token'ları kullanılır). Her ekranın her yazısı iki temada okunur.

### 3.3 Hakkında sayfası (özenle, güzel bir şekilde)
- Üstte uygulama logosu, adı, sürümü ve kısa slogan.
- Belirgin bir "Açık kaynak" bölümü, sıcak ve anlaşılır bir dille:
  - Bu uygulamanın açık kaynak olduğu, kodun herkese açık olduğu, ne yaptığının
    koddan doğrulanabileceği, gizli bir şey olmadığı.
  - Kaynak koduna giden bağlantı (GitHub), lisansın adı (GNU GPL-3.0) ve bir
    cümleyle anlamı ("kodu okuyabilir, değiştirebilir ve paylaşabilirsiniz;
    değiştirilmiş sürümler de açık kaynak kalmalıdır").
  - Katkı ve hata bildirimi yolu (issue bağlantısı).
- Gizlilik: verilerin nerede tutulduğu tek cümleyle (VERİ ayarına göre) ve
  gizlilik politikası bağlantısı.
- Lisanslar ekranına bağlantı (3.4).
- İletişim / geri bildirim (e-posta uygulamasını açan bağlantı; e-posta adresi
  repoya değil derleme ayarına konur).
- Uygulama sağlık, finans, hukuk gibi bir alandaysa feragat metni (bölüm 7).
- Sürüm notları (CHANGELOG'dan) — isteğe bağlı.

### 3.4 Lisanslar ekranı
- Flutter'ın `showLicensePage`'i + paketlerin bildirmediği font, ikon ve
  görsellerin lisansları. Uygulamanın kendi lisansı en üstte.

### 3.5 Paylaş ve puan ver
- Paylaş: `share_plus`, uygulama dilinde kısa metin + doğru mağaza bağlantısı
  (Android'de Play, iOS'ta App Store).
- Puan ver: `in_app_review`. Uygulama içi puanlama penceresi yalnızca olumlu bir
  andan sonra, seyrek (mağaza kotalarına saygılı) ve asla bir işin ortasında
  istenir; ayarlardaki "Puan ver" satırı doğrudan mağaza sayfasını açar.
  Puan karşılığında ödül verilmez (mağaza kuralı).

### 3.6 Diğer uygulamalarımız ("Diğer Uygulamalarımızı Keşfedin")
- Ayrı bir sayfa; ayarlardan VE ana ekrandan/menüden kolayca görülen bir yerden
  ulaşılır.
- Her uygulama için: ikon, ad, kısa açıklama (uygulama dilinde), dokununca
  Android'de Google Play, iOS'ta App Store sayfası. Şu an açık olan uygulama
  listede gösterilmez. Kart tasarımı özenli, iki temada uyumlu.
- Veri kaynağı GitHub'dır: proje sahibinin herkese açık bir reposundaki tek
  bir `apps.json` dosyası, `https://raw.githubusercontent.com/<kullanıcı>/<repo>/main/apps.json`
  adresinden HTTPS ile çekilir (adres derleme ayarından gelir, koda sabit
  yazılmaz). Örnek kayıt:
  ```json
  {
    "schema": 1,
    "apps": [
      {
        "id": "ornek_uygulama",
        "androidPackage": "com.ornek.uygulama",
        "appStoreId": "1234567890",
        "icon": "https://raw.githubusercontent.com/<kullanıcı>/<repo>/main/icons/ornek_uygulama.png",
        "name": { "en": "Example App", "tr": "Örnek Uygulama" },
        "description": { "en": "One line about it.", "tr": "Tek cümlelik açıklama." },
        "order": 1
      }
    ]
  }
  ```
  Uygulama dosyayı çeker, önbellekte tutar (ör. 24 saat), internet yoksa ya da
  dosya bozuksa önbelleği, o da yoksa uygulamaya gömülü kopyayı gösterir.
  Uygulama dilinde metin yoksa İngilizce gösterilir. Kendisiyle aynı paket
  adını taşıyan kayıt listede gösterilmez. Yeni uygulama yayınlamak = bu dosyaya
  bir kayıt ve bir ikon eklemek; diğer uygulamalar güncelleme gerektirmeden
  görür. Dokununca Android'de `https://play.google.com/store/apps/details?id=<paket>`,
  iOS'ta `https://apps.apple.com/app/id<appStoreId>` açılır.
- **Diğer uygulamayı indirene ödül YOK.** "Şu uygulamamızı kur, 1 gün Pro kazan"
  türü hiçbir ödül, kredi ya da geçici Pro verilmez. Apple App Store Review
  Guidelines 3.2.2 "başka uygulama indirmeyi" karşılığında ödül vermeyi açıkça
  yasaklar; Google Play de 2022'den beri yükleme karşılığı ödülü yasaklar.
  Sayfa yalnızca tanıtır; indirmek tamamen kullanıcının isteğidir.
- iOS'ta isteğe bağlı: Apple'ın resmi iTunes Lookup API'si
  (`https://itunes.apple.com/lookup?id=<geliştirici-id>&entity=software`)
  ile ikon/ad/açıklama otomatik çekilebilir. Google Play için resmi bir API
  yoktur; Play sayfaları KAZINMAZ (kurallara aykırı, kırılgan).
- Dışarıdan gelen JSON doğrulanır (bölüm 1.4); bozuk kayıt atlanır, uygulama
  çökmez.

### 3.7 Diğer ortak özellikler
- Onboarding: kısa, atlanabilir; ilk ekranda uygulamanın kendi ikonu.
- Veriyi dışa / içe aktarma: bölüm 3.8.
- Geri al (yanlışlıkla yapılan değişiklik tek dokunuşla geri alınır) — uygun
  olan uygulamalarda.
- Hata durumlarında anlaşılır, çevrilmiş mesaj; boş durumlarda yol gösteren
  metin.

### 3.8 Veriyi JSON olarak dışa / içe aktarma
- Kullanıcı verisi ve ayarları tek bir JSON dosyasına dışa aktarılabilir ve
  aynı dosyadan içe aktarılabilir (paylaşım menüsü / dosya seçici).
- **PRO = EVET ise bu özellik Pro'ya özeldir:** dışa ve içe aktarma yalnızca
  ömür boyu Pro satın alındıktan sonra (ya da ödüllü reklamla açılan geçici Pro
  süresince) çalışır. Pro olmayan kullanıcı satırları kilit simgesiyle görür,
  dokununca paywall açılır. Amaç: ücretsiz kullanıcı uygulamayı silip yeniden
  kurarak ya da telefonu sıfırlayarak Pro özelliklerini yedek dosyasıyla bedava
  taşıyamasın.
- **PRO = HAYIR ise** herkes kullanabilir.
- Dosyada Pro durumu, satın alma bilgisi, reklam sayaçları, kurulum tarihi ve
  hiçbir sır/anahtar YER ALMAZ; Pro yalnızca mağazadan gelir. İçe aktarma Pro'yu
  asla açmaz.
- Dosyada `formatVersion` alanı bulunur; eski sürümler okunabilir, bilinmeyen
  alanlar yok sayılır, değerler uygulamanın sınırlarına kırpılır, bozuk dosya
  hiçbir şeyi değiştirmeden anlaşılır bir hatayla reddedilir (bölüm 1.4).
- VERİ = BULUT ise dışa aktarma yine kullanıcının kendi verisidir (GDPR veri
  taşınabilirliği); içe aktarma yalnızca kullanıcının kendi hesabına yazar.

---

## 4. MARKA VE GÖRÜNÜM

- Tek bir kaynak ikondan bütün boyutları üreten bir betik (`tool/brand/`):
  Android uyarlanabilir ikon + Android 13 temalı (monochrome) ikon, Android 12+
  ve eski sürümler için splash, iOS ikonları (opak, alfa yok), web ve varsa
  masaüstü ikonları. Hiçbir platformda Flutter'ın varsayılan logosu kalmaz.
- Başlıkta logo: solda ikon (yazıya yakın), yanında ikonun renkleriyle uygulama
  adı, Pro kullanıcıda sonunda küçük ve zarif "PRO" işareti, altında slogan.
  Paywall başlığı da aynı logo + PRO işaretidir.
- Splash'ta uygulamanın gerçek ikonu; splash, uygulamanın açılış temasıyla
  aynı zeminde (açılışta beyaz parlama olmaz).
- Kullanıcı dostu: net hiyerarşi, tutarlı boşluklar, kaydırıcı gibi kontroller
  sürüklenirken yerinden oynamaz (yanlarına beliren/kaybolan öğe olmaz).

---

## 5. GELİR MODELİ

### 5.1 PRO — ömür boyu, tek seferlik (PRO = EVET ise; HAYIR ise bu bölümü atla)
- Tek ürün: ömür boyu Pro (non-consumable). **Abonelik YOK.** Ürün kimliği
  `<uygulama>_pro_lifetime`, Google Play ve App Store'da AYNI ad.
- Yalnızca mağazanın kendi ödeme sistemi (`in_app_purchase`). Uygulamada kart
  formu, dış ödeme bağlantısı yok.
- Pro'nun getirdikleri: tüm reklamların kaldırılması (REKLAM = EVET ise, banner
  dahil) + uygulamanın Pro özellikleri. Pro kullanıcı için reklam SDK'sı HİÇ
  başlatılmaz; reklam kalkınca ekranda boşluk kalmaz.
- "Satın alımı geri yükle" düğmesi zorunlu (Apple kuralı). Açılışta sessiz geri
  yükleme (yeni telefon, yeniden kurulum, başka cihazda tamamlanan satın alma).
- `completePurchase` her zaman çağrılır (atlanırsa Play 3 gün sonra iade eder,
  Apple her açılışta tekrar oynatır). Bekleyen ödeme (pending), iptal ve hata
  ayrı ayrı ele alınır; tanınmayan bir yanıt asla "satın alındı" sayılmaz.
- Pro durumu önce cihazdan okunur; ödeme yapmış kullanıcı açılışta bir anlık
  reklam görmez.
- Paywall dürüst: gerçek faydalar, mağazadan gelen fiyat (biçimlenmiş metin),
  "tek ödeme, abonelik yok" vurgusu, geri yükleme düğmesi. Sahte indirim, geri
  sayım, suçluluk dili YOK.
- Kilitli bir özelliğe dokunmak paywall'u açar (boş dokunuş bozuk düğme gibi
  görünür).

### 5.2 REKLAM (REKLAM = EVET ise; HAYIR ise bu bölümü tamamen atla)
- Kurallar reklam SDK'sından bağımsız, saf ve birim testli tek bir sınıfta
  (`AdPolicy`) yaşar; ekranlar yalnızca ona sorar.
- **İlk günden itibaren yalnızca küçük banner.** Banner yüklenmezse ekranda boşluk
  bırakmaz.
- **Açılış (app-open) reklamı:** kurulumdan sonraki ilk 7 gün VE ilk 5 oturum
  boyunca HİÇ gösterilmez. Sonrasında: oturumda en fazla 1 tam ekran reklam
  (açılış + geçiş reklamı toplamı), iki açılış reklamı arasında en az 4 saat;
  yalnızca uygulama sıfırdan açılırken; 4 saniyede yüklenmezse gösterilmez;
  onboarding'in üstüne asla.
- **Geçiş (interstitial) reklamı:** aynı 7 gün / 5 oturum koruması; yalnızca
  doğal duraklarda (bir işi bitirince), asla bir işin ortasında; iki tam ekran
  reklam arası en az 4 dakika. Gösterim ancak reklam gerçekten göründüyse
  sayılır.
- **Ödüllü reklam → 24 saat Pro** (PRO = EVET ise): kurulumdan 7 gün sonra
  açılır; günde en fazla 1 kez; düğme görünür bir yerde (üst çubukta hediye
  simgesi) ve dokununca ne kazanılacağını açıkça yazan bir onay penceresi.
  Ödül yalnızca reklam SONUNA kadar izlenirse verilir; sonuç reklam KAPANINCA
  okunur (`show()` açılınca döner, o an okunursa ödül hep boş gelir).
- Reklam yüklemeleri onay ve SDK başlatma tamamlanmadan istenmez (erken istek
  sessizce hiç yüklenmez). Önyükleme "istek gönderildi" değil "yüklendi ya da
  başarısız oldu" anlamına gelir; sınırlı süre bekler.
- **Önce onay:** AB/İngiltere için Google UMP onay formu; iOS'ta ATT izni. SDK
  bunlardan SONRA başlatılır. Onay reddedilirse uygulama çalışmaya devam eder
  (kişiselleştirilmemiş reklam).
- Google AdMob ve Apple reklam politikalarına tam uyum: yanıltıcı yerleşim yok,
  kazayla tıklatma yok, içerikle karışan reklam yok; uygulama çocuklara yönelik
  değilse "Families" kapsamına girilmez, yönelikse o kurallar uygulanır.
- Reklam birimi kimlikleri `--dart-define` ile; repoda yalnızca test kimlikleri.
- iOS: `Info.plist`'e `GADApplicationIdentifier`, `SKAdNetworkItems` ve ATT
  açıklama metni eklenir. Android: AdMob uygulama kimliği manifest'e derleme
  ayarından gelir.

---

## 6. VERİ

### 6.1 YEREL (VERİ = YEREL ise; ayrıca her durumda cihaz içi kurallar)
- Veriler yalnızca cihazda: yerel veritabanı (sqflite / drift) + küçük ayarlar
  için SharedPreferences. Hesap, sunucu, analiz ve çökme raporlama SDK'sı YOK.
- Kalıcılık: bellekte tek kaynak + debounce'lu tam kayıt; hiçbir ayar
  kaybolmaz; uygulama arka plana giderken bekleyen kayıt diske yazılır.
- Veritabanı şema sürümü ve göç (migration) testleri; eski sürümden gelen
  kullanıcının verisi korunur.
- Hassas veri varsa veritabanı şifrelenir (ör. `sqlcipher_flutter_libs`),
  anahtarı güvenli depoda (bölüm 1.4).
- Native tarafta (servis, alarm, widget) bir kopya gerekiyorsa uygulamanın kendi
  kopyası kazanır ve açılışta native'e yeniden gönderilir; native'in gerçekten
  çalışan durumu (ör. arka planda açılıp kapanan bir servis) açılışta okunur.
- Veri dışa aktarma kullanıcının kendi dosyasıdır; içe aktarma doğrulanır.

### 6.2 BULUT (VERİ = BULUT ise; YEREL ise bu bölümü atla)
- Sunucu anahtarları ve yönetici erişimi uygulamada DEĞİL, sunucuda. Uygulama
  yalnızca kullanıcıya özel, kısıtlı erişim belirteci taşır.
- Kimlik doğrulama sağlam bir hizmetle (ör. Firebase Auth / Supabase Auth);
  şifre uygulamada saklanmaz.
- Veritabanı erişim kuralları (Firestore Security Rules / Supabase RLS) her
  kullanıcının yalnızca kendi verisine erişeceği şekilde yazılır ve test edilir;
  "herkese açık okuma/yazma" asla.
- Yalnızca HTTPS; kritik uç noktalarda sertifika sabitleme (pinning) düşünülür.
- Sunucuda istek sınırlama (rate limiting) ve girdi doğrulama.
- **Hesap silme** uygulama içinden yapılabilir ve web'den de istenebilir
  (Google Play ve Apple zorunluluğu); silinen hesabın verisi gerçekten silinir.
- Çevrimdışı çalışma: yerel önbellek (6.1) + bağlantı gelince eşitleme; çakışma
  kuralı belirlenir.
- KVKK / GDPR: veri minimizasyonu, açık rıza, veri indirme ve silme hakkı;
  gizlilik politikası ve mağaza formları bulut kullanımına göre güncellenir.
- Bulut hizmetlerinin yapılandırma dosyaları bölüm 1.1'e göre repoya girmez.

---

## 7. MAĞAZA VE POLİTİKA UYUMU (Google Play + Apple App Store)

- Uygulama her iki mağazanın güncel politikalarına uyar; her yayından önce
  kontrol edilir.
- **Gizlilik politikası:** herkese açık bir web sayfası (ör. GitHub Pages),
  uygulamada ve mağaza sayfasında bağlantısı. Play "Veri güvenliği" formu ve
  Apple "Gizlilik etiketleri" gerçeğe uygun doldurulur (reklam SDK'sının
  topladıkları dahil).
- **Hassas alanlar (sağlık, beslenme, finans, hukuk vb.):** tedavi, tanı,
  iyileştirme, hastalık önleme ya da garanti sonuç vaadi YOK; bilimsel her iddia
  kaynağıyla (yayın künyesi) uygulamada gösterilir; "tıbbi cihaz değildir /
  uzman tavsiyesinin yerini tutmaz" türü feragat belirgin yerde; Play'in ilgili
  beyanları (ör. Sağlık uygulamaları) ve Apple'ın ilgili kuralları (ör. 1.4.1)
  eksiksiz uygulanır. Kanıtla desteklenmeyen hiçbir iddia mağaza metnine de
  yazılmaz.
- Mağaza metni ve ekran görüntüleri uygulamada olmayan hiçbir şeyi vaat etmez;
  platformda mümkün olmayan özellik (ör. iOS'ta yapılamayan bir şey) vaat
  edilmez. Ekran görüntüleri çalışan uygulamadan alınır.
- Yaş derecelendirmesi ve içerik anketi doğru doldurulur.
- Android: güncel `targetSdk`; ön plan servisi varsa doğru tür ve Play beyanı;
  arka plandan ön plan servisi başlatma Android 12+'da reddedilebilir, bu yüzden
  tek bir korumalı yardımcı fonksiyon üzerinden, try/catch ile başlatılır;
  kısıtlı izinler (ör. pil muafiyeti isteği) yalnızca politikanın izin verdiği
  durumda.
- iOS: `Info.plist`'te gereken tüm açıklama metinleri; Apple'ın dış bağlantı ve
  satın alma kurallarına uyum; Sign in with Apple, başka bir sosyal giriş varsa
  zorunludur (bulut).
- Sürümleme: `pubspec.yaml` sürüm + derleme numarası her yüklemede artar;
  `CHANGELOG.md` tutulur.

---

## 8. KALİTE

- Mimari: clean architecture (`core / domain / data / presentation`),
  Riverpod. Kurallar (reklam politikası, Pro durumu, hesaplamalar) saf ve
  platformdan bağımsız.
- Her commit'te `flutter analyze` temiz ve `flutter test` yeşil. Reklam
  kuralları, Pro durumu, kalıcılık, çeviri eksiksizliği ve iş mantığı birim
  testli; önemli hatalar için regresyon testi (düzeltme geri alınınca başarısız
  olan test).
- Erişilebilirlik: ekran okuyucu etiketleri (bir kez okunur, kontroller
  dokunulabilir kalır), kaydırıcılar neyi ayarladığını söyler, en az 48dp
  dokunma alanı, büyük yazı ölçeğinde (1.3x) taşma yok, yeterli kontrast.
- Tablet ve yatay ekranda düzen bozulmaz (içerik genişliği sınırlı).
- Çökme yok: izin reddi, ağ yokluğu, mağaza hatası, bozuk dosya anlaşılır
  mesajla karşılanır.
- **SÜRÜM (release) derlemesi mutlaka emülatörde/cihazda çalıştırılıp uçtan uca
  denenir.** R8/ProGuard, yansıma ile bulunan sınıfları silebilir (ör.
  WorkManager'ın Room veritabanı) ve sürüm APK'sı açılışta çöker; debug'ın
  çalışması yeterli değildir. Gereken keep kuralları `proguard-rules.pro`'da.
- Android doğrulaması yerel emülatörle yapılır; "cihaz gerekli" bahanesi yok.
  Doğrulanamayan her iş, nedeni ve test adımlarıyla PROJECT_BRAIN.md'ye yazılır.
- Performans: açılış hızlı; gereksiz yeniden çizim yok; büyük listeler
  tembel yüklenir.
- CI (GitHub Actions): `flutter analyze`, `flutter test`, `gitleaks`, sürüm APK
  derlemesi.

---

## 9. ÇALIŞMA ŞEKLİ

- Proje durumu, hedef, mimari, görevler ve kararlar tek dosyada:
  **PROJECT_BRAIN.md** (project-brain protokolü). Her görev doğrulanıp
  kapatılır; atomik commit; push.
- Yolda bulunan her yeni sorun görev olarak eklenir; o an yapılan işten
  sapılmaz.
- Belirsizlikte en güvenli seçenek seçilir ve gerekçesiyle kaydedilir. Geri
  dönüşü olmayan işlemler (force-push, veri silme, yayına alma, lisans
  değişikliği) için proje sahibine sorulur.
- Proje sahibi kullanıcıya dürüst bilgi verilir: yapılmayan ya da
  doğrulanamayan şey "yapıldı" diye raporlanmaz.
