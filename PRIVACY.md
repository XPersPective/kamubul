# KamuBul gizlilik açıklaması — geliştirme sürümü

KamuBul hesap oluşturmaz. Uygulama resmî kamu iş ilanlarını okur; kayıtlı aramalar, yer imleri, bildirim geçmişi ve tema tercihi cihazda saklanır ve yedek olarak dışa aktarılabilir. Bu sürümde kullanıcı profili veya asistan konuşması sunucuya gönderilmez. Uygulama kaldırıldığında yerel veriler silinir.

## İlan kataloğu

Sunucu adresi ile derlenen sürümlerde uygulama, ilan listesini KamuBul sunucusundan (Google Cloud üzerinde) okur. Bu istek yalnızca herkese açık ilan verisini ister; kullanıcı bilgisi göndermez. Sunucu, resmî kaynaklardan (ör. Kariyer Kapısı, Kamu İlanları) yalnızca herkese açık ilan sayfalarını okur. İlan metninden kısa özet ve şart alanları çıkarmak için sunucu bir yapay zekâ hizmeti kullanabilir; bu hizmete yalnızca **herkese açık ilan metni** gider, hiçbir kullanıcı verisi gitmez. Yapay zekâ özetleri uygulamada "Yapay zekâ özeti" olarak etiketlenir.

## Sunucu bildirimleri (isteğe bağlı, varsayılan kapalı)

Ayarlardan "Sunucudan anlık bildirim" açılırsa ve bildirim izni verilirse, uygulama sunucuya şunları gönderir: cihazda rastgele üretilen anonim bir kimlik ve gizli anahtar (sunucu yalnızca anahtarın özetini saklar), bildirim jetonu (FCM/APNs), saat dilimi farkı, sessiz saat ve günlük bildirim sınırı ile bildirimi açık kayıtlı aramaların süzgeç değerleri (şehir, kategori, yaş, eğitim, KPSS türü gibi). Ad, e-posta, telefon veya konum toplanmaz. Bu veriler yalnızca yeni ilanları aramalarınızla eşleştirip bildirim göndermek için kullanılır; reklam veya profil çıkarma için kullanılmaz.

Bildirimlerin teslimi Google (Firebase Cloud Messaging) ve Apple (APNs) altyapısından geçer. Kayıt, 120 gün boyunca güncellenmeyen cihazlar için otomatik silinir. Anahtarı kapattığınızda kaydınız sunucudan silinir (bağlantı yoksa bağlantı geldiğinde silinir).

## Reklam ve satın alma

Ücretsiz sürümde kullanılan Google Mobile Ads ve onay bileşenleri reklam/izin amaçlı veri işleyebilir; ayrıntılar yayın öncesinde Google beyanları ve mağaza gizlilik formlarıyla tamamlanmalıdır. Pro etkinse uygulama reklam başlatmamayı hedefler. Gerçek satın alma mağaza altyapısı üzerinden gerçekleşir; KamuBul kart bilgisi saklamaz.

Bu metin geliştirme sürümü içindir. Yayın öncesi mağaza gizlilik beyanları (Google Play Veri Güvenliği, Apple gizlilik etiketleri) sunucu bildirimi ve sunucu tarafı veri işlemeye göre güncellenecektir. Kaynak kodu ve hata bildirimi: https://github.com/XPersPective/kamubul
