# KamuBul — Bağlayıcı Kısıtlar

## C-053 Sunucu devri — 5 Ekim son kullanıcı yönü
Kaynak okuma ve ayıklama tamamen sunucuda; telefonda otomatik kaynak/şehir/
ayrıntı/backfill yok. Önceki C-040 geçiş fallback korumasını son kullanıcı
yönü değiştirir. Telefon yalnız API/cache ve kullanıcı tarafından açılan
başvuru bağlantısı.5 Ekim son açık "Google Play'i gönder" talimatı code13
üretim gönderimini kaynak kabulünü beklemeden yetkilendirdi; eksik kaynak
kapsamı ve kalite görevleri tamamlanmış sayılmaz.
Qwen3.6-flash mevcut Token Plan ile birincil ayıklama ve Asistan; yapısal
kaynak alanları doğrudan, ayrı parça başına AI özet çağrısı yok. Geçerli
sonuç tekrar okutulmaz; provider Credits'i varsayımsal sabit mesaja çevrilmez.
Kullanıcı Cloudflare erişimini doğruladı; IP/ülke nedeni tahmin edilmez;
gerçek okuyucu/uç nokta sonuçları ve eksik kapsam dürüst kaydedilir.

## C-042 Android ve yayın kökü — 3 Ekim son kullanıcı yönü
Bu çalışma iOS/Mac işlerini erteler; Android emülatör doğrulaması yetkilidir.
Önceki fiziksel Android zorunluluğu bu kapsamda emülatör kabulüyle değiştirilir;
emülatör gerçek telefon/mağaza satın alma kanıtı olarak sunulmaz. AppPublishing
yayıncısı crazypenguin; uygulama sırrı/imzası apps/kamubul/credentials altında,
ortak Play API publisher altında. Kullanıcı kalıcı üretim imzası oluşturma ve
anahtarların bu yapıya taşınmasını açıkça istedi; skill içindeki insan sınırı
bu yetkilendirilmiş hazırlığı yeniden engellemez. Kaynak izin/ücretsiz bütçe,
kişisel veri ve mevcut mağaza imzası koruması sürer; yayın izni varsayılmaz.

30 Eylül 2026. Güncel kullanıcı isteği eski hedeflerin yerini alır. Mevcut davranış current.md, hedef target.md, görevler tasks/.

## C-001 Ücretsiz işletim
2 Ekim kullanıcı istisnası ADR-002: Free AI kotası dolunca kendi harici sağlayıcısı ve ayrıca kriter asistanı kullanılabilir. Sağlayıcı/secret/açık ayrı bütçe sınırları netleşmeden çağrı açılmaz. Aşağıdaki eski ücretli AI/fallback yasağı bu dar kapsam dışında korunur; Cloudflare otomatik upgrade hâlâ yasak.
Cloudflare Workers Free + D1 + Workers AI ücretsiz kotası; Firebase Spark yalnız FCM. Cloud Run, Firestore, Blaze, ücretli AI, ücretli VPS ve otomatik upgrade yok. Kota bitince iş dayanıklı biçimde bekler/cache sunulur; ücret doğuracak fallback açılmaz. 10.000 kurulum kapasitesi ölçüm hedefi, garanti değildir. Model yalnız Free erişimliyse seçilebilir.

## C-002 Sunucu sorumluluğu
Resmî kaynak çekme, ayrıntı/PDF işleme, AI, normalizasyon, kanıtlı koşullar, katalog revizyonu, yeni ilan eşleştirme, instant/digest kararları ve push gönderimi Cloudflare'dadır. Telefon kaynaklara arka planda veya otomatik fallback olarak gitmez. Kaynak engeli açık gösterilir. Resmî başvuru/doküman linkini kullanıcının açması serbesttir.

## C-003 Hesapsız ve veri minimizasyonu
ADR-002 istisnası: kullanıcı kriter asistanına kendi mesajını ve seçtiği aramanın gerekli alanlarını, sağlayıcı açıklanarak gönderebilir. Bütün profil/kurulum secret/FCM token gönderilmez. Ingestion AI kişisel veri almaz. Assistant erişimi FCM iznini zorunlu tutmaz.
Kullanıcı girişi yok; kurulum başına güvenli ID+secret ve FCM token. Profil/favori yerelde; bildirim açılırsa yalnız gerekli kayıtlı kriterler/tercihler sunucuya gönderilir. Kullanıcı tanımlı arama adı kişisel etiket, public global taxonomy değildir. Hiçbir kullanıcı profili AI'ya gönderilmez. Silme/izin kapatma/token yenileme/reinstall davranışı açık; server kaydı 120 gün heartbeat yoksa temizlenir. Kimlik doğrulama secret'ı güvenli cihaz deposunda ve backup dışında.

## C-004 Resmî veri ve çıkarım doğruluğu
Yalnız resmî kaynak; WAF/login/CAPTCHA aşma, arbitrary URL fetch ve gizli proxy yok. Source-native alanlarda type/range/origin; metin/AI alanlarında kaynak alıntısı, şema ve doğrulanmış değer desteği. Alan başına en az 50 örnek/kaynak değerlendirmesi, precision >=0.95 kapısı; recall ayrıca raporlanır. Alıntı tek başına doğruluk ispatı değildir. Unknown = unknown; AI kesin işe uygunluk kararı vermez. Çoklu kadro koşulları birbirine karıştırılmaz.

