# KamuBul büyüme yeniden kontrolü — 16 Ekim 2026

Bu kayıt 15 Ekim [rakip/Play denetimini](PLAY_GROWTH_AUDIT.md) tamamlar. Mağaza sırası ve en çok indirme sonucu garanti edilemez; aşağıdaki durumlar gözlem, kod izi veya doğrulanmamış iddia olarak ayrıdır.

## Bugünkü kritik bulgular

| Öncelik | Bulgu | Kanıt / sonuç |
|---|---|---|
| P1 | Play için hazırlanmış yedi ekranın 02/04/06/07 numaralı görselleri 11.10.2026 son tarihli ilan gösteriyor. 06'nın başlığı “Son başvuruyu kaçırmayın”; 16 Ekim'de bu örnek bitmiş. 01/02/05/07'de “Deneme · 7 gün” rozeti var. 03'te kesilmiş üst metin, 04/06'da yinelenen yer bilgisi var. | `D:/AppPublishing/apps/kamubul/stores/google-play/metadata/tr-TR/images/phoneScreenshots/` yedi dosya görsel olarak incelendi. SA-021 yenileme görevi. [Google görsel rehberi](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) fiyat/promosyon ve yanıltıcı tanıtımdan kaçınmayı ister. |
| P1 | Pro sunucu hakkı doğrulanmıyor. | `workers/src/assistant.js` limit için `body.tier === 'pro'` kullanıyor; `lib/data/assistant_client.dart` bu alanı istemciden gönderiyor. Play satın alma jetonunu sunucuda doğrulama ve tekrar oynatma koruması SA-016'da açık. İstemci restore'u mevcut olsa da “abonelik sorunsuz” denemez. |
| P1 | Tam kaynak kapsamı ve ayrıştırma kalitesi kanıtlanmadı. | 15 Ekim health: 212 aktif / 137 complete / 56 partial / 19 metinsiz. İŞKUR HTTP 500, SBB blocked, Kariyer ayrıntı hatası. Mekanik önce + alıntı/şema kontrolleri mevcut; alan başına 50 örnek/kaynak ve precision ≥0,95 kapısı açık (SA-003/004/005). 16 Ekim canlı sayım yeniden okunmadı. |
| P1 | Otomatik kaydedilen ilan son tarih hatırlatması çalışır olarak doğrulanmadı. | `deadlineReminder` ve `markReminded` çağrısız; eski Workmanager işi iptal ediliyor. SA-015. Kriter bazlı yeni ilan FCM akışı var; FCM kabulü cihaz teslimi değildir. |
| P2 | Yayımlanmış mağaza metni ile gönderilen adayın halka açık eşleşmesi henüz doğrulanmadı. | 15 Ekim Play API commit/readback metadata ve görsel hash'lerini doğruladı; [açık Play sayfasının](https://play.google.com/store/apps/details?id=com.crazypenguin.kamubul) arama önbelleği hâlâ eski metni gösteriyor (tarama 13 Ekim civarı). Bu, Google onayı/yayılımı hakkında tek başına kesin sonuç vermez. Console inceleme durumu ve güncel TR public görünümü okunmalı. |
| P2 | Güncel checkout'ın Flutter toplu testi iki golden'da kırmızı. | `flutter pub get` sonrası `flutter test --no-pub --concurrency=1`: 204 geçti, 2 hata (`canonical_tablet_light_1_3x_top`, `canonical_tablet_dark_top`). SA-017'nin sürmekte olan detay ekranı değişikliğiyle ilişkili olabilir; neden ayrı doğrulanmalı. `test/position_filter_test.dart` 7/7 geçti. Worker contracts+pipeline 162/162 geçti. Bunlar gerçek cihaz ödeme/reklam/FCM kanıtı değildir. |

## Rakip ve konumlandırma

