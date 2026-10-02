# Bildirim kapasitesi — 2 Ekim 2026

Çalıştırma: `cd workers; node tool/check-fanout.js`. Node native SQLite,
tüm migration'lar ve gerçek `matchEvents` kullanılır. Veritabanı yalnız bellekte;
üretim kaydı, FCM çağrısı, AI veya Cloudflare bağlantısı yoktur.

| Tek yeni ilan için eşleşen kurulum | Matching invocation | SQL execution | En büyük invocation SQL | Yerel wall p95/p99 ms |
| --- | ---: | ---: | ---: | ---: |
| 100 | 11 | 154 | 15 | 6.11 / 6.11 |
| 1.000 | 101 | 1.504 | 15 | 2.36 / 3.04 |
| 10.000 | 1.001 | 15.004 | 15 | 2.39 / 3.03 |

Eşleştirici sayfanın on kurulum/kriterini tek parametrik JOIN ile okur; enabled,
mode ve abonelik başlangıç seq koşulları aynı snapshot'ta uygulanır. Önceki
ayrı kurulum+arama okumalarında10k34.004 SQL/max34 vardı; şimdi15.004/max15.
Native EXPLAIN kontrolü installations/saved_searches tam taramasını reddeder;
unrelated/unknown/new subscription ve duplicate-facet regresyonları geçer.

Her kurulum wildcard/instant arama taşır. Her biri için tam bir pending outbox
oluştuğu, cursor'ın tamamlandığı, replay'de duplicate olmadığı ve invocation
SQL sayısının50'yi geçmediği assert edilir. İlk100 run cold-start etkisi taşır.
Bu sayılar D1 rows_read/rows_written, cloud CPU veya cihaz teslimi değildir.
SQL execution sayısı indeks yazma maliyetini ve taranan satırları ölçmez.

Gönderim yolu da aynı araçta injected offline sender ile boşaltılır; gerçek
FCM/Google OAuth/cihaz yok.100/1000/10000 kurulum için800/8000/80000 SQL,
max8/mesaj; bütün satırlar accepted ve owner lease'leri boş, drain replay
sender'a yeniden gitmez. Yerel send wall p95/p99 sırasıyla0.83/1.21,
0.74/1.15,1.34/1.78ms. Bunlar ağ ve API gecikmesini içermez.

Önceki10k kontrolü p95 yaklaşık7.52–10.38ms/p99 8.96–15.34ms verdi.
Root cause: pending/leased OR sorgusu tüm uygun kuyruğu temporary sort'a
alıyordu. Yeni compound query iki state'in ayrı indexed LIMIT1 adayını alır,
yalnız bu iki aday sıralanır. Aynı due tarihindeki ID sırası, expired lease
recover ve live lease skip test edilir. Owner atomik UPDATE RETURNING ile
alınır; yalnız busy/missing yolunda ek SELECT gerekir. Pre-FCM opt-out/current
version/cap kontrolü korunur.150 native test ve dry-run geçti.

Üretim D1 readonly EXPLAIN iki outbox_due index search ve bounded subquery
planını doğruladı:0rows_read/0rows_written/changed_db=false. EXPLAIN boş gerçek
kuyruktaki çalışma zamanı/D1 scan sayısını ölçmez. Leased branch canlı lease
satırlarını hâlâ ziyaret edebilir; yüksek consumer concurrency ayrı ölçülmelidir.

Araç `runScheduled`'ı boş veriyle1440 dakika ilerletip gerçek aşama çağrılarını
sayar:480 matching ve456 send slot/gün. Saatlik:59 bakım slotu24 send slotunu
alır. Mevcut `flushOutbox` bir invocation'da bir kurulumun mesajını gönderir;
digest aynı kurulumdaki ilanları birleştirir, farklı kurulumları birleştirmez.

Eski yalnız-Cron yolunda tek ilan100/1000/10000 kuruluma uyarsa kusursuz, sürekli dolu
kuyrukta gönderim üst hızı456 mesaj/gündür. Yalnız gönderim için steady-state
iş yükü sırasıyla0.219/2.193/21.930 gündür. Başlangıç hizası, eşleştirme,
OAuth/FCM hatası, quiet hours/cap ve deadline süreyi etkiler; süresi geçenler
gönderilmez. Bu fiziksel teslim zamanı tahmini veya garanti değildir.