## C-005 Ekonomik AI
5 Ekim kullanıcı istisnası ADR-006: ingestion koşul ayıklamasında Cloudflare
eksik çıkarımında da ayrı günlük tavanla Qwen destekleyebilir. Sohbet Qwen
kalır. İki çağrı sınırı D1'de içerik/çıkarım/model sözleşmesine bağlıdır;
ücretli otomatik Cloudflare upgrade izni değildir.
ADR-002 kullanıcı kriter asistanı kullanıcı isteği başına ayrı sınırlı inference yapabilir; aşağıdaki notice-revision maliyet ilkesi ingestion içindir. Assistant ve ingestion fallback ayrı atomik bütçe/limit kullanır.
AI yeni veya semantik içeriği değişmiş ilan revizyonu başına; kullanıcı/etiket/refresh başına değil. UI tarih/görüntülenme gürültüsü hash'e girmez. Başarılı sonuç kalıcı; aynı (contentHash, extractionVersion, modelRevision) yeniden çağrılmaz. Başarısız çağrı kontrollü retry yapabilir. Günlük rezervasyon/bütçe, request/input/output/attempt üst sınırı. Yarım işlem veri kaybetmez.

## C-006 Premium ve erişilebilir mobil
Türkçe, tema token'ları, light/dark/system, skeleton, kesilebilir spring motion, geri bildirim/haptic, filtrede sonuç sayısı, okunaklı özet ve alıntılı koşul chip'leri. WCAG AA kontrast, 48dp hedef, TalkBack/VoiceOver, telefon/tablet/1.3x metinde taşma yok. İzin ilk açılışta zorlanmaz. Premium iddiası release cihaz ölçümü gerektirir. Mevcut napp_core/pro/ads ve gelir modeli korunur; Pro'ya reklam isteği yok, okuma/başvuruda fullscreen reklam yok.

## C-010 Offline ve sync güvenliği
D1 authoritative katalog, SQLite cache+favori+profil. Cache hemen gösterilir, API açılış/manual refresh ile fark getirir. Sayfa UPSERT/explicit null/tombstone ve cursor aynı yerel transaction; yarım sync cursor ilerletmez. Server deletion favoriyi yok etmez, unavailable olarak gösterir. Eski v1 cache/arama/favori migration'ı korunur. ETag maliyet azaltır ama Worker request kotasını sıfırlamaz.

## C-020 Secret ve trust boundary
FCM private key/AI key/admin secret APK/Git/Brain/log içinde yok; server Cloudflare Secrets. Firebase client config yetkilendirme değildir. Bound payload/page/arama sayısı, typed whitelist, parametrik SQL, source/redirect allowlist, timeout/backoff, API schema versiyonlaması. Public cevaplarda kurulum/FCM token/kişisel kriter yok; device endpoint private/no-store. Rate-limit erişim kontrolü değildir.

## C-030 Bildirim gerçeği
FCM/OS teslimi best effort; kapalı uygulama bildirim payload'u foreground/data-only ile aynı davranmaz. Force-stop/izin ret/OS kısıtında teslim garantisi yok. Commit önce, outbox sonra, send en son. Timeout belirsiz kabul nedeniyle tam exactly-once garanti edilmez; kalıcı eventId ve client dedupe. FCM kabul = cihaz teslimi değildir. Outbox işi retry/cap nedeniyle sessizce atılmaz. Yeni abonelik eski tüm ilanları push yapmaz.

## C-040 Geçiş ve doğrulama
Eski local fetch yeni backend doğrulanmadan sökülmez; yalnız geçişte tutulur, hedef değildir. Pilot→mobil cutover→eski kod/Workmanager/Google referansı silme. Yeni bağımlılık/abstraction zorunlu değilse eklenmez. Nontrivial logic bir çalıştırılabilir kontrol bırakır. Brain gerçeği hedefmiş gibi anlatmaz; completed/superseded görevler Git'te kalır, aktif ağaçta tutulmaz. Store signing/publishing ve güvenlik erişimi insan sınırıdır.

## C-041 Kalıcı canlı kurulum — 30 Eylül 2026 son istek
3 Ekim son yön: yalnız Türkiye/tr-TR dağıtımı; reklam ve gerçek satın alma
ürünü, Türkçe gerçek ekran görüntüleri ve bir sürüm gönderme kapsamda. Mağaza
yükleme yetkisi vardır; sözleşme/export beyanı action-time onayını kaldırmaz.
Backend/frontend tüm uygulama ve canlı kurulum yetkilendirildi. Son kaynaklar kalıcı üretim Worker/D1 ve gerçek resmî veridir; Hello World/dev kaynakları güvenli cutover sonrası kaldırılır. Demo/fake ilan veya pretend-success sender üretimde yok. Deterministik test fixture'ları yalnız otomatik kontrol içindir. Credential/access grants, geri alınamaz silme ve mağaza işlemlerinde yürürlükteki insan/onay sınırları korunur; tamamlanmayan canlı adımlar açık raporlanır.

## C-050 Kaynak kapsamı — 4 Ekim 2026 kullanıcı kararı
Yalnız kamu ilanları. İŞKUR'dan YALNIZ kamu işyeri ilanı okunur (özel sektör
kapsam dışı); "Kamu" filtresi yoksa İŞKUR hiç okunmaz. Kaynak okuma basit ve
deterministiktir (filtreli liste isteği + kural tabanlı ayrıştırma); yapay zekâ
kaynak sayfalarında gezinmez/arama yapmaz.

## C-051 Ücretli özellik metni — 4 Ekim 2026 kullanıcı kararı
Pro/abonelik metinleri olumlu ve teşvik edicidir; maliyet gerekçesi, "cüzi",
suçlayıcı/rencide edici ifade kullanıcıya gösterilmez (uygulama, mağaza, sürüm notu).

## C-052 Geri bildirim kuyruğu — 4 Ekim 2026
Kullanıcı çalışma sırasında yeni istek gönderirse istek hemen ilgili PB görevine
madde olarak yazılır; yürüyen iş yarım bırakılmaz, yeni madde sıraya girer.
