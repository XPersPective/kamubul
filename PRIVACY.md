# KamuBul gizlilik açıklaması

Son güncelleme: 4 Ekim 2026. KamuBul, crazypenguin tarafından geliştirilen bağımsız bir ilan uygulamasıdır; hesap veya giriş istemez. Kayıtlı aramalar, yaş/KPSS gibi kriterler, yer imleri ve tema tercihi cihazda saklanır. Sunucu bildirimlerini açmadığınız sürece kayıtlı aramalarınız KamuBul sunucusuna yüklenmez. Bu açıklama mevcut Cloudflare/FCM sürümünü anlatır; mağaza beyanlarının tamamlandığı anlamına gelmez.

## İlan kataloğu

Uygulama ortak ilan kataloğunu Cloudflare üzerindeki KamuBul API'sinden okur. Katalog isteğine kişisel arama kriterleri eklenmez; eşleştirme cihazdaki önbellekte de yapılır. Cloudflare bağlantıyı sağlarken IP adresi ve istek zamanı/URL/durum gibi teknik verileri işleyebilir. Kurulum kayıt isteklerinde kötüye kullanımı sınırlamak için IP ve saatten üretilen hash sayacı kullanılır; süresi dolan sayaçlar sınırlı bakımda temizlenir. Uygulama günlüklerine gizli anahtar, bildirim jetonu veya kişisel kriter yazılmaz. Bu sürüm Firebase Analytics veya Crashlytics kullanmaz.

Sunucu resmî ilan kaynaklarını merkezi olarak kontrol eder. Kaynağın başvuru bağlantısını açtığınızda ilgili sitenin uygulamaları geçerlidir. Erişilemeyen ayrıntılar kesin bilgi gibi gösterilmez.

Bu geçiş sürümünde cihazdaki kaynak kontrolü de korunmaktadır; telefon resmî ilan sitelerine doğrudan bağlanabilir. Bu bağlantılarda ilgili kaynak IP adresinizi ve teknik istek bilgilerini işleyebilir. Kaynak kontrolüne kişisel arama kriterleri eklenmez.

## Sunucu bildirimleri (isteğe bağlı, varsayılan kapalı)

Ayarlardan “Sunucudan anlık bildirim” seçeneğini açıp gerekli izni verdiğinizde sunucuya şu veriler gönderilir:

- Rastgele kurulum kimliği, kimlik doğrulama için gizli anahtar, FCM bildirim jetonu ve Android/iOS platform bilgisi. Sunucu anahtarın yalnız hash'ini saklar.
- Bildirimi açık aramaların kimlikleri, sizin verdiğiniz **arama adları**, kriterleri ve anlık/özet bildirim tercihi. Kriterler doldurduğunuz şehir, eğitim, meslek/kurum, serbest sözcük, yaş/referans tarihi ve KPSS türü/puanı/yılı gibi değerleri içerebilir.
- Sessiz saatler, günlük bildirim sınırı ve son kayıt güncelleme zamanı. Mobil kayıt isteği cihazın saat farkını da taşır; mevcut sunucu bildirim takvimi Türkiye saatini kullanır.

Ad, e-posta, telefon veya GPS konumu için profil alanı yoktur. Ancak arama adına ya da serbest sözcüğe yazdığınız kişisel bilgiler, o aramanın bildirimi açıksa aramayla birlikte gönderilir. Bu alanlara hassas bilgi yazmayın. Veriler ilan eşleştirme, bildirim gönderme ve size ait bildirim geçmişini sunmak için kullanılır; reklam hedeflemek için kullanılmaz.

