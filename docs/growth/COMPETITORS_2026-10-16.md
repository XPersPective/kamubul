# KamuBul — rakip saha matrisi

Erişim: 16.10.2026. Öncelik görev benzerliği ve gözlenen sorgu sonuçlarıdır; büyük genel iş uygulamalarının bütün indirmesi kamu ilanı talebi sayılmaz. Android paketleri sabit kimlik; aşağıdaki özellikler aksi belirtilmedikçe geliştirici **beyanı**, cihaz testi değildir. “UNKNOWN” belirtilmeyen özelliğin yokluğu anlamına gelmez. [Resmi kural ve ölçüm tabanı](RESEARCH_2026-10-16.md).

## Bir defalık Play TR web sorgu gözlemi

IAB masaüstü, Türkçe, footer Türkiye (Türkçe); Google hesabı seçilmedi. İlk sorgu `hl=tr&gl=TR`, devamı görünen arama kutusundan. Ham sıralı DOM ve tüm sayfa ekranları `evidence/play-search-*-20261016.*`. Sıra soldan sağa, yukarıdan aşağıya kart sırasıdır; “Play” metni fragman düğmesidir, sponsorlu etiket olarak sayılmadı. İşlem saatleri için dosya kanıtları esas; bu aynı gün anlık örneklem, izleme serisi değil.

| Sorgu | İlk sonuçlar | KamuBul | Sonuç/sınır |
|---|---|---|---|
| kamu ilanları | Kamu Personeli Alımı → SELLSOFT → Gulerkan → Güncel Kamu İlanları → İŞKUR | Görülen 29 kart içinde 10. | Gözlenen alaka var; Türkiye mobil ortalama sıra veya hacim değil. |
| memur alımı | Kamu Personeli Alımı → SELLSOFT → Gulerkan → Kamu Kadro → MemurJet | Dönen 28 kartta yok | Ana niyet boşluğu hipotezi; “hiç indekslenmiyor” veya bir anahtar kelime ekleyince düzelir denmez. |
| kamu iş ilanları | Kamu Personeli Alımı → SELLSOFT → Gulerkan → Onur Altun → İŞKUR | Dönen 12 kartta yok | Başlıktaki tam ifade bile görünmeyi garanti etmiyor; trafik ve kalite kanıtını birlikte ele al. |

Arama motoru Play önbelleklerinde indirme/puan/tarih farklı çıktı. Örnek: İŞKUR için farklı dillerde 1M+/5M+ ve 2,0–2,7; TR canlı arama kartında 4,8. Bu değerler birleştirilmedi; kesin büyüme hızı veya sıralama sebebi çıkarılmadı.

## Ürün ve ücret matrisi

