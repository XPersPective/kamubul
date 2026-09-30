# KamuBul native Dart backend — geçiş referansı

Bu klasör önceki native Dart sunucunun kaynak/test referansıdır; **Cloudflare Worker değildir ve yeni dağıtım yolu değildir**. Güncel hedef Cloudflare Workers Free + D1 + Free Workers AI + Firebase FCM; [Project Brain](../PROJECT_BRAIN.md) ve [geçiş yol haritası](../docs/CLOUDFLARE_FCM_YOL_HARITASI.md) geçerlidir.

Cloud Run/Blaze/Firestore/Hosting, VPS ve Docker dağıtım reçeteleri/konfigürasyonları aktif ağaçtan kaldırıldı. İhtiyaç halinde Git geçmişinden incelenir; çalıştırılmaz. Firestore adapter ve Google OAuth runtime hâlâ referans kodda; hedef depolama D1. Yeni Worker uygulaması henüz yok.

## Geçişte yeniden kullanılacak kanıt

- `packages/kamubul_core`: parser/model/extraction evidence+eval, v1 snapshot/device kayıt formatları, matcher/planner örnekleri; Flutter da bu paketi kullanır.
- `lib/src/api.dart`: mevcut GET /v1/listings.json, /v1/sources.json, /v1/health ve PUT|DELETE /v1/devices/{id} davranışları, auth/body validation tests.
- `lib/src/pipeline.dart`: source merge/detail/AI/publish/send referansı. Content revision/outbox/cursor ve Free Worker sınırlarına uygun sayılmaz; current.md riskleri geçerli.
- `test/`: native davranış tabanı, Worker parity fixtures için başlangıç. Mock FCM veya Firestore testi gerçek hizmet kanıtı değildir.

Runtime/process/direct file storage/Google metadata OAuth Worker'a aynen taşınmaz. Minimum TS/JS Worker ve shared JSON conformance fixtures PB-016; authoritative ingestion+AI PB-017, match/FCM PB-018. PB-019 cutover ve parity tamamlandıktan sonra kullanılmayan legacy kod silinir; ortak mobil package körlemesine silinmez.

## Güvenli yerel doğrulama

```sh
cd backend
dart pub get
dart analyze
dart test
```

Yerel pipeline/sunucu çalıştırılacaksa yalnız dosya deposu ve `PUSH=log`, AI kapalı test fixture kullanılır; gerçek kaynak/AI/push komutu geçerli user scope ve kotalarla ayrıca yürütülür. Burada bulut deploy reçetesi yok. Private key/client config veya token repoya konulmaz.
