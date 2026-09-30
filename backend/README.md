# KamuBul arka ucu

Arayüzsüz servis: resmî kaynakları günde ~3 kez çeker, şart alanlarını çıkarır (deterministik + isteğe bağlı yapay zekâ), katalog anlık görüntüsünü yayınlar ve kullanıcının kayıtlı aramalarına uyan yeni ilanlar için FCM bildirimi gönderir. Hesap yoktur. Uygulama yalnızca `/v1` API'sini bilir.

**Google öncelikli, her yere taşınabilir:** aynı Docker imajı Cloud Run'da (Firestore + FCM) ya da herhangi bir VPS'te (dosya deposu) çalışır. Depolama ve bildirim, `Storage` ve `PushSender` arayüzlerinin arkasındadır.

```
Cloud Scheduler ─► Cloud Run Job (/app/job)  ─► Firestore (anlık görüntü + cihazlar)
                     kaynaklar → birleştir → ayrıntı/AI → yayınla → eşleştir ─► FCM
Firebase Hosting (CDN) ─► Cloud Run Service (/app/server)
      /v1/listings.json · /v1/sources.json · /v1/health · PUT|DELETE /v1/devices/{id}
```

## API

| Uç | Açıklama |
| --- | --- |
| `GET /v1/listings.json` | Sürümlü (`schema: 1`) katalog. `ETag` + `If-None-Match` → `304`. `Cache-Control: public, s-maxage=300` ile CDN'de önbelleklenir. |
| `GET /v1/sources.json` | Kaynak başına durum: `ok`, `failed`, `blocked`, `disabled`, son deneme/başarı, not. |
| `GET /v1/health` | Canlılık ve anlık görüntü yaşı (`ageSeconds`). Yaşa alarm bağlayın. |
| `PUT /v1/devices/{id}` | Bildirim aboneliğini oluştur/güncelle. `Authorization: Bearer <gizli anahtar>`. |
| `DELETE /v1/devices/{id}` | Aboneliği sil ("bildirim verilerimi sil"). |

Cihaz kimliği (32 hex) ve gizli anahtar (64 hex) **cihazda rastgele üretilir**. Sunucu yalnızca anahtarın SHA-256 özetini saklar. Kayıt yalnızca FCM jetonu, saat dilimi farkı, sessiz saatler, günlük tavan ve etiket süzgeçlerini taşır (bkz. `packages/kamubul_core/lib/remote/device_registration.dart`). Yazma uçları IP başına saatte 30 istekle sınırlıdır, gövde 32 KB'ı aşamaz, süzgeç anahtarları beyaz listelidir, 120 gündür güncellenmeyen kayıtlar silinir.

## Yapay zekâ (isteğe bağlı, varsayılan KAPALI)

İlan başına **bir kez** çağrılır (kullanıcı sayısından bağımsız maliyet). Sağlayıcı sunucu ayarıdır: `AI_PROVIDER=anthropic|openai|gemini`. `openai`, taban adresi ayarlanabilir OpenAI uyumlu uçtur (OpenAI, OpenRouter, kendi modeliniz). Anahtar yalnızca sunucuda (Secret Manager) durur; uygulamaya girmez.

- Model yalnızca **aday** üretir. Bir alan üç kapıdan geçmeden girmez: katı şema, alıntının kaynak metinde **birebir** bulunması ve değeri desteklemesi, güven eşiği. Geçemeyen alan "belirtilmemiş" kalır.
- Özet maddeleri de doğrulanmış alıntıya bağlıdır; alıntısı bulunamayan madde atılır. Uygulama özeti "Yapay zekâ özeti" diye etiketler.
- **Alanlar (`AI_FIELDS`) ölçüm geçilene kadar kapalıdır.** `packages/kamubul_core` içinde `dart run tool/eval_ai.dart --limit 10` (gerçek çağrı yapar, para harcar) her alanı altın etiketlere karşı ölçer; precision ≥ 0.95 çıkan alanlar açılabilir. Özet (`AI_SUMMARY=1`) alıntı kapısıyla korunur.
- `AI_BUDGET_TOKENS` çalışma başına token tavanıdır; dolunca AI çağrıları durur, deterministik akış sürer.
- Model kimlikleri için sağlayıcının güncel dokümanına bakın; örnek `.env.example` içinde.

## Google'da kurulum (öncelikli yol)

> **Not:** Aşağıdaki komutlar Google dokümantasyonuna göre yazıldı ve bu ortamda **çalıştırılıp doğrulanmadı** (bu oturumda Google Cloud erişimi yoktur). İlk dağıtımda çıktıları birlikte doğrulayın. Uygulamanın kendisi (sunucu, iş, testler) yerelde derlenip çalıştırıldı.