| Ürün / sabit Android kimliği ve kaynak | Teklif ve fark | Giriş / monetizasyon | Ölçek/tarih gözlemi; KamuBul kararı |
|---|---|---|---|
| [Kamu: Memur Alım İlanları — SELLSOFT](https://play.google.com/store/apps/details?id=com.selman.memur_ilanlari&hl=tr&gl=TR) `com.selman.memur_ilanlari` | SBB kaynaklı ilan/PDF; yeni/bugün son/hafta bitiyor; cihazda eğitim-doğum yılı-şehir karşılaştırması; favori, başvuru durumu/not, takvim, koyu tema. MinerU + DeepSeek ile PDF özet alanı. | Açıklama hesap gerektirmez ve tamamen ücretsiz der; mağazada ücretli plan gözlenmedi. Gerçek reklam/Android satın alma UNKNOWN. | Canlı TR: 1K+, 4,7/15 yorum, 6 Ekim. Görev açısından çok yakın ve önceki kısa raporda eksik. Hesapsız veya AI ayıklama tek başına benzersiz değil; son tarih/başvuru takibi bizim açık boşluk. |
| [Kamu Kadro](https://play.google.com/store/apps/details?id=com.kamukadro.app&hl=tr&gl=TR) `com.kamukadro.app`; [web](https://kamukadro.com/), [koşullar](https://kamukadro.com/terms) | Kadro/eğitim/bölüm/puan eşleşmesi; yeni uygun, son tarih ve favori hatırlatması, yalnız uygun kadro görünümü. | Play/web ücretsiz reklamlı, aboneliksiz diyor; Google/Apple hesabı istiyor. Play IAP rozeti ve ilk görselde Premium bildirim yazısı var: çelişki. Güncel Android fiyat UNKNOWN. | Canlı TR: 100+, 5,0/6 yorum, 9 Ekim. Web akademik ilanı dışlar, Play dahil eder; kaynak sayısı da değişir. Kapsam üstünlüğü ilan edilmez. |
| [Atama Bildirim — Techspiration](https://play.google.com/store/apps/details?id=com.techspiration.kamu&hl=tr&gl=TR) `com.techspiration.kamu` | Profil/ilan, filtre, bildirim; mağaza ekranlarında başvuru takibi ve profil tamamlama. | Reklam + IAP rozeti. Android TR aylık/yıllık fiyat UNKNOWN; mağaza fotoğraflarında abonelik başlat CTA'sı var. | Canlı TR: 500+, 4,2/5 yorum, 8 Eylül. [iOS ayrı kaynak](https://apps.apple.com/tr/app/atama-bildirim-kamu-i-lanlar%C4%B1/id6780600221): 49,99 aylık/499,99 yıllık; Android fiyatı diye kullanma. |
| [Atama Bildirim Programı — Kariyer Cepte](https://play.google.com/store/apps/details?id=com.atananben.atama_bildirim_app_final&hl=tr&gl=TR) `com.atananben.atama_bildirim_app_final`; [web](https://atamabildirim.com/) | Profil filtresi, bildirim; Play manuel ilan derleme beyanı. Web puan/sınav takvimi/çalışma planı/notlar/klavye/CV araçları sunar; mobilde hepsi olduğu doğrulanmadı. | IAP; web indirme/bildirim ücretsiz, analiz Premium der. Güncel Android TR fiyat UNKNOWN. 8 Temmuz yorumunda yaklaşık60 TL/ay var; resmi güncel fiyat kanıtı değil. | Canlı TR: 10K+, 4,5/848, 10 Ekim. Aynı ada rağmen Techspiration ile farklı ürün. Destek/dağıtım topluluğu da rakip avantajı olabilir. |
| [Kamu Personeli Alımı](https://play.google.com/store/apps/details?id=com.Kamu.Personeli.Alimi&hl=tr&gl=TR) `com.Kamu.Personeli.Alimi` | İlan/haber/duyuru ve anlık bildirim; uzun resmi kaynak listesi. Detaylı kadro/AI/yerel profil yeteneği UNKNOWN. | Ücretsiz yükleme; yorumlar ve geliştirici reklam olduğunu doğruluyor. Ücretli plan/güncel Android fiyat UNKNOWN. | Canlı TR: 1M+, 4,5/12,4K, 9 Eylül; News & Magazines, sayfada anlık #9 kategori rozeti. Bu toplam kategori ölçeği bizim hedef sorgu sırası değil. |
| [Kamu Personeli Alım — Gulerkan](https://play.google.com/store/apps/details?id=com.kamu.personeli.alim.app&hl=tr) `com.kamu.personeli.alim.app` | Bildirim, resmi kaynak haber/ilan; kişisel eşleştirme/AI UNKNOWN. | Ücretsiz yükleme, ücretli plan ve reklam davranışı UNKNOWN. | Web kaynak: 50K+, 6 Eylül; News & Magazines. Sorgularda ilk üçte görünmesi yalnız yeni akıllı eşleştirme uygulamalarının rakip olmadığını gösterir. |
| [Güncel Kamu İlanları](https://play.google.com/store/apps/details?id=com.mtlive.guncelkamuilanlari&hl=tr) `com.mtlive.guncelkamuilanlari` | Kamu ilanı, otomatik analiz ve günlük bildirim beyanı. | Ücretsiz yükleme; hesap/reklam/ücretli plan UNKNOWN. | Kaynak: 1K+, 13 Eylül2022. Eski güncelleme tek başına kullanılamaz olduğunu kanıtlamaz. |
| [Kadro Radar](https://play.google.com/store/apps/details?id=com.kadroradar&hl=tr) `com.kadroradar` | Resmi Gazete ilanı; kadro, şehir/kurum/unvan/öğrenim filtreleri, tarih/puan/şartlar. | Ücretsiz yükleme; hesap/abonelik/reklam UNKNOWN. | Kaynak: 10+, 20 Haziran; İş. Küçük ama detay/filtre ihtiyacına yakın. |
| [Memurlar.net](https://play.google.com/store/apps/details?id=net.memurlar&hl=tr) `net.memurlar` | Kamu ilanı/haber/maaş/topluluk; marka ve içerik dağıtımı. | Reklam + IAP; Android fiyat UNKNOWN. [iOS ayrı](https://apps.apple.com/tr/app/memurlar-net-maa%C5%9F-ilan-kamu/id1535460924):19,99 aylık/199,99 yıllık; Android'le birleştirme. | Kaynak:1M+, 9 Ağustos; News. Geçmiş 2020/2021 yorumları güncel Android hatası diye yazılmadı. Haber sitesi hacmini kopyalamak daha büyük editoryal kapsam. |
| [Memur365](https://play.google.com/store/apps/details?id=com.memur365&hl=tr) `com.memur365` | Personel alımı ve geniş kamu/gündem haberleri. | Reklam, ücretsiz yükleme; Android ücretli plan UNKNOWN. | Kaynak:100K+,27 Eylül2024; News. Sorgu görünürlüğü var; kişisel şart açıklaması bizim daha odaklı teklifimiz olabilir. |
| [Kamu İş Personel Alımı](https://play.google.com/store/apps/details?id=com.kamuiscomtr.app&hl=tr) `com.kamuiscomtr.app` | İlan/haber/başvuru bilgisi/bildirim. | Reklam; ücretsiz yükleme, ücretli plan UNKNOWN. | Kaynak:500+,9 Haziran2026. Makine eşleşmesi yerine genel içerik teklifi. |
| [İŞKUR Mobil](https://play.google.com/store/apps/details?id=tr.gov.iskur.iskurapp&hl=tr) `tr.gov.iskur.iskurapp` | Resmi kamu/özel iş arama, öneri, başvuru, CV, işveren paneli, yakın işler. | Ücretsiz yükleme, abonelik görünmüyor; resmi işlem akışları hesap gerektirir. | Diller/önbellekler sayısal olarak çelişiyor; gerçek TR anlık indirme bandı bu matriste UNKNOWN. Resmi başvuru yeteneği taklit edilmez; KamuBul resmi kaynağa götürür. |
| KamuBul `com.crazypenguin.kamubul` [Play](https://play.google.com/store/apps/details?id=com.crazypenguin.kamubul&hl=tr&gl=TR) | Hesapsız ilan/kriter/cache; ilan bağlamında Türkçe AI soru-cevap; ücretsiz10/Pro50 soru/gün. Bildirim altyapısı var, uçtan uca cihaz teslim kabulü eksik. | 15Ekim yetkili API:58,99 TL/ay P1M; ilk7gün reklamsız dönem, sonra reklam. Yıllık ürün gözlenmedi. | Canlı TR:5+ indirme,7Ekim/code17; eski sekiz görsel, Pro100/30 hâlâ public. Aday API gönderimi görünür sayfayı henüz değiştirmemiş. |

## Rakipte var / bizde var / savunulabilir farklılaşma

| Kullanıcı işi | KamuBul bugün | Rakip kanıtı | Strateji |
|---|---|---|---|
| Hesap açmadan ilan/favori | Var | SELLSOFT da beyan ediyor; Atama web kayıt zorunlu değil diyor | Sürtünme avantajı; benzersizlik iddiası yok. |
| Kişisel puan/eğitim/şehir filtre ve yeni uygun ilan | Motor ve FCM var; teslim kabulü açık | SELLSOFT/Kamu Kadro/iki Atama beyan ediyor | Beklenen temel fayda. Kriteri kaydetme/izin/kapalı app/dedupe göstergesi birlikte kabul edilmeli. |
| İlan metnine bağlanmış Türkçe soru-cevap | Var; metin eksikse sınırlı | İncelenen sayfalarda aynı sohbet yolculuğu açıkça gösterilmedi; SELLSOFT AI ayıklama var | **Aday fark:** “Bu şart benim için ne demek?” sorusunu kaynakla açıklama. Yokluk araştırması kesin rakipsizlik ispatı değil. |
| Kadro başına uygun/bilinmeyen ayırma | SA-017 geliştirme; code17 için yeni filtre sayılmaz | Kamu Kadro ve SELLSOFT görünüm/beyan | Eşdeğer temel gereksinim; yeni motor yerine mevcut üç durumlu matcher. |
| Otomatik son tarih hatırlatma | SA-015 açık; takvim editörü kaynakta, public binary kabulü ayrı | Kamu Kadro, SELLSOFT, Atama web | Retention için yüksek öncelik; yalnız rozet yeterli değil. |
| Başvuru durum/not | SA-018 açık | SELLSOFT açıklama, Techspiration mağaza ekranı | Küçük yerel veri özelliği; resmi başvuru durumu sanılmamalı. |
| Şeffaf ayıklama/kaynak/bilinmeyen | Alıntı ve tip kontrolü var; precision kabulü açık | Rakipler de PDF/şart hata uyarısı kullanıyor | Kaliteyi örneklem ve hatalı-uygun oranıyla kanıtla; “AI var” yerine güvenilir karar desteği. |
| Çevrimdışı kayıtlı ilan, yazı ölçeği, koyu tema | Var | SELLSOFT koyu tema/offline font beyanı; diğerleri UNKNOWN | Faydayı mağazada net göster; tek başına tüm rakiplere üstünlük değil. |
| Sınav hazırlık/CV/haber | Kapsam dışı/eklenmedi | Atama web, Memurlar ve haber uygulamaları | İlk aşamada ekleme; çekirdek ilan işini daha iyi bitirmek daha az bakım ve daha tutarlı konumlandırma. |

## Kullanıcı sesi: küçük, amaçlı örneklem

Kamuya açık sayfada görünen yorumlar seçilidir, rastgele örneklem değildir. Tarihi eski olanı güncel hata sayma, oran/gelir çıkartma. Kişi adları gereksiz olduğu için burada tutulmadı; tüm alıntılar yerine kısa anlam özeti.

| Kaynak/tarih | Gözlenen tema | KamuBul için doğrulama görevi |
|---|---|---|
| Kamu Personeli Alımı,8Eylül2026 | Geri tuşu sayfadan tüm uygulamaya çıkıyor şikayeti; geliştirici19Eylül düzeltme dedi | Liste→detay→resmi sayfa→geri ve cold notification rotası kaldığı yeri korusun; düzeltilmiş rakip kusuru üstünlük iddiası olmasın. |
| Aynı,7Eylül2026 | Okuma alanını reklam kaplaması şikayeti | 7.gün sonrası ilan okuma/başvuru ve büyük yazı akışında reklam alanını gerçek cihazda gözle. |
| Aynı,9Eylül2026 | İzin verilmesine rağmen bildirim eksikliği | İzin tek başına teslim kanıtı değil; token yenileme/kapalı app/batarya/force-stop ve payload açılışı ayrı. |
| Techspiration,30Eylül2026 | Ücret yüzünden ilana erişemediği/başvuramadığı kullanıcı iddiası | Ücretsiz temel ilan erişimi ve resmi başvurunun nerede yapıldığı açık olsun. Rakibin gerçekten ücretli başvuru aldığı doğrulanmadı. |
| SELLSOFT,23Temmuz/3Ağustos2026 | Tek yerde ilan + bildirim faydası övülüyor | Kullanıcının ilk işi uzun AI sohbetine zorlanmadan ilanı bulmak olabilir; AI-first kreatif test edilmeli. |
| Kariyer Cepte,21Ağustos2026 | Birebir destek ve basit süreç övülüyor | Destek kalitesi ürün değerinin parçası; şikâyeti reddeden kalıp yanıt yerine somut inceleme. |
| İŞKUR TR web önbelleği,29Ağustos/17Eylül2026 | Eksik/eski ilan ve meslek eşleştirme sürtünmesi | Güncel ilan/eksik bilgi ve unknown davranışı görünür; profil eksik diye kullanıcıyı yanlış uygunsuz sayma. |

## Görsel saha gözlemi

Üç doğrudan rakibin gerçek Play görseli açıldı. Kanıt JPEG'leri yalnız bu araştırma kaydıdır; rakip görseli bizim mağazaya taşınmaz. UI/UX rehberindeki okunurluk/kontrast ilkeleri eleştiri desteğidir; Play önizlemesindeki okunurluk ayrıca değerlendirilir, mobil16px kuralı afişe doğrudan uygulanmaz.

| Rakip / kanıt | Gözlem | KamuBul tasarım kararı |
|---|---|---|
| SELLSOFT `sellsoft-listing`, `sellsoft-screen1` | Lacivert/mavi arka plan; ilk görselde yeni ilan faydası + gerçek liste; ikinci bildirim, üçüncü son tarih, dördüncü özet. Küçük kartlarda tüm şart metni okunmuyor ama ana fayda net. | İlk3 görselde bulunabilirlik, kişisel açıklama ve bildirim faydasını kanıtla; karmaşık tam paragrafı küçülterek gösterme. |
| Kamu Kadro `kamukadro-listing`, `kamukadro-screen1` | Kırmızı güçlü marka; ilk ekran kişisel puana eşleşme; hero bildirim. Görselde Premium modu varken açıklama ücretsiz/aboneliksiz diyor. | Görsel/metin/ürün tutarlılığı temel güven kapısı. Mavi KamuBul markasını koru; rakibin kırmızısını kopyalama. Pro CTA koyma. |
| Techspiration `techspiration-listing`, `techspiration-screen1` | Fotoğraflı ofis arka planı ve cihaz çerçevesi; ilk ekran genel kariyer başlangıcı, telefonda büyük abonelik CTA'sı; sonraki profil/ilan/başvuru. | Gerçek okunur ürün kanıtı daha güçlü aday; ofis fotoğrafı veya satış CTA'sı ana faydayı gölgelemesin. |
| KamuBul `kamubul-public-listing`, `kamubul-public-pro` | Public ilk ekran genel liste; AI dördüncü; son ekran 7gün/Pro100-30. Yeni yerel7ekran AI-first set bu sayfa değil. | Önce public yanlış vaadi kaldır ve yeni seti görsel kabulden geçir; sonra AI-first ile ilan-first'i aynı örnek ilan ve aynı görsel kalitede karşılaştır. |

## Fiyat ve görüşme araştırmasını devralma

Şu aşamada gerçek Android TR rakip satın alma ekranları gözlenmedi. Tutar uydurmak yerine paket/sürüm/Google hesabı ülkesi/aylık-yıllık/dahil fayda/yenileme/intro teklifini tek seferlik ekranla kaydet. Satın alma yapma. Kullanıcı yorumundaki60 TL veya iOS49,99 TL, KamuBul58,99 TL'yi değiştirmek için yeterli veri değil. Önce ücretsiz ilanın erişilebilirliği, ücretli faydanın anlaşılması ve güvenli entitlement çözülür.

Beş hedef kullanıcıyla isteğe bağlı saha testi taslağı: (1) belirli şehir/eğitim için ilan bul, (2) bir şartı açıklat ve resmi kaynağı bul, (3) arama kaydet/bildirim aç, (4) son başvuru ve başvuru takibini bul, (5) ücretsiz/Pro farkını kendi sözleriyle anlat. Süre/yanlış anlama/yardım gereksinimini kaydet; kişisel sınav belgesi/kimlik isteme. Bu görüşmeler yapılmış değildir.
