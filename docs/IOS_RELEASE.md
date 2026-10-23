# iOS yayın hazırlığı

Durum (23 Ekim 2026): iOS mağazaya gönderilmedi. Bu belge, depodan doğrulanan boşlukları ve yayın için gereken dış girdileri listeler. İmzasız derleme `.github/workflows/ios-build.yml` ile doğrulanır; sonuç henüz okunmadı.

## Hesap ve imza (kullanıcıya ait)
- Apple Developer Program üyeliği (yıllık ücretli; GitHub Actions ücretsizliği bunu kapsamaz).
- App Store Connect'te `com.crazypenguin.kamubul` için uygulama kaydı.
- App Store Connect API anahtarı (.p8, Key ID, Issuer ID) ve dağıtım imzası. Sırlar GitHub Secrets'a konur, depoya girmez.

## Depoda doğrulanan boşluklar
- `ios/Flutter/AdsConfig.xcconfig` Google'ın **test** AdMob uygulama kimliğini içeriyor; iOS için gerçek AdMob uygulaması/reklam birimleri yok (`app-ids.env` yalnız Android kimlikleri içerir). Test reklamlarıyla mağazaya gönderilmez; ya iOS AdMob kimlikleri alınır ya da iOS'ta reklam kapatılır.
- Pro aboneliği `in_app_purchase` ile; iOS'ta App Store Connect'te abonelik ürünü ve StoreKit testi gerekir (Apple kural 3.1.1). Ürün yoksa Pro iOS'ta gizlenmelidir.
- FCM bildirimi için Firebase iOS uygulaması (`GoogleService-Info.plist` değil, dart-define ayarı kullanılıyor) ve APNs anahtarı ile Push Notifications yeteneği gerekir; `Runner.entitlements` yok.
- `kamubul/calendar`, `kamubul/reminders`, `kamubul/device` kanallarının iOS karşılığı yok. Dart tarafı `MissingPluginException` yakalıyor; takvim düğmesi iOS'ta hata mesajı gösterir. Gizlenmeli veya EventKit ile uygulanmalı.
- `Info.plist` içinde izin açıklaması anahtarı yok; takvim/bildirim özelliği eklenirse gerekir.
- `stores/app-store/metadata` ve `screenshots` boş. iOS ekran görüntüleri iPhone simülatöründen üretilmeli (Android görüntüsü kullanılmaz).
- Gizlilik "beslenme etiketleri", yaş derecelendirmesi, ihracat uyumu ve inceleme notları App Store Connect'te doldurulmalı.
