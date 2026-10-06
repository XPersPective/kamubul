# KamuBul — Premium Ürün İncelemesi Talimatı

Bu talimat KamuBul'u (Flutter Android uygulaması + Cloudflare Worker sunucusu +
Google Play mağaza sayfası) uçtan uca incelemek içindir. İncelemeyi yapan yapay
zekâ ya da kişi bu metni emir kabul eder; bulguları Project Brain protokolüne
uyarak `.project-brain/tasks/` altına yazar. Böylece sonraki çalışan işi kayıpsız
devralır.

## 1. Rol

Aynı anda şu dört rolde düşün:

1. **Büyük bir şirketin yazılım geliştirme direktörü.** Ürünü yayına çıkmaya
   hazır mı diye değerlendirir. Riskleri iş etkisine göre sıralar ve "çalışıyor"
   ile "kullanıcıya güven veriyor" arasındaki farkı görür.
2. **Kıdemli Flutter/Dart ve Android mühendisi.** Widget ağacı, durum yönetimi,
   performans (kare süresi, yeniden çizim, liste sanallaştırma), erişilebilirlik,
   çevrimdışı çalışma, Play politikaları ve 16 KB sayfa uyumu gibi konulara bakar.
3. **Kıdemli sunucu mühendisi.** Cloudflare Workers, D1, Queues ve Cron
   ortamında veri doğruluğu, ayıklama hattı (mekanik → denetim → Qwen), maliyet
   tavanları, güvenlik (girdi doğrulama, kimlik, kota, sır yönetimi) ve
   gözlemlenebilirliği inceler.
4. **Sanat yönetmeni ve ürün tasarımcısı.** Tipografi, boşluk, renk, hiyerarşi,
   ikon dili, hareket, boş/yükleme/hata durumları ve mağaza görsellerinin hikâye
   anlatımına bakar. Ölçütü "premium" uygulamalardır: sade, güven veren,
   okunaklı, tutarlı ve özenli.

## 2. Kullanıcı ve ürün vaadi

- Kullanıcı: kamuda iş arayan, çoğunlukla orta segment Android telefon kullanan,
  bazen büyük yazı tipi kullanan, uzun resmî metinleri okumaktan yorulan kişi.
- Vaat: "Bütün kamu ilanları tek yerde; bana uygun olanı hızlıca gör, şartlarını
  anla, başvuru tarihini kaçırma."
- İlkeler: Türkçe, yalnız Türkiye; açık/koyu tema; 7 gün reklamsız deneme, sonra
  reklam; Pro ≈ 1 USD + KDV; açık kaynak; yapay zekâ yalnız gerektiğinde, düşük
  maliyetle ve "hata olabilir" ibaresiyle.

## 3. İnceleme alanları ve sorulacak sorular

### A. Veri doğruluğu (en yüksek öncelik)
- Kartta ve ayrıntıda kontenjan, son başvuru, yer, kurum ve pozisyonlar aynı mı,
  doğru mu? Canlı API'den en az 20 ilanı kaynak metinle karşılaştır.
- Ayıklama hattı: Mekanik sonuç ne zaman "tamam" sayılıyor? Yeterlilik
  denetiminde yanlış alarm (ör. "Öğretim Üyesi" kelimesini eğitim şartı sanmak)
  var mı? Qwen yedeği gerçekten devreye giriyor mu, katkısı neden reddediliyor?
- Göreli tarihler ("Resmî Gazete'de yayımından itibaren 15 gün") kullanıcıya
  anlamlı bir tarih olarak sunuluyor mu?
- Kaynak kapsamı: Hangi kaynakta metin yok (ör. Kariyer Kapısı)? Kullanıcı bunu
  boş ekran olarak mı görüyor?
- Yapay zekâ katkısı açıkça etiketleniyor mu?

### B. Ürün akışları (her biri ekran ekran)
1. İlk açılış: açılış ekranı → tanıtım → ana liste. İlk anlamlı içerik ne kadar
   sürede geliyor?
2. Liste: arama, süzgeçler, "Sizin için", kart bilgi yoğunluğu, sıralama,
   aşağı çekip yenileme, boş ve hata durumları.
3. Ayrıntı: en üstte kısa özet var mı? Bilgi hiyerarşisi, pozisyon kartları,
   başvuru takvimi, tam metnin okunaklılığı (tablolar ham `|` olarak mı
   görünüyor?), eylem düğmeleri, yazı boyutu.
4. Kaydedilenler, Aramalarım/kriter editörü, bildirimler.
5. Asistan: kapsam, bağlam, kota, yükseltme önerisi, hata dili.
6. Ayarlar, Pro sayfası, deneme rozeti, reklamların zamanlaması.
7. Diğer uygulamalar (Keşfet): katalog otomatik mi çekiliyor, yeni uygulama
   eklenince güncelleme gerekmeden görünüyor mu?

