# SA-015 — Yerel hatırlatma kabul kaydı

## Durum

Uygulama kodu ve otomatik kontroller hazırlanıyor; üretime gönderilmedi. Native cihaz, yeniden başlatma, bildirim dokunuşu ve TalkBack kabulü tamamlanmadan özellik bitmiş sayılmaz.

## Uygulama

- Core `deadlineReminderPlan`: kayıtlı/kesin/aktif ilan, yaklaşık üç gün önce Türkiye09:00;22–08 sessiz saat, expiry ve iptal denetimi.
- `DeadlineReminders.kt`: kullanıcı tercihi ve public ilan planları backup dışında AtomicFile; platform inexact alarmı, teslimde izin/kanal/expiry/sessiz saat kontrolü, kalıcı duplicate anahtarı. Yeni exact alarm izni veya sunucu favori verisi yok.
- `home_page.dart`: yerel okumalar ve native uzlaştırma ayrı sıralı Future zincirleri; save/unsave, katalog yenileme, açılış/resume. Ayarlar elle denetimi aynı `_refresh` akışını kullanır.
- Ayarlar: ayrı opt-in, native teyit edilen durum, açık izin/kanal/hata metni; başarısız kullanıcı isteğini otomatik okuma temizlemez. Yeniden dene aynı açık/kapalı isteğini tekrarlar.

## Bağımsız kod incelemesi

`review_reminders` yalnız okuma yaptı. Dört ilk bulgu: ayarlar denetiminden sonra eski alarm, latest-wins okumanın açık kayıtlı arama sheet'ini eski bırakması, kapalı Android kanalında gönderilmiş kaydı, retry düğmesinin açma isteğini tekrarlamaması. Ek yarış: hata readback'i sırasında resume'ın retry niyetini kaybettirmesi.

Tümü kodda düzeltildi; son bağımsız okuma somut ek hata bulmadı. Bu sonuç görev kabulü veya Android runtime PASS değildir. Widget testindeki `Completer`, hata readback'ini bekletip resume'ı araya sokar; ardından gerçek retry düğmesine basılır. Ayarlar elle denetimi de native uzlaştırma sayacıyla denetlenir.

## Kanıt ve sınırlar

- İlk düzeltmede saved_search_edit + ui_list_scale19/19 PASS.
- Genel Flutter214/214, core223/223 ve analyze komutları başarılı çıktı; bu sırada kaynak değiştiği için Store Automation turu doğru olarak FAIL/stale kaydetti. Güncel kabul yerine kullanılamaz.
- Son kesin kaynak genel check PASS: Flutter214/214, core223/223, hedefli analyze temiz; digest4c6202f0240095db. Loglar `.store-automation/runs/SA-015-20261016T101606Z-1.log`, `101839Z-2.log`, `101843Z-3.log`. Dört golden yeniden doğrudan incelendi, visual criterion513659 kanıtlandı.
- Önceki debug x64 derlemesi başarılı; C:/Users/rubicon/.codex/builds/kamubul-sa015-debug-artifact/app-debug-20261016.apk korunur. Son kanal/kapasite/readback düzeltmelerini içermez; release adayı değildir.
- Kullanıcının temizleme isteği: `flutter clean` başarılı, D boş alan1,851,244,544 ->3,467,694,080 byte (yaklaşık1.62GB kazanç). Pub get mevcut lock ile başarılı; dependency eklenmedi.
- Cihaz denemesi yalnız özel `kamubul_sa015_qa` AVD / emulator-5556; başka projenin emulator-5554 cihazına müdahale edilmedi.

## Açık kabul

Tam home/save/unsave/revision akışının native planla uçtan uca kabulü, reboot restore, sıcak/soğuk dokunuş -> cached ayrıntı, gerçek kanal/izin kapatma ve keyboard/TalkBack açık. Aşağıdaki native fixture testi bu kapsamın yalnız bir bölümünü kanıtlar. Inexact alarm Android tarafından geciktirilebilir; teslim garantisi verilmez.

## Android çalışma kanıtı — son test

- Güncel integration hedefi x64 debug derleme461.6s başarılı; yalnız QA5556 üzerine kuruldu. `flutter test integration_test/deadline_reminders_test.dart -d emulator-5556 --no-pub --no-uninstall`:1/1 PASS,33s. Kalıcı on/off, bozukHTTP URL reddi,501plan için `reminder_capacity`, duplicate/revizyon/boş liste sözleşmesi ve exception kontrolleri geçti. Ham native fixture testi bütün home/save akışını tek başına kanıtlamaz.
- Testin30s penceresinde doğrudan `run-as ... cat no_backup/deadline-reminders.v1` gözlemi: enabled=true,nextId=4,plans=[],sent=[{url:https://www.ilan.gov.tr/ilan/sa015-device-test,expires:1792232944789}]. Aynı anda dumpsys gerçek `NotificationRecord` gösterdi: package=com.crazypenguin.kamubul,id=3,tag=kamubul.deadline,channel=kamubul_deadlines,importance=3. Bu paragraf canlı tool gözleminden aktarılmıştır; sonradan dosyaya alınmaya çalışılan ilk durum artık off olduğundan teslim dosyası diye kullanılmadı.
- Test sonunda doğrudan readback: enabled=false,plans=[]; aktif KamuBul NotificationRecord yok. `evidence/SA015_NATIVE_OFF_2026-10-16.json` son durumdur; `evidence/SA015_NATIVE_2026-10-16.log` gerçek build/test çıktısıdır. Sent anahtarı bilinçli korunur.
- Flutter harness sonunda paketi stopped=true yapıyor. Bu durum reboot kabulü olarak kullanılamaz; gerçek boot kabulünden önce normal kullanıcı açılışı/uygun test fixture'ı gerekir. Reboot/tap ve gerçek izin/kanal kapatma ile keyboard/TalkBack kabulü hâlâ açık.
- Test sonrası build/ dizini yoktu; nedeni doğrulanmadı. Son APK yalnız QA5556 üzerinde kurulu uygulamanın `pm path` çıktısından C:/Users/rubicon/.codex/builds/kamubul-sa015-debug-artifact/app-integration-debug-20261016.apk konumuna alındı. Bu integration entrypoint içerir, üretim veya mağaza adayı değildir.
- Arşivdeki integration APK SHA256: B0BC202C0186FA22F3DF0BDCC2B95E092758DEBEFA5A5B68AD228B226175FD74 (88,927,684 byte). `.dart_tool/package_config.json` da yok; sonraki Flutter çalışması pub get gerektirir. Kaynak dosyaları b3ffa0e içinde korunur.
