# Sunucuda ilan toplama ve Qwen bütçesi

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
- HTML tablo satırları `hücre | hücre` biçiminde, paragraf sınırlarıyla saklanır.
  Kariyer genel metni ve her kadronun ayrı metni birlikte korunur.
- Model hatası/kota/boş koşullar tam metni silmez. API ve offline cache aynı
  metni gösterir. Veri henüz yoksa durum açık gösterilir; telefon boşluğu doldurmaz.

## Çağrı ekonomisi
- Kaynağın açık yapısal alanları (kimlik, tarih, il, kontenjan, kadro) doğrudan
  kullanılır. Qwen yalnız serbest metindeki şartların ayıklanmasını yapar.
- `qwen3.6-flash`, thinking kapalı, JSON çıktısı. Normalize metin + istem/model
  sürümü D1 cache anahtarıdır; cihaz/kullanıcı/yenileme bu anahtara girmez.
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
server-only mobil sürümü üretime gönderilmez.
