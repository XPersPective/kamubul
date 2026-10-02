# Bildirim kapasitesi — 2 Ekim 2026

Çalıştırma: `cd workers; node tool/check-fanout.js`. Node native SQLite,
tüm migration'lar ve gerçek `matchEvents` kullanılır. Veritabanı yalnız bellekte;
üretim kaydı, FCM çağrısı, AI veya Cloudflare bağlantısı yoktur.

| Tek yeni ilan için eşleşen kurulum | Matching invocation | SQL execution | En büyük invocation SQL | Yerel wall p95/p99 ms |
| --- | ---: | ---: | ---: | ---: |
| 100 | 11 | 344 | 34 | 16.41 / 16.41 |
| 1.000 | 101 | 3.404 | 34 | 4.31 / 6.06 |
| 10.000 | 1.001 | 34.004 | 34 | 4.91 / 6.32 |

Her kurulum wildcard/instant arama taşır. Her biri için tam bir pending outbox
oluştuğu, cursor'ın tamamlandığı, replay'de duplicate olmadığı ve invocation
SQL sayısının50'yi geçmediği assert edilir. İlk100 run cold-start etkisi taşır.
Bu sayılar D1 rows_read/rows_written, cloud CPU veya cihaz teslimi değildir.
SQL execution sayısı indeks yazma maliyetini ve taranan satırları ölçmez.

Araç `runScheduled`'ı boş veriyle1440 dakika ilerletip gerçek aşama çağrılarını
sayar:480 matching ve456 send slot/gün. Saatlik:59 bakım slotu24 send slotunu
alır. Mevcut `flushOutbox` bir invocation'da bir kurulumun mesajını gönderir;
digest aynı kurulumdaki ilanları birleştirir, farklı kurulumları birleştirmez.

Dolayısıyla tek ilan100/1000/10000 kuruluma uyarsa kusursuz, sürekli dolu
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
