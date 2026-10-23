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
- Genel Flutter214/214, core223/223 ve analyze komutları başarılı çıktı; bu sırada kaynak değiştiği için eski otomasyon turu doğru olarak FAIL/stale kaydetti. Güncel kabul yerine kullanılamaz.
- Son kesin kaynak genel check PASS: Flutter214/214, core223/223, hedefli analyze temiz; digest4c6202f0240095db. Eski otomasyon logları devralınmadı. Dört golden yeniden doğrudan incelendi, visual criterion513659 kanıtlandı.
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

## Boot denemeleri — kabul başarısız / açık

- `integration_test/qa_deadline_boot.py`: yalnız QA5556/AVD adı, kurulu APK SHA256 ve public fixture durumu doğrulanır; başka cihaz/veride abort. Saat/izin/kısıt değiştirmez. Önce fixture-only kalıcı gelecek planı yazar, gerçek reboot yapar, AlarmManager ve NotificationRecord bekler. Sonunda yalnız kendi fixture'ını off geri yükler ve QA paketini durdurur. Bu yardımcı home/save/tap testi değildir.
- İlk denemede boot property1 görüldüğünde hemen alarm aranması erken bulundu: ActivityManager cleanup force-stop10:42:09.868, PostingBOOT_COMPLETED10:42:10.623. Test artık gerçek alarmı60s bekler. Bu hata uygulama boot bug'ı diye yazılmadı.
- İkinci deneme yine alarm restore gözlemedi. Sistem PostingBOOT_COMPLETED10:44:11.872, completion10:45:06.857; uygulama başlangıcı/alarm kanıtı yok. İki deneme FAIL olarak korundu: `evidence/SA015_BOOT_FIRST_FAIL_2026-10-16.log`, `evidence/SA015_BOOT_SECOND_FAIL_2026-10-16.log`. Her iki deneme kendi fixture durumunu off/plans[] olarak temizledi; bildirim kalmadı.
- Cihaz usage readback: KamuBul bucket50/never, used ve usedByUser uninitialized; stopped=false tek başına normal kullanıcı açılışını kanıtlamadı. Script bu durumu artık reboot öncesi reddeder. Bunun başarısız restore'un kesin nedeni olduğu doğrulanmadı; gerçek normal lib/main.dart APK açılışı ve UI kullanımıyla tekrar gerekir. Normal APK hash'i doğrulanmadan scriptin pinned integration hash'i yeni dosyaya çevrilmez.
- Bağımsız read-only review: hedef/APK/veri sınırları uygun; restore+aynıIDtag notification+sent birlikte gerçek gözlenirse receiver-only kanıt geçerli. amstart integration harness'ini çalıştırırsa fixture ile yarışabilir; boot sonrası tam eşitlik bunu yakalar. Uygulama koduna testin geçmesi için kısıt aşımı eklenmedi.
- Android kaynakları boot yayınını ve durdurulan uygulama davranışını ayrı tanımlar: [Android15](https://developer.android.com/about/versions/15/behavior-changes-all#enhanced-stop-states), [AOSP broadcast constants](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/am/BroadcastConstants.java). Bunlar bu cihazda başarının yerine geçmez.
- Son sabit kaynak genel check a0652e4f06ab08d6 PASS:Flutter214/214,core223/223,analyze. Normal lib/main.dart x64 debug derleme283s PASS; C: arşiv app-normal-debug-20261016.apk SHA25695661E4A19AC32BFC5047C845776ECE669E2D053641BF819F9A9B2B0EB48FD8F. İlk kurulum denemesi cihaz boot property boşken başarısız oldu; mevcut QA cold boot'u sürüyor. Bu APK integration entrypoint içermez, ancak debug/QA yapısıdır; üretime gönderilmedi ve henüz cihaz/UI kabulü yapılmadı.
- Sonraki kurulum SUCCESS, launcher BrokenPipe32; screenshot yalnız Google boot logo. Crash buffer SYSTEM PROCESS WifiHandlerThread NetworkMonitor/DeadObjectException, ardından SystemUI/phone DeadSystemException gösterdi; appPID/ilkframe kanıtı yok. Bunun app bug'ı veya kesin RAM nedeni olduğu söylenmedi. AVD kayıtlı2G ayarı yerineCLI1536 kullanıldığı görüldü; yalnız kendi emülatörümüz durdurulup normal2G ile yeniden başlatıldı. Sistem crash logu .tmp/sa015-qa-system-crash.log, ekran .tmp/sa015-normal-first-frame.png. Henüz normal app/boot PASS yok.
- Kalıcı platform kanıtları: `evidence/SA015_QA_SYSTEM_CRASH_2026-10-16.log`, `evidence/SA015_QA_BOOT_SCREEN_2026-10-16.png`. Ekran bir app ilk frame'i değildir. Yeni2G QA parent67468/qemu36104; boot-property ve bootanim-stopped kontrolü17791 devam ediyor. Normal APK tekrar derlenmedi veya kurulum başarısından sonra kör tekrar gönderilmedi.
- Son2G denemesi: OS_READY17791, kurulu normal hash95661E4A doğrulandı. AppPID2044 ve standby bucket10; gerçek Onboarding/Atla/Devam UI etiketi görüldü. SystemUIANR Wait seçeneğinden sonra çıktı, uyarı yeniden açıldı; home geçişi/ilk katalog/save kabulü yok. `evidence/SA015_QA_SYSTEM_UI_ANR_2026-10-16.png` bu durumu gösterir. Yalnız kendi QA emülatörümüz kapatıldı; başka proje5554/Java süreçleri korunur.
- Yapılandırma sınırı: normal debug komutunda KAMUBUL_API verilmedi; source remote_sync.dart default boş olduğu için uzak katalog kapalı. Bu APK prod/release veya tam katalog testi sayılmaz. Boot helper fixture-only ve integration APK pinli kalır; gerçek API yapılandırılmış normal paket + kararlı OS + gerçek kullanıcı yolu gerekir. Eksik kabulü gizlemek için varsayılan sunucu veya app kodu değiştirilmedi.
