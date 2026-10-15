# Product
Status: CONFIRMED

(Project Brain target.md'den 15.10.2026 devralındı; hedef kullanıcı yönergelerinden oluşur. Tam eski metin arşivde.)

## Goal
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
- [remote] Play canlı listeleme yerel tr-TR metadata ile aynı (kısa/uzun açıklama, ekran sırası).
- [remote] Play Console unique user install CTR 28 günlük baseline kaydedildi ve deneylerle izleniyor.
- [machine] Sunucu ayıklama ve Asistan testleri geçer.

## Riskiest Assumptions
- RA-1: Asistan-öncelikli metin/görsel CTR'yi artırır → Play store listing experiment (unique install clicks).

## Target State
### Sunucu, ayıklama, Asistan
- Kaynak okuma/ayıklama yalnız sunucuda; mekanik önce, eksikse Qwen; tam metin kalıcı (ADR-001..006).
### Mobil
- Premium Türkçe UI, açık/koyu, büyük metin; telefon yalnız API/cache.
### Mağaza büyümesi
- Asistan-öncelikli mağaza metni ve ekran sırası canlı; deneylerle doğrulanmış.

## Non-Goals
- İngilizce/diğer ülke mağaza girişi (C-061); iOS/APNs; ücretli Cloudflare/AI yükseltmesi.

## Open Decisions
- OD-001 OPEN: Rapordaki en-US yerelleştirme önerisi C-061 (yalnız Türkçe) ile çelişiyor → kullanıcı kararı.
- OD-002 OPEN: Landing page alan adı (örn. kamubul.app) alınacak mı? → SA-010.