| Ürün | Açık sayfada görülen | KamuBul farkı / açık boşluk |
|---|---|
| [Kamu Kadro](https://play.google.com/store/apps/details?id=com.kamukadro.app&hl=tr) | Profil/KPSS eşleştirme, yeni ilan ve son tarih bildirimi, kaydetme, reklam; sayfa ücretsiz ve aboneliksiz olduğunu söylüyor. Giriş için Google/Apple hesabı istiyor. | KamuBul hesap açmadan arama ve AI ile ilan metni açıklaması sunuyor; otomatik son tarih uyarısı rakipte var, bizde henüz yok. Play sayfasındaki “Uygulama içi satın alma” rozeti ile açıklamadaki “yok” ifadesi çelişiyor; gerçek fiyat/işlem doğrulanmadı. |
| [Atama Bildirim Programı](https://play.google.com/store/apps/details?id=com.atananben.atama_bildirim_app_final&hl=tr) | Profil filtresi, bildirim; Play'de 10 bin+ indirme ve uygulama içi satın alma rozeti. Web'de sınav/plan araçları bulunuyor. | Mobil ücretli planın TR fiyatı ve web araçlarının mobil varlığı doğrulanmadı. İlan okuma ve uygunluk açıklamasında derinleşmek daha yakın hedef. |
| [İŞKUR Mobil](https://play.google.com/store/apps/details?id=tr.gov.iskur.iskurapp&hl=tr) | Resmî ilan/başvuru/CV akışları, 5 milyon+ indirme (15 Ekim gözlemi). | Başvuruyu kurumun resmî kanalına bırak; güvenilir kaynak açıklaması ve hesap açmadan inceleme ile ayrış. Ölçek kıyasını aynı dağıtım düzeyi sayma. |
| KamuBul | 15 Ekim yetkili API kaydı: aylık `kamubul_pro_monthly`, TR 58,99 TL; ücretsiz 10/Pro 50 Asistan sorusu/gün. | “Bana uygun mu?” açıklaması güçlü fayda; sunucu hak doğrulaması ve kaynak kapsamı güveni zedeliyor. Rakip Android Pro fiyatları açık sayfalarda doğrulanamadı; tahmin yazılmaz. |

## Mağaza metni ve büyüme kararı

Mevcut [aday metin](STORE_LISTING_CANDIDATE.md) başlıkta “Kamu İş İlanları”, kısa açıklamada Asistan faydası, uzun açıklamada memur/işçi/belediye/akademik niyeti ve bağımsız uygulama uyarısı içeriyor. Anahtar kelime yüzdesi hedefleyerek tekrar eklemek yerine sorguya uygun, doğrulanmış faydayı kullan. İlk görselde AI ve ilan şartları açıklaması güçlü; ücret/Pro/deneme rozeti öne çıkarılmamalı. 06 görseli bugünkü haliyle kullanılmamalı.

[Google'ın sıralama açıklaması](https://support.google.com/googleplay/android-developer/answer/9958766?hl=tr) arama alakasını, teknik kaliteyi, kullanıcı tepkilerini ve bağlamı farklı ağırlıklarla değerlendirir. Belirli kelime veya metinle kalıcı birincilik garantisi yok. Ölçülebilir hedef: Türkiye/tr-TR aynı trafik kaynağında 28 günlük unique Install CTR, gerçek edinim, Android Vitals ve 7/30 gün elde tutmayı izlemek; tek değişkenli görsel deneyi yapmak (SA-007/008/011). Console oturumu olmadığı için bugünkü CTR, Vitals, gerçek abonelik dönüşümü ve sorgu sırası **UNKNOWN**.

## Sıradaki kapılar

1. SA-021: geçmiş tarihli ve promosyon rozetli görselleri gerçek güncel ekranlarla yenile; sonra Play readback ve public kontrol.
2. SA-016, SA-015, SA-003/004/005: abonelik hakkı, hatırlatma, kaynak/alan doğruluğunu gerçek yaşam döngüsüyle kabul et.
3. SA-017'nin iki tablet golden hatasını çöz; ardından Android emülatörde ilk açılış, 7. gün sonrası reklam, restore, bildirim izni/teslim ve çevrimdışı akışı ayrı gözle.
4. Console'dan aynı dönemin edinim/vitals/yorum verisini al; veriye göre mağaza deneyinin kazananını belirle. Bu veri olmadan “birinci olmayı engelleyen her şey çözüldü” denmez.