### C. Görsel tasarım
- Tipografi ölçeği, satır yüksekliği, en az 16 sp gövde; başlıklar tutarlı mı?
- 4/8 dp boşluk ızgarası; kart köşe, gölge ve kenar tutarlılığı.
- Renk: marka mavisi, anlamlı durum renkleri (aciliyet), koyu temada katman
  ayrımı, WCAG AA kontrastı.
- İkonografi tek aileden mi? Ham metin, `|` karakteri, büyük harf blokları
  ekrana çıplak düşüyor mu?
- Mikro etkileşim: dokunma geri bildirimi, geçişler, iskelet yükleme.

### D. Flutter mühendisliği
- Büyük dosyalar (ör. 3000 satırlık `home_page.dart`): sorumluluk ayrımı ve
  test edilebilirlik.
- Ölü kod: sunucuya taşınan telefon tarafı ayıklama ve AI istemcileri,
  kullanılmayan paketler, eski backend dizinleri.
- `setState` kapsamı, liste performansı, `const` kullanımı, ağ hatalarında
  davranış, çevrimdışı önbellek.
- Erişilebilirlik: Semantics, dokunma hedefi ≥ 48 dp, büyük yazı, TalkBack.
- Analiz uyarıları, testler, golden testler.

### E. Sunucu
- Girdi doğrulama, gövde boyutu sınırları, hız sınırlama, kurulum kimliği ve IP
  kotaları, Pro iddiasının doğrulanması.
- Sırlar yalnız Worker Secrets'ta mı? Loglarda kişisel veri var mı?
- Cron/Queue dayanıklılığı, kilit/lease, yeniden deneme, bütçe tavanları.
- Ayıklama önbelleği ve sürümleme: sürüm atlatınca bütçe patlıyor mu?
- Gözlemlenebilirlik: sağlık ucu, hata kodları, kalite sayaçları.

### F. Gelir ve politika
- Deneme yeniden kurulumla sıfırlanmıyor mu? Reklam SDK'sı ve UMP yalnız
  deneme bitince mi başlıyor? Pro satın alma, geri yükleme, iptal.
- Play Veri güvenliği beyanı ile gerçek veri akışı uyumlu mu?

### G. Mağaza sayfası
- Başlık, kısa açıklama, uzun açıklama: fayda odaklı, SEO dostu, Türkçe, abartısız,
  açık kaynak vurgusu.
- Ekran görüntüleri: güncel arayüz mü, başlıklı çerçeveler (hikâye) var mı,
  açık+koyu, özellik grafiği.

### H. Açık kaynak ve depo hijyeni
- README, lisans, katkı rehberi; sırların depoda olmaması; commit'lerde yapay
  zekâ ortak yazar satırının olmaması (kullanıcı kuralı).

## 4. Yöntem

1. Önce Project Brain'i (`current.md`, `target.md`, `constraints.md`, açık
   görevler) oku. Kullanıcının geçmiş geri bildirimleri PB-024/025/027'dedir.
2. Kod incelemesini dosya ve satır kanıtıyla yap (`yol:satır`).
3. Canlı veri kanıtı topla: `/api/v2/listings`, D1 salt okunur sorgular, yerel
   ölçüm betikleri.
4. Mümkünse emülatörde ekran ekran gez. Açık ve koyu temada, küçük ekranda ve
   büyük yazıda dene.
5. Her bulguya önem derecesi ver:
   - **P0**: yanlış veri, güvenlik açığı, çökme, mağaza politikası ihlali.
   - **P1**: kullanıcının ana işini zorlaştıran ya da premium algısını bozan sorun.
   - **P2**: tutarsızlık, cila eksiği, bakım yükü.
   - **P3**: güzel olur.
6. Her bulgu şu biçimde yazılır: **Sorun** (gözlem + kanıt), **Etki**,
   **Öneri** (somut çözüm), **Kabul ölçütü** (nasıl doğrulanacağı).

## 5. Çıktı

- `.project-brain/tasks/PB-028.md`: inceleme raporu ve öncelikli iş listesi
  (Objective, Status, Acceptance, Verification, Decision boundary, Resume notes).
- Kullanıcının yeni geri bildirimleri ilgili görevlere madde olarak eklenir
  (C-052). Hiçbir madde atlanmaz.
- Rapor; sorunu, hedefi ve yapılacakları sonraki yapay zekânın başka kaynağa
  ihtiyaç duymadan anlayacağı açıklıkta yazılır.
- Düzeltmeler öncelik sırasıyla uygulanır. Her biri test edilir, gözden geçirilir,
  commit edilir (ortak yazar satırı eklenmez) ve gönderilir. Rapordaki madde
  ancak kanıtla işaretlenir.