**10.000 kullanıcıya hızlı kişisel bildirim kabulü geçmedi.** Kalıcı outbox ve
idempotency çalışması throughput kanıtı yerine kullanılamaz. Sonraki iş:
Free erişimi doğrulanmış dayanıklı task dispatch/consumer veya ölçülmüş küçük
send batch; gerçek Worker CPU, subrequest/D1 maliyeti, OAuth ve FCM ile kabul.
Kapasiteyi artırmak için limitsiz loop/paid upgrade açılmaz. Mevcut resmi
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/)
Free Cron CPU10ms ve50 subrequest sınırını bildirir; local wall bu CPU değildir.

Queues'ın [güncel fiyatlandırması](https://developers.cloudflare.com/queues/platform/pricing/)
Free günlük10.000 operasyon/24h retention gösterir; write/read/delete normalde
3operasyon ve retry ek read tüketir. Alıcı başına Queue mesajı10k push için
30k normal operasyon oluşturur. Bu yüzden yalnız Queue ekleyerek kapasite
kanıtlanamaz; bounded batch/dispatch bütçesi ve D1 authoritative recovery gerekir.
Kalıcı Queue artık kuruldu/bağlandı; ücretli upgrade yok.

## Bütçeli Queue dispatch — ADR-003

kamubul-work24h retention; Workerb41b6716 producer/consumer1/1 doğrulandı.
Migration0016 dispatch_state(kind,generation,state,lease_until) ve bağımsız
daily_usage.queue_jobs ekler. Mesaj yalnız kind/generation; kişisel veri yok.
Claimqueued→running atomiktir. Max batch1/concurrency1/retry0; send consumer
en çok4instant iş yapar. İlk3'te digest varsa grup durur; dördüncü instant-only
seçilir.6 yeni native test race/duplicate/expired ticket, quota2999→3000,
AI counter korunumu, publish failure recovery ve whole consumer query bütçesi
kontrol eder. Stage veya cleanup D1 hatasında lease recovery ve duplicate
outbox korunumu da test edilir. Toplam156 Worker testi geçti;
runtime dry-run/deploy/live API kontrolü başarılıdır.

3000 task/gün normal9000 Queue operasyonu demektir; platform redelivery/failed
publish ek maliyet/kapasite tüketebilir. İş içerikleri D1'da kalır; lost wake-up,
24h message expiry veya quota sonrası Cron lease expiry ile yeniden dener.
Cron480match/456send slotu ayrıca durur. Shared budget tamamen instant-send
görevlerine ayrılsa teorik12000 recipient/gün işlenebilir; gerçekte matching,
digest/quiet/cap/retry ve CPU aynı bütçeyi etkiler. Tek10k wide-match için
1001match +2500 four-send task=3501task; bu shared3000 limitini aşar ve Cron
katkısına/zamanlamaya bağlıdır.10k anlık/aynı-gün garantisi verilmez.

Çalıştırılabilir araç artık gerçek dispatcher/consumer fonksiyonlarını da aynı
in-memory D1 adaptörü ve injected sender ile sırayla çalıştırır (Cron eşzamanlı
değildir).100/1000 alıcı36/351 görevde tamamen işlendi.10k için günlük3000
rezervasyon sınırı korundu:7996 gönderim ve2004 pending kayıt kaldı; normal
Queue operasyon tahmini9000. Pending+accepted toplamı10k, rezervasyon/görev
sayısı eşit ve her görev ack kontrolü geçti. Bu yerel sonuç gerçek Cloudflare
Queue işlemi, Worker CPU veya FCM teslimi ölçümü değildir.

Son readonly production: dispatchmatch/sendidle generation0, queue_jobs0,
installation1/outbox0. Yeni kurulumun kaynağı/teslimi doğrulanmadı. Consumer
CPU/gerçek Queue işlemi/FCM OAuth/cihaz teslimi henüz gözlenmedi; sahte prod
message/installation/push ile kanıt üretilmedi. Sonraki gate gerçek nonempty
işleme ve operations/CPU ölçümü; Free sınırı aşılırsa grup azaltılır/cache/backlog
korunur. Kalıcı katalog23/46 hâlâ source-only, source detail gate ayrıca açıktır.
