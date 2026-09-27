# napp_app_template

CrazyPenguin (XPersPective) icin yeni Flutter uygulaması şablonu.

## Yeni uygulama açma

1. Bu şablonu klonla: git clone https://github.com/XPersPective/napp_app_template.git yeni-uygulama && cd yeni-uygulama
2. Kurulum betiğini çalıştır:

   dart run tool/new_app.dart      --name "Uygulama Adı" --package com.crazypenguin.uygulama      --ads yes --pro yes --data local      --source-icon assets/brand/example_source_icon.png

3. Betik: flutter create (güncel android/ios), platform ayarları (AdMob,
   R8 keep, yalnızca HTTPS, yedekleme kuralları, imza), pubspec'e seçilen
   napp paketleri (git etiketine sabitli), PROJECT_BRAIN.md bölüm 0 tablosu,
   ikon üretimi ve analyze/test/release-build doğrulaması yapar.

Kural kaynağı: ORTAK_UYGULAMA_STANDARDI.md. Çalışma protokolü: AGENTS.md
→ PROJECT_BRAIN.md. Lisans: GPL-3.0. Uygulama adı ve logosu markadır;
lisansa dahil değildir.
