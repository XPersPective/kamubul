# Sunucuda ilan toplama ve Qwen bütçesi

## Mekanik önce — PB-027
Her saklı belge önce kaynak alanları ve başlıklı tablo sütunlarıyla ayıklanır.
Derece, aday/sınav sayısı, sıra numarası ve tekrarlanan aynı tablo toplam
kontenjana katılmaz. Eksik/sayısı okunmayan pozisyon varsa satırların ara toplamı
ilan toplamı diye yayımlanmaz. Kaynakta yazan başvuru tarihi ve saati korunur;
sınav, belge teslimi veya yayım tarihi son başvuru yerine kullanılmaz.
Göreli gün hesabı ve birden fazla pozisyon takvimi tek kesin tarihe indirgenmez.

Yeterlilik denetimi eksik alanları kaydeder. Mekanik bilgiler AI kuyruğunu
beklemeden küçük sunucu partileriyle yayımlanır. Yalnız eksik belgeler Qwen'e
saklı tam metinle gider. Metin/model/sözleşme önbelleği ve iki deneme tavanı
korunur; aynı ilana kullanıcı tıklaması ayıklama veya kaynak isteği başlatmaz.
AI şartı başka tablo satırından alınamaz. Geçerli fakat kısmi yanıt kalıcı
`extraction.status=partial` olarak görünür; sınırsız yeniden inference yapılmaz.

Tek kanonik payload `quota`, `deadline`, `requirementGroups`, `fieldEvidence`,
`applicationPeriods` ve `extraction` alanlarıyla kart/ayrıntı/offline eşitliğini
sağlar. AI katkısı varsa uygulama “Yapay zekâ ile ayıklandı; hata olabilir.” der.
Koşul grubu sayısı kişi sayısı değildir; bilirkişi listesinde bilinmeyen kontenjan
bilinmiyor kalır. Her pozisyonun tam kaynak koşulu ve ilanın özgün metni saklanır.

Gerçek regression corpus: workers/test/fixtures/ilangov-details.json (yedi
resmî ilan). Sabancı1, Ahi Evran27/15, Bakanlık5, TİBU7, Eskişehir5 kontenjanları
mekanik doğrulanır. Ahi göreli süre ve Eskişehir farklı takvimleri açık kısmi
bilgidir; kesin tarih uydurulmaz.

## Sorumluluk
Kaynak → Cloudflare kaynak işi → D1 tam metin → paylaşılan ayıklama → API →
SQLite → ayrıntı/Asistan. Telefon resmî kaynakları otomatik okumaz; yalnız
kullanıcının açtığı resmî başvuru bağlantısı kaynağa gider.

## İlanı AI'dan ayır
- Önce kaynak listesindeki bütün native kimlikleri kaydet. Ayrıntı veya AI
  kuyruğu bitmeden liste görünür; farklı URL'ler kurum/tarih benzerliğiyle elenmez.
- Sayfa cursor'u D1'de kalır. ilan.gov.tr gerçekte 20 kayıt döndürür; 100 istense
  bile 20 verir. Cursor 20 ilerler. Eksik/tekrarlanan/değişmiş snapshot başarılı
  tam liste olarak yayımlanmaz; önceki katalog korunur.
- Ayrıntı kuyruğu sürerken de kaynak listesi30 dakikada yenilenir. Tamamlanan
  ayrıntı cursor'u korunur; yeni native kimlikler hemen listeye eklenir.
- HTML tablo satırları `hücre | hücre` biçiminde, paragraf sınırlarıyla saklanır.
  Kariyer genel metni ve her kadronun ayrı metni birlikte korunur.
- Model hatası/kota/boş koşullar tam metni silmez. API ve offline cache aynı
  metni gösterir. Veri henüz yoksa durum açık gösterilir; telefon boşluğu doldurmaz.

## Çağrı ekonomisi
- Kaynağın açık yapısal alanları (kimlik, tarih, il, kontenjan, kadro) doğrudan
  kullanılır. Qwen yalnız serbest metindeki şartların ayıklanmasını yapar.
