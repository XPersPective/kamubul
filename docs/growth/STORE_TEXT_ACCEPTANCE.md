# Türkçe mağaza metni — yerel hazırlık ve eleştirel kabul

16.10.2026 | SA-025 | LOCAL_CANDIDATE, NOT_PUBLISHED

Tek kaynak STORE_COPY.md Title/ShortA/Full markerları. candidate/tr-TR/*.txt bu kaynaktan üretilmiş UTF-8/LF dosyalarıdır; AppPublishing dizinine kopyalanmadı, gönderilmedi. ShortB sonraki deneydir.

| Dosya | Karakter/sınır (son LF hariç) | SHA256 (LF dahil) |
|---|---|---|
| title.txt | 26/30 | 169c64f878f1039cba7e1dbd3a4558bfb3367ba2004053b32cfbc44966502d23 |
| short_description.txt | 76/80 | e0aadfbe657984981f7085a27880744174d67b04c28dca2bd5f4167c5c613a20 |
| full_description.txt | 3240/4000 | 26a67db6566f7b730a350098148463fad4cbf0fac4818d2ec44d8734fe00eda4 |

## Tur 1 — yayımlanmış ürünle vaat eşlemesi

Kaynak: C:/Users/rubicon/.codex/builds/kamubul-1.2.2-17/lib snapshot'ı. Kod varlığı gerçek cihaz başarısını kanıtlamaz.

| Vaat | Kod / kabul sınırı |
|---|---|
| Şehir/eğitim/yaş/puan, arama kaydı | home_page.dart filtre alanları/kayıt yükleme, listing_store.dart savedSearches; bütün şartlarda kesin uygunluk yok. |
| Kaydedilmiş metni çevrimdışı açma | listing_store.dart ayrıntı cache/favori, OfficialListingPage cacheNotice; tüm kataloğun çevrimdışı/güncel olduğu vaat edilmiyor. |
| Asistan koşul açıklaması | assistant_chat.dart/assistant_client.dart ilan bağlamı; hata, bilinmeyen ve nihai resmî metin uyarısı korunuyor. |
| İsteğe bağlı kayıtlı arama bildirimi | home_page.dart _setServerPush/push_registration.dart; izin/bağlantı/OS sınırları yazılı. Cihaz teslimi SA-005 açık. |
| İlk dönem/aylık Pro | main.dart trialDaysLeft/reklam yükleme koruması, pro_page.dart 10/50 ve otomatik yenileme; reklam/restore SA-005, server entitlement SA-016 açık. |
| Kaynak kapsamı | 16 Ekim health/meta araştırması; desteklenen kaynaklar, kesinti/metin eksikliği ve eksiksiz kapsama garantisi yok. |
| Kadrolar | code17 pozisyon kartları; çalışma ağacındaki SA-017 çipleri pazarlanmıyor. |

## Tur 2 — eleştiri ve yeniden kontrol

| Risk | Yeni adayın içerik kararı / yeniden kontrol |
|---|---|
| Önceki adayda “kesin uyan” ifadesi | Yeni Full, eşleşmenin bütün şartları sağlamak olmadığını açıklıyor; resmî metin uyarısıyla birlikte okundu. |
| Reklamsız ilk dönemin ücretli denemeyle karışması | İlk 7 günün kendiliğinden ücretli abonelik başlatmadığı yazılı; aylık yenileme ve Play iptal yolu ayrıca açık. |
| Kelime doldurma/kurum taklidi | Başlık ve kısa açıklamada KPSS/ÖSYM yok; doğal kategori cümlesi ve sınırlar PASS; kaynak/bağımsızlık uzun metinde. |
| Gelecek özelliği vaat etme | Otomatik deadline hatırlatması, başvuru notu, native takvim ve yeni pozisyon filtreleri adayda yok; SA-015/018/017 ile karşılaştırıldı. |
| İyi metni büyüme sonucu sayma | Arama hacmi/dönüşüm kazancı uydurulmadı; kullanıcı okuma testi, baseline ve deney sonucu UNKNOWN. |

Bu içerik turları bağımsız HIGH review veya gerçek kullanıcı testi değildir. Bulgu varsa düzelt → etkilenen vaat/kaynak eşitliği/karakter/hash yeniden doğrula. Aynı kontrolü yeni bulgu olmadan tekrar etmek ilerleme sayılmaz.

## Yayın readback

16 Ekim mevcut .tmp/listing-api-readback.py tekrar çalıştı: **eski 15 Ekim AppPublishing metinleri** ve yedi görselin sıralı SHA256 değerleri API ile eşit; production/internal code17 status completed. Inspection edit silme true. Bu sonuç yeni 3240 karakter adayın yayını veya Google public onayı değildir. Public eski sekiz görsel/100-30 ayrılığı için yetkili Publishing overview gerekli (SA-021). Yeni upload yok.

## Sıra

SA-021 doğru görseller/public → SA-025 metin inceleme/gönderim/API/public eşitliği → SA-011 son kontrol baseline → SA-007 → SA-008 → SA-009. Açık bağımsız inceleme, public kabul veya yetersiz trafik varken tamamlandı/kazandı deme. Zamanlanmış takip yok.
