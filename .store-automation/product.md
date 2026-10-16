# Product
Status: CONFIRMED

(Project Brain target.md'den 15.10.2026 devralındı; hedef kullanıcı yönergelerinden oluşur. Tam eski metin arşivde.)

## Goal
16 Ekim son ürün önceliği: “bunları yapmadan önce uygulamayı ... düzeltmeni, incelemeni ... vaat ettiği şeyleri yapıyor mu ... Premium ... görseliyle her şeyi”. Araştırma sonrası ürün/vaat/kaynak/ödeme/bildirim/UX kabulü yeni mağaza gönderiminden önce; Console erişimi doğrulandı (ADR-010).
16 Ekim son netleştirme: “ilk, en iyi ve en çok indirilen uygulama ... mükemmel ... uluslararası dillerde de araştırma ... dar kapsamlı düşünme, geniş düşün”. Her işte uygulama/test/eleştirel inceleme/düzeltme/yeniden doğrulama döngüsü; açık kabul sorunları kapanmadan tamamlandı sayılmaz. Araştırma dilleri serbest, uygulama/mağaza Türkçe. Türkçe ana metin hazırlık ve yayın işi SA-025; bu istek zamanlanmış takip yasağını kaldırmaz.
16 Ekim son kullanıcı yönü: “en öncelik alan araştırması, saha araştırması” ve “başka bir yapay zeka bunu devralabilsin”; “en çok indirilen”, “birinci sırada” hedefi korunur. Tam kullanıcı hedefi: `docs/growth/USER_OBJECTIVE_2026-10-16.md`. Önce kapsamlı araştırma ve büyüme mimarisi, sonra uygulama/test/yayın; şu aşamada takip otomasyonu yok. Mağaza görselinde Pro/satın alma/deneme promosyonu yok (ADR-009).
"Premium görünümlü, Türkçe Android/iOS uygulaması; hesap açmadan resmî kamu ilanlarını okuma, profil ve kişisel kayıtlı kriterlerle filtreleme, yeni uygun ilana FCM bildirimi." 15 Ekim büyüme yönü: Play Store'da AI Asistan ("Bu ilan bana uygun mu?") ayrışmasını öne çıkarmak, mağaza dönüşümünü (unique install CTR) eş-uygulama ortancasının üzerine çıkarmak.

## Users
- Kamu ilanlarını takip eden, şartlara uyup uymadığını hızlı öğrenmek isteyen Türkiye'deki iş arayanlar.

## Core Journeys
- Aç → ilan listesi/filtre → ilan ayrıntısı → Asistan'a "bana uygun mu?" → Uygun/Uygun değil/Bilinmiyor.
- Kriter kaydet → yeni uygun ilanda FCM bildirimi.
- Mağaza ziyareti → Asistan öne çıkan metin/görsel → yükle.

## Platforms
- android: Google Play, yalnız Türkiye, yalnız Türkçe (iOS ertelendi).

## Success Conditions
- [artifact] Kaynaklı saha araştırması, rakip/fiyat/bilinmeyen matrisi, mağaza metni/görsel briefi ve devralınabilir büyüme stratejisi kayıtlı (SA-022/023).
- [remote] Play canlı listeleme yerel tr-TR metadata ile aynı (kısa/uzun açıklama, ekran sırası).
- [remote] Play Console unique user install CTR 28 günlük baseline kaydedildi ve deneylerle izleniyor.
- [machine] Sunucu ayıklama ve Asistan testleri geçer.

## Riskiest Assumptions
- RA-1: Aynı doğru7ekranda ilan-first veya Asistan-first sırası Install CTR'yi değiştirir mi? → kontrollü tekvaryant deney (SA-007). Pro görseli yok; kazanım bilinmiyor.

## Target State
### Sunucu, ayıklama, Asistan
- Kaynak okuma/ayıklama yalnız sunucuda; mekanik önce, eksikse Qwen; tam metin kalıcı (ADR-001..006).
### Mobil
- Premium Türkçe UI, açık/koyu, büyük metin; telefon yalnız API/cache.
### Mağaza büyümesi
- Doğru güncel metin/görseller public; ilan-first ve Asistan-first farkı gerçek trafikle deneylenmiş. Pro/satın alma/deneme görseli yok; RA-1 sonucu varsayılmaz.

## Non-Goals
- Bu aşamada takip/heartbeat/cron veya periyodik Codex işi kurmak (C-062).
- İngilizce/diğer ülke mağaza girişi (C-061); iOS/APNs; ücretli Cloudflare/AI yükseltmesi.

## Open Decisions
- OD-001 RESOLVED (16 Ekim): Kullanıcı “Mağaza girişi hazırlansın ... Sadece Türkçe olacak” diye netleştirdi. Uygulama ve mağaza Türkçe; İngilizce giriş hazırlanmaz. Türkçe mağaza metni/görselleri ve optimizasyonu kapsamda (C-061, STORE_COPY, SA-021/007/008/009).
- OD-002 OPEN: Landing page alan adı (örn. kamubul.app) alınacak mı? → SA-010.
