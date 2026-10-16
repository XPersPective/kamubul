# Ürün vaatleri ve kalan kabul kapıları — 16 Ekim

Kullanıcı mağaza yayınından önce uygulamanın kapsamlı incelenmesini/düzeltilmesini, vaatlerini gerçekleştirmesini ve premium kaliteyi istedi (ADR-010). Bu belge durum ayrımıdır; tüm ürünün kabul raporu değildir.

| Kullanıcı işi | Mevcut kanıt | Açık kapı / görev |
|---|---|---|
| İlanı ve koşulları bulma | Flutter cache/sync, kart/ayrıntı, kaynak fallback yasağı ve koşul testleri | Kaynak canlı kapsamı, alan bazlı precision/recall ve örneklem SA-003/004; fixture PASS canlı tüm ilanların doğruluğu değil. |
| Kriter/kadro eşleşmesi | SA-017 aynı kadro AND, alternatif OR, unknown ve sibling şehir testleri; yıl-only filtresi ortak Dart/Worker düzeltmesi | Cihaz/TalkBack ve bağımsız review; yeni Worker deploy canlı config drift uzlaştırılmadan yapılmaz. |
| Kayıt/çevrimdışı/geri dönüş | Flutter favori/tombstone/yarım delta, bildirim route/cache testleri | Güncel release cihazında cold start/uzun ara/izin ret/geri dönüş SA-005. |
| Yeni uygun ilana bildirim | FCM tercih/kayıt/history/dedupe ve API testleri | Worker accepted cihaz teslimi değil; gerçek izin/kapalı uygulama/token/tekrar/bildirim dokunuşu SA-005. |
| Son başvuruyu hatırlama | Tarih rozeti ve ayrı native takvim; otomatik yerel reminder bağlı değil | **Vaat uyuşmazlığı:** izin primer'ı otomatik deadline hatırlatmasını söylüyor. SA-015 gerçek planlama/iptal/boot/sessiz saat/izin kabulünü tamamlamalı. |
| AI ile koşulu anlama | Sohbet/client bağlam ve metin yokken hak tüketmeme testleri | Yanıtın doğruluğu ve uygulama içi raporlama SA-004/024; AI nihai uygunluk kararı değil. |
| Pro satın alma/restore/iptal | Aylık ürün API kaydı ve istemci kodu | İstemci body.tier sunucuda güvenilir sayılıyor: SA-016 açık. Gerçek Play satın alma/restore/yenileme/pending/iptal/geçiş SA-005; ücretli gerçek işlem yapılmadı. |
| İlk7gün ve reklam | Flutter Pro'ya reklam isteği yok/trial/restart kapıları PASS | Gerçek release cihazında7gün sonrası, okuma/başvuru kesintisi, app-open/back stack SA-005. |
| Premium görünüm/erişilebilirlik | Telefon/tablet light/dark1.3x SA-017 görselleri tek tek incelendi; geniş Flutter responsive testleri | TalkBack cihaz kabulü, gerçek performans/Vitals ve görev tamamlama kullanıcı testi açık. Sadece güzel screenshot premium başarısı değil. |
| Başvuru takibi/not | Plan/spec mevcut, yeni özellik yayımlanmadı | SA-018 yerel kullanıcı durumu; resmî kurumun başvuru sonucu gibi gösterilmez. |
| Mağaza vaadi ile ürün eşitliği | SA-025 Türkçe aday ve check scripti; Console eski aday incelemede | SA-021 yeni medya, bağımsız içerik review, ürün kapıları ve public readback sonrası gönderim. |

## Bu turdaki doğrulamalar

- Flutter206/206: golden farkları yeni kriter açıklaması kaynaklıydı; iki tablet top ve iki conditions görseli gözle incelenerek yenilendi. Telefon/tablet filtre görselleri de incelendi. Bunlar test fixture'ları, mağaza medyası değil.
- Worker contracts+pipeline162/162; tüm Worker testleri veya üretim kabulü diye genellenmez.
- Core Dart219/219: Windows komutu cmd.exe ile düzeltildi; mevcut test paketi önbelleği dart pub get ile tamamlandı. Yeni bağımlılık/ürün değişimi yok.
- Flutter hedefli analyze gereksiz test import'u kaldırıldıktan sonra temiz.
- Son task check kaydı ve geçerli digest/contract SA-017 Evidence içinde; bu metin onun yerine geçmez. Gerçek cihaz ve bağımsız reviewer kanıtı eksikse görev açık kalır.

## Çalışma sırası

SA-017 mevcut düzeltmenin kabulü → SA-016/024/003/004 risk sözleşmeleri ve SA-005 cihaz kapılarını yürütülebilir hâle getirme → SA-015/018 kişisel takip → gerekli düzeltmelerin tekrar kontrolü → Türkçe mağaza/görsel/API/public ve yeterli trafik deneyleri. İzin/araç/veri engeli olan görev başka bağımsız işi durdurmaz. Bütün görevler kapanmadan genel tamamlandı iddiası yok.