İş kayıtları Cloudflare D1'da tutulur. Cloudflare Queue mesajı yalnız görev türü ve nesil numarası içerir; kişisel kriter veya jeton taşımaz. Bildirim Google Firebase Cloud Messaging üzerinden, iOS'ta Apple APNs altyapısıyla iletilir. Mesaj ilan başlığı, ilan kimliği/bağlantısı ve olay kimliği içerir. Teslim cihaz izni ve işletim sistemi koşullarına bağlıdır. Sağlayıcının kendi veri uygulamaları [Firebase gizlilik açıklamasında](https://firebase.google.com/support/privacy) yer alır.

## Saklama, silme ve yedekler

Sunucu bildirimi anahtarını kapatmak yerel tercihi kapatır; sunucudaki kurulum, arama ve ilişkili bildirim kayıtlarının silinmesini ister. Bağlantı yoksa silme bekler ve uygulama sonraki bağlantıda yeniden dener. Bu sürede daha önce iletilmiş bir mesaj gelebilir. KamuBul kaydının silinmesi, sağlayıcıların teknik kayıtlarının aynı anda silindiği anlamına gelmez.

120 gün güncellenmeyen kurulumlar otomatik temizlemeye uygun olur; sınırlı bakım ve devam eden işlem kilitleri nedeniyle temizlik tam 120. günde bitmiş olmayabilir. Tamamlanmış bildirim içerikleri 90 gün sonra sınırlı bakımda küçültülür. Tekrar gönderimi önleyen kimlik/durum kayıtları kurulum silinene kadar kalabilir. Bekleyen işler bu içerik temizliğiyle atılmaz. “Bildirim geçmişini temizle” cihazdaki görünümü temizler; sunucu kurulumunu silmek için sunucu bildirimi kapatılır.

Cihazdaki arama/yer imleri dışa aktarılabilir; dosyanın saklanması ve paylaşılması sizin kontrolünüzdedir. Kurulum gizli anahtarı dışa aktarma dosyasına eklenmez; güvenli cihaz deposunda tutulur. Android yedek/cihaz aktarım kuralları bu depoyu dışlar. Uygulamayı kaldırmak sunucuya silme isteği göndermez; kaldırmadan önce sunucu bildirimini kapatabilirsiniz. Aksi halde stale-kurulum temizliği uygulanır.

## Yapay zekâ

İlan işleme için Cloudflare Workers AI'ya yalnız herkese açık ilan metni, başlığı veya resmî ilan PDF belgesi verilir; kullanıcı kriterleri veya bildirim jetonu verilmez. PDF'den metin çıkarılır; taranmış belgede okunabilir metin yoksa bilgi uydurulmaz. Başarılı çıktı ortak katalogda saklanır; aynı içerik her kullanıcı için yeniden işlenmez. Bilinmeyen şart uygunluk onayı sayılmaz. [Workers AI veri açıklaması](https://developers.cloudflare.com/workers-ai/platform/data-usage/) sağlayıcı uygulamalarını anlatır.

### KamuBul Asistan (yapay zekâ sohbeti)

Asistan sekmesinde yazdığınız mesaj, aynı sohbetteki son en fazla 10 mesaj, bir ilan seçtiyseniz o ilanın herkese açık resmî metni ve "Bu ilan bana uygun mu?" karşılaştırması için cihazınızda kayıtlı arama kriterleriniz (yaş ve yaş tarihi, eğitim, KPSS türü/puanı/yılı, il, meslek; salt okunur) KamuBul sunucusu üzerinden yapay zekâ sağlayıcısına (Alibaba Cloud Qwen, OpenAI uyumlu API) yanıt üretmek için gönderilir. Rastgele kurulum kimliği ve IP adresinden üretilen karma yalnızca günlük kullanım sınırı için sayılır; KamuBul mesaj içeriğini ve yanıtı sunucuda saklamaz. Konu dışı mesajlar ve bağlantı/komut içeren mesajlar yapay zekâya hiç gönderilmez. Sağlayıcının veri işleme kuralları kendi gizlilik politikasında yer alır. Mesajlara ad, T.C. kimlik numarası, telefon gibi kişisel bilgi yazmayın. Yanıtlar yapay zekâ ile üretilir ve hatalı olabilir; başvurmadan önce resmî ilanı kontrol edin.


### İlan şartlarının ayıklanması

Cihazınız resmî kaynaklardan okuduğu ilanların şartlarını (yaş, eğitim, KPSS) önce kendi içinde ayıklar. Bunun yapılamadığı ilanlarda, yalnız o ilanın herkese açık resmî metni ve rastgele kurulum kimliği KamuBul sunucusuna gönderilir; sunucu şartları yapay zekâ sağlayıcısıyla ayıklar ve sonucu metnin karma değeriyle saklar ki aynı ilan için tekrar sorulmasın. Bu işlemde kişisel bilgi veya arama kriterleriniz gönderilmez; kurulum kimliği yalnız günlük kullanım sınırı için sayılır.

### Reklamsız deneme süresi

İlk 7 gün reklam gösterilmez. Uygulamayı kaldırıp yeniden kurmanın deneme süresini sıfırlamaması için cihazın bu uygulamaya özgü Android kimliği (ANDROID_ID) cihazda tuzlanıp SHA-256 ile özetlenir; ham kimlik gönderilmez. Sunucu yalnızca bu özeti ve ilk görülme zamanını saklar; başka bir veriyle eşleştirilmez ve reklam hedeflemesinde kullanılmaz.

## Reklam ve satın alma

Ücretsiz sürüm Google Mobile Ads ve onay bileşenlerini içerir; bunlar reklam/izin amaçlı veri işleyebilir. Pro aylık bir abonelik olup abonelik süresince reklam akışını kapatır. Abonelik ve ödeme Google Play altyapısından geçer; KamuBul kart bilgisi saklamaz. Uygulama açılışta aboneliğin hâlâ etkin olup olmadığını yalnız cihazdaki Google Play'den sorar; iptal Google Play > Abonelikler'den yapılır. Gerçek reklam yapılandırmasıyla Google Play Veri Güvenliği ve Apple gizlilik formları yayın öncesinde ayrıca doğrulanmalıdır.

Google Mobile Ads SDK, reklam sunumu, ölçüm ve kötüye kullanım önleme için IP adresi (yaklaşık konum çıkarılabilir), uygulama/reklam etkileşimleri, performans ve tanılama bilgileri ile reklam kimliği/uygulama kümesi kimliği gibi cihaz kimliklerini toplayıp paylaşabilir. Bu, uygulamada Firebase Analytics bulunmadığı açıklamasından ayrıdır. SDK veri aktarımı TLS ile şifrelenir. Android reklam kimliğinizi cihaz ayarlarından sıfırlayabilir veya silebilirsiniz. [Google Mobile Ads veri açıklaması](https://developers.google.com/admob/android/privacy/play-data-disclosure) ve [Google gizlilik politikası](https://policies.google.com/privacy) sağlayıcının uygulamalarını açıklar.

“Diğer uygulamalarım” GitHub'daki ortak uygulama kataloğunu indirir ve cihazda önbelleğe alır. İsteğe kişisel kriter veya kurulum anahtarı eklenmez. Mağaza bağlantısını açarsanız mağazanın uygulamaları geçerlidir.

Gizlilik, destek ve veri silme soruları için [devcrazypenguin@gmail.com](mailto:devcrazypenguin@gmail.com) adresinden crazypenguin ile iletişime geçebilirsiniz. Sunucu kurulumunuzu uygulamadaki sunucu bildirimi ayarını kapatarak silebilirsiniz; sağlayıcıların teknik kayıtları ayrı saklama kurallarına tabidir.