1. Firebase/Google Cloud projesi açın, **Blaze planına** geçin ve **bütçe uyarısı** ekleyin (ör. 5 $).
2. API'leri açın: `run`, `firestore`, `cloudscheduler`, `artifactregistry`, `cloudbuild`, `secretmanager`, `fcm`.
3. Firestore'u Native modda oluşturun. `firebase deploy --only firestore,hosting` (bu klasörden; `.firebaserc.example` → `.firebaserc`). Kurallar istemci erişimini tamamen kapatır.
4. Servis hesabı: `roles/datastore.user`, `roles/firebasecloudmessaging.admin`, `roles/secretmanager.secretAccessor`.
5. İmaj: `gcloud builds submit --config backend/cloudbuild.yaml --substitutions=_IMAGE=<bölge>-docker.pkg.dev/<proje>/kamubul/backend:latest .` (depo kökünden).
6. Hizmet: Cloud Run servisi `kamubul-api` (`/app/server`, `--allow-unauthenticated`, `--max-instances 3`), ortam: `STORAGE=firestore PUSH=fcm GCP_PROJECT=<proje>`.
7. İş: Cloud Run Job `kamubul-job` (`--command /app/job`, aynı ortam + `PROBE_SOURCES=1`, `--max-retries 1`). Cloud Scheduler'dan `08:00`, `13:00`, `18:00` (`Europe/Istanbul`) tetikleyin. İş, hiçbir kaynak okunamazsa **1 ile çıkar**: Cloud Run başarısızlık alarmı bağlayın.
8. Firebase Hosting `/v1/**` isteklerini `kamubul-api` servisine yönlendirir (`firebase.json`); GET yanıtları CDN'de önbelleklenir.
9. Uygulamada FCM: Firebase konsolundan `google-services.json` (Android) ve `GoogleService-Info.plist` (iOS) indirilir, **repoya girmez** (`.gitignore` kuralları var). iOS push için APNs anahtarı Firebase'e yüklenir (Apple Developer hesabı).
10. Uygulama derlemesine sunucu adresi verilir: `--dart-define=KAMUBUL_API=https://<proje>.web.app`.

## Taşınabilir kurulum (VPS, ör. Türkiye)

`deploy/docker-compose.yml` iki servis çalıştırır (`api`, `worker`) ve bir birimi paylaşır. `STORAGE=file` Google hesabı istemez. Önüne `deploy/Caddyfile` ile TLS koyun. `PUSH=fcm` yine Google/Apple altyapısından geçer (mobil push için başka yol yoktur) ve servis hesabı anahtarı ister (`GOOGLE_APPLICATION_CREDENTIALS`); `PUSH=log` yalnızca deneme içindir. `SCHEDULE_TIMES` boş değilse `worker` kendi zamanlayıcısıyla çalışır (Türkiye saati).

Google'dan taşımak: `STORAGE=firestore` → `file` değişikliği yalnızca ortam değişkenidir; uygulama tarafı yalnızca `KAMUBUL_API` adresini değiştirir. Cihaz kayıtları taşınmaz: uygulama her açılışta kaydı tazelediği için yeni sunucuya kendiliğinden yeniden kaydolur.

## Sınırlar ve dürüst notlar

- **Kaynak erişimi:** İŞKUR ve ilan.gov.tr WAF/oturum arkasındadır; `PROBE_SOURCES=1` her çalışmada yalnızca herkese açık ana sayfaya **tek anonim GET** atar ve sonucu `sources.json`'a (engel/erişilebilir) yazar. Oturum, CAPTCHA ya da WAF aşılmaz. SBB yurt dışı IP'leri engelleyebilir; Google Cloud'da Türkiye bölgesi yoktur (planlı, 2028–2029). İlk gerçek çalışmanın kaynak durumu, hangi kaynakların sunucudan çekilebildiğinin kanıtıdır.
- **Ölçek:** Cihazlar her çalışmada bir kez taranır (günde 3 × cihaz sayısı okuma; 10 bin cihazda Firestore ücretsiz günlük okuma kotasının içinde). ~15 bin cihazı aşınca kuyruklu cihazları ayrı bir indekse alın.
- **Yeniden dağıtım:** İlanları bu API'den yayınlamak, kaynağın kullanım şartlarına tabidir (TD-002); yayın öncesi kaynak başına doğrulanmalıdır.
- **Bildirim garantisi yok:** FCM/APNs teslimatı en iyi çabadır. Geçici gönderim hatasında bildirim cihaz kuyruğuna döner; çökmede bekleyen bildirimler bir sonraki çalışmada yeniden gönderilir (kayıp yerine az tekrar).
- **Gizlilik:** Sunucu yalnızca anonim kimlik, FCM jetonu, tercihler ve etiket süzgeçlerini tutar. Uygulamadaki "bildirim verilerimi sil" `DELETE /v1/devices/{id}` çağırır. `PRIVACY.md` ve mağaza beyanları yayın öncesi güncellenmelidir.

## Yerel çalıştırma ve test

```sh
cd backend
dart pub get
dart test
DATA_DIR=/tmp/kb PROBE_SOURCES=1 dart run bin/job.dart    # bir kez çek (kaynak erişimi gerekir)
DATA_DIR=/tmp/kb PORT=8080 dart run bin/server.dart       # API
```
