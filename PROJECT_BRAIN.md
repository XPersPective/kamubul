# Project Brain — KamuBul

## 0. PROTOCOL

Bu depoda çalışmaya başlamadan önce `C:/Users/rubicon/.codex/skills/project-brain/SKILL.md`
protokolünü oku. Git durumunu incele, aktif görevin kabul ölçütlerini doğrula, mimari
bilgiyi `current.md` ile eşleştir ve her güvenli kontrol noktasında commit/push yap.

Güncel proje kaydı `.project-brain/` dizinindedir. Başlangıç sırası:
`config.yaml` → `current.md` → `target.md` → `constraints.md` → hazır görev.
30 Eylül 2026 geçiş yönü: Cloudflare Free + D1 + Workers AI Free + FCM;
karar `decisions/ADR-001.md`, ilk uygulama görevi `tasks/PB-016.md`.
`docs/CLOUDFLARE_FCM_YOL_HARITASI.md` devir/sıra rehberidir. Eski local-only
ve Cloud Run/Blaze görevleri aktif plandan kaldırılmıştır; Git geçmişindedir.
5 Ekim son kullanıcı yönü PB-026: kaynak okuma/ayıklama yalnız sunucuda;
telefon API/cache kullanır. Önceki telefon fallback koruma yönergesi geçersizdir.
6 Ekim güncel yayın:1.1.9/code14 üretim ve dahili teste gönderildi; dahili test
kullanılabilir, production Google incelemesinde. Kaynak kapsamı/kalite PB-027
ve PB-026 üzerinde açık takip edilir.
Mevcut mimari yalnızca `current.md` içinde, ürün hedefi `target.md` içinde,
uygulama sırası `tasks/` içinde tutulur. `ORTAK_UYGULAMA_STANDARDI.md`
kuralları geçerlidir.
