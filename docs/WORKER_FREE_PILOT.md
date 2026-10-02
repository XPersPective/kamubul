# Cloudflare Free — gerçek CPU/D1 ölçüm kaydı

2 Ekim 2026. Bu belge kapasite garantisi veya tamamlanmış pilot değildir.
Ölçüm: mevcut üretim kamubul-api / kamubul D1, gerçek resmî RSS kataloğu.
Kaynak ayrıntısı erişimi ve gerçek AI/fanout/FCM CPU kapıları açık.

## Dashboard gözlemi

2 Ekim yaklaşık09:46 Europe/Istanbul hesabın Current plan Free / $0 olarak
göründü. Günlük Workers requests483/100000 idi. Bunlar o andaki sayaçtır,
günün son toplamı değildir. Worker Metrics Last24h / All deployed versions:

| Ölçü | Değer |
| --- | --- |
| Invocations | yaklaşık1.55k |
| Subrequests |754 |
| CPU P50 / P90 / P99 / P999 |2.55 /8.66 /13.35 /13.35ms |
| Exceeded CPU Time Limits |0 |
| Dashboard invocation errors |0 |

Bu pencere farklı deployment ve CLI kontrolünü içerir. Catch edilmiş kaynak
hataları runtime invocation error değildir. Örneğin Kariyer detail522 ve SBB
engeliyle pipeline source_only yayımlarken Cron outcome ok olabilir.

O sırada yalnız aktif6f148686 sürümü filtresi11 invocation/subrequest0/errors0,
CPU P50 1.48ms/P90-P99-P999 3.33ms gösterdi. Bu düşük trafik ve çoğunlukla boş
iş aşamalarıdır; gerçek inference/token signing veya10k eşleştirmeyi ölçmez.

Observability'de gerçek yüksek CPU Cron kaydı: 2 Ekim08:38:16.868GMT+3,
version8f751e87-a893-414e-baed-184becfbbf8e, scheduledTime1790919417,
cpuTimeMs20 /wallTimeMs79028 /outcome ok. Slot modulo3=0 kaynak/expiry/AI
aşamasıdır. O sürüm kaynak başına dört ilan işliyordu. Ölçü sadece detail
fetch'e atfedilemez. CPU rollover ve günlük%10 örnekleme nedeniyle sıfır
limit exception, her isteğin10ms içinde olduğu anlamına gelmez.

## Kaynak iş miktarı değişikliği

Kaynak slotu şimdi bir pending_batch girdisi tüketir; imleç ve mevcut batch
kalıcı korunur.127 native test/dry-run sonrasında canlıya alındı. Cron her
dakika, kaynak slotu her3dk:21 giriş yaklaşık63dk artı tur tamamlanınca30dk
bekleme gerektirebilir. Bu daha düşük iş miktarıdır; CPU kazanımı henüz
aynı kaynak aşaması ölçümüyle doğrulanmadı.30dk ayarı full-refresh SLA değildir.

Geçici diagnostic deployment d8443b8a-e0b5-4df8-a1f6-aafcba6f0d66 sırasında
head_sampling_rate=1 idi; health/meta/listings50/changes50/taxonomy gerçek
GET'leri200 döndü. Bu beş çağrının CPU değerleri kayda alınmadı. Sonra
a2f92b43-b8d8-4ea1-9650-1afa6b4ef5ac ile%10'a geri dönüldü. Yeni üretim
67ad2d7f-2a8e-447e-ad88-93fe33945081 de%10 kullanır; AI model/sürüm pinning
eklenmiştir, CPU ölçümü yapılmış sayılmaz.

## D1 Last24h gözlemi

Mevcut üretim D1 dashboard EEUR chart legend değerleri:

| Ölçü | Değer |
| --- | --- |
| Total/read/write queries |5.78k /4.69k /1.09k |
| Rows read /written |25.88k /1.85k |
| Database size |yaklaşık319kB |
| Tables |14 |

Boş processing lease sorgusu820kez/5.74k rows read/0 written; source due
sorgusu837kez/4.26k rows read; listing recheck606kez/1.21k rows written.
Pencere farklı sürümleri/CLI okumalarını içerir; bu sayılar per-request maliyet
veya10k kullanıcı yük testi değildir. Daha sonraki readonly CLI ölçümünde DB
327680bytes/21 completed processing işi/legacy partial0 idi. O sorgu21read,
0written ve changed_db=false; üretim fixture/ek kaynak oluşturulmadı.

## Erişim ve kalan doğrulama

Onaylı Wrangler OAuth ile readonly telemetry keys endpoint10000/HTTP403
döndü. Scope genişletilmedi, token dosyaya/loga yazılmadı. Mevcut oturumdaki
Cloudflare dashboard okuması kullanıldı; bu erişim başarısızlığını CPU testi
başarısızlığı veya tüm hesabın erişilemezliği diye raporlamayın.

Devamda aynı deployment/aynı kaynak aşaması için cpuTimeMs ölçün; public
GET/auth/parse/hash ayrı, native binding AI/Google OAuth signing/gerçek send ve
eşleşme ayrı ölçülmeli. Boş slotları veya native SQLite test süresini cloud CPU
yerine kullanmayın. Kısa%100 örnekleme gerekiyorsa kota takibi ve sonunda%10
geri dönüş checkpoint'i yapın. Aynı request limits/outcomes/rows counters ve
gözlem penceresini kaydedin; test gerçek kullanıcıya bildirim göndermemeli.

Bir ilan için model REST kalitesi/neurons kanıtı docs/AI_MODEL_PILOT.md'de;
REST/native memory pilot Worker Free CPU veya gerçek kaynak egress değildir.
Önce ayrıntı erişimi/terms, doğrulanmış çıkarım, gerçek fiziksel cihaz ve geniş
fanout kanıtları gerekir.10k kapasite kabulü açık kalır.

Resmî CPU/rollover açıklaması:
[Workers metrics](https://developers.cloudflare.com/workers/observability/metrics-and-analytics/).
Örnekleme:
[Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/).