- `qwen3.6-flash`, thinking kapalı, JSON çıktısı. Normalize metin + istem/model
  sürümü D1 cache anahtarıdır; cihaz/kullanıcı/yenileme bu anahtara girmez.
- Kabul edilen120.000 karaktere kadar metnin tamamı Qwen'e gider; içeride
  yeniden60.000 karaktere indiren gizli kesit yoktur.
- Geçerli Qwen sonucu bir çağrıda saklanır; kaba eksik-sözcük kontrolü aynı
  metni tekrar okutmaz. Bozuk/hatalı çağrı için mevcut iki-deneme tavanı korunur.
- Ayrı, her parçaya AI özet üretme işi üretimde kapalıdır. Tam metin okunur;
  ayıklanan alanların kaynak alıntıları gösterilir.
- Ayıklama günlük150/saatlik30, global400 fiziksel çağrı; Asistan mevcut ayrı
  global/kurulum sınırlarında. Bunlar kredi miktarı garantisi değildir.
- Provider input/output/cached token sayaçları kişisel metin olmadan D1
  `assistant_usage/tokens:{extract|assistant}:{input|output|cached}` içinde
  tutulur. Kredi dönüşümü plan konsolundaki gerçek tüketimle karşılaştırılır;
  otomatik yükseltme veya farklı ücretli sağlayıcı açılmaz.
- Qwen resmî dokümanı Credits tüketimini model/token/thinking/tool kullanımına
  göre dinamik tanımlar; sabit “mesaj başına kredi” hesabı verilmez.
  [Token Plan belgesi](https://docs.qwencloud.com/token-plan/personal/token-plan-personal-overview)

## Dayanıklı işler
- Kaynak, ayıklama, eşleştirme ve gönderim mevcut Queue + D1 lease/generation
  protokolünü paylaşır. Kaynak zinciri en az15 saniye bekler; her invocation
  bir ayrıntı okur. Başarılı ayrıntı6 saatte güncellik denetimine girer.
- Kaynak hatasında önceki başarılı metin korunur; iki başarısız onarım sonrası
  6 saat cooldown ile yeni sınırlı bölüm mümkündür. Süresiz kilit yoktur.
- AI kota/hata alan ilan `conditions_due_at` ile ertelenir; diğer ilanların
  sırasını kapatmaz. Günlük Queue3000 işi tavanında backlog D1'de kalır.
- İlk snapshot bildirim üretmez. Unknown koşul kesin uygunluk/push sayılmaz.
- Yerel100/1000/10000 alıcı kontrolü çalıştırılabilir: `node tool/check-fanout.js`.
  10.000 örneğinde3000 günlük Queue görevi7996 gönderim işini tamamlar,
  2004 iş dayanıklı bekler. Bu gerçek Cloudflare CPU/FCM teslim kapasitesi
  veya bütün kullanıcılara aynı gün gönderim garantisi değildir.

## Asistan
İndirilen tam metin ile soru ve gerekli profil alanları sunucuya gönderilir.
Sunucu kaynak URL'sine gitmez. Uzun metinde soruya ilişkin bölümler deterministik
seçilir (en fazla8000 karakter); ilk bölüm ve sonlardaki ilgili kadrolar seçilebilir.
`partial=true` modelin kesit dışındaki bilgiyi “ilanda yok” saymasını engeller.
Bu sözcük eşleştirmesinin bilinçli sınırıdır; kesin uygunluk kararı verilmez.

## Yayın kapısı
`npm test`, `flutter test`, `flutter analyze`, imza/16KB/native kontrolleri ve
gerçek kaynak sayı/tam-metin karşılaştırması gerekir. HTTP200 health bütün
kaynakların tamamlandığı anlamına gelmez. Bütün kaynak metni kanıtlanmadan
server-only mobil sürümü için eksiksiz üretim kabulü verilmez. Son açık
"Google Play'i gönder" talimatıyla bu bekleme kapısı yayın gönderimini
engellemez; code14 üretim incelemesinde ve dahili testte kullanılabilir.
Eksik kaynak kapsamı/kalite görevleri yayın sonrası açık tutulur.
