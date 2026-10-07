# Project Brain — KamuBul

## 0. PROTOCOL

Bu depoda çalışmaya başlamadan önce `C:/Users/rubicon/.codex/skills/project-brain/SKILL.md`
protokolünü oku. Git durumunu incele, aktif görevin kabul ölçütlerini doğrula, mimari
bilgiyi `current.md` ile eşleştir ve her güvenli kontrol noktasında commit/push yap.

Güncel proje kaydı `.project-brain/` dizinindedir. Başlangıç sırası:
`config.yaml` → `current.md` → `target.md` → `constraints.md` → hazır görev.
30 Eylül 2026 geçiş yönü: Cloudflare Free + D1 + Workers AI Free + FCM;
karar `decisions/ADR-001.md`. 6 Ekim: PB-016…PB-023'ün kalan kabul kapıları `tasks/PB-029.md`'de birleştirildi.
`docs/CLOUDFLARE_FCM_YOL_HARITASI.md` devir/sıra rehberidir. Eski local-only
ve Cloud Run/Blaze görevleri aktif plandan kaldırılmıştır; Git geçmişindedir.
5 Ekim son kullanıcı yönü PB-026: kaynak okuma/ayıklama yalnız sunucuda;
telefon API/cache kullanır. Önceki telefon fallback koruma yönergesi geçersizdir.
7 Ekim güncel yayın: 1.2.2/code17 üretim ve dahili teste gönderildi (Google
incelemesi). Ayıklama kalitesi PB-027, kaynak kapsamı PB-026 (BLOCKED), üretim
kabul kapıları PB-029, kullanıcı listeleri PB-024/025, premium inceleme PB-028.
Mevcut mimari yalnızca `current.md` içinde, ürün hedefi `target.md` içinde,
uygulama sırası `tasks/` içinde tutulur. `ORTAK_UYGULAMA_STANDARDI.md`
kuralları geçerlidir.
