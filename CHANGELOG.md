# Değişiklik kaydı

## Yayınlanmamış

### Eklenenler
- `packages/kamubul_core`: uygulama ve sunucunun paylaştığı saf Dart çekirdek.
- `backend/`: arayüzsüz API, günlük çekim işi, Firestore/dosya depolama, FCM
  gönderimi ve dağıtım dosyaları (Google öncelikli, taşınabilir).
- Uygulama: sunucu kataloğu (`KAMUBUL_API`), kaynak başına cihaz yedeği,
  isteğe bağlı anonim sunucu bildirimi ve silinebilir kayıt, "Yapay zekâ özeti"
  kartı, yerel şema v4.
- Sağlayıcıdan bağımsız yapay zekâ katmanı (Anthropic, OpenAI uyumlu, Gemini);
  varsayılan kapalı, alanlar ölçüm kapısı geçilene kadar açılmaz.

### Değişenler
- Resmî Gazete kapsam dışı bırakıldı (adaptör ve sertifika zinciri kaldırıldı).
- Ayrıştırıcı ve şart çıkarım testleri ile değerlendirme korpusu
  `packages/kamubul_core` altına taşındı.

## 1.0.0+1

İlk sürüm.

### Eklenenler
- Resmî kaynaklardan kamu iş ilanı takibi: Kariyer Kapısı ve Kamu İlanları
  (SBB) derlemeleri; Resmî Gazete yalnızca duyuru bağlantısı olarak.
- Mekanik şart çıkarımı: kontenjan, KPSS türü/taban puanı, yaş sınırı,
  eğitim düzeyi, kadro/kota tipi — her değer birebir alıntısıyla; belirsiz
  olan "belirtilmemiş" kalır. Alan bazlı politika haritası kapalı alanı ham
  metne düşürür.
- Varsayılan süzgeçler ve kullanıcı etiketleri (şehir, yaş, eğitim, KPSS):
  aramaları süzer, kayıtlı aramalara uyan ilanlar için bildirim üretir.
  Sessiz saatler 22:00-08:00.
- Kayıtlı aramalar, yer imleri, bildirim geçmişi ve ayarlar yalnızca bu
  cihazda tutulur; silinebilir ve JSON yedeği olarak dışa/içe aktarılabilir.
- Ömür boyu Pro (reklamsız kullanım) ve satın alma geri yükleme.
- Tema (sistem/açık/koyu), tablet düzeni, Hakkında ve lisanslar sayfası,
  uygulama paylaşımı ve puan istemi (kota dostu: olumlu andan sonra, seyrek).

### Sürüm öncesi notlar
- `CONTACT_EMAIL`, `PRIVACY_URL`, `OTHER_APPS_URL` değerleri `--dart-define`
  ile verilir. `hello@example.com` geliştirici yer tutucusudur; mağaza
  yayınında gerçek adresle değiştirilmeden yayınlanmaz.
- Reklam ve ürün kimlikleri `--dart-define` ile verilir; geliştirme
  derlemelerinde test kimlikleri kullanılır.
- Mağaza sürümü obfuscate edilmiş, `split-debug-info` çıktısı depo dışında
  tutularak üretilir.
