# Project Constraints

## Latest user direction — 2026-09-30

The current request is inspection and a roadmap only. Entirely free operating services, no user login, profile/saved-search matching and closed-app notifications are required. No automatic paid-plan upgrade or paid AI dependency. Earlier Cloud Run/Blaze and paid-AI deployment targets below are historical proposals superseded for this investigation; do not execute them. Cloudflare + FCM is the service-name interpretation, subject to clarification if Firestore was intended as a separate database. Detailed proposal and verified new backend baseline: `docs/CLOUDFLARE_FCM_YOL_HARITASI.md`. Runtime/D1/API choices are not yet approved implementation.

## User Requirements

### C-001 Official sources
Use official channels: feed/API first, otherwise public page parsing. Include İŞKUR, ilan.gov.tr, Resmî Gazete, Kariyer Kapısı, municipalities and other trustworthy institutions. Keep original application URL.

### C-002 Local-first
No app account. **Revised 2026-09-29:** a serverless Firebase/Google Cloud backend (no self-managed host, no UI) fetches official sources about three times a day and serves the catalogue; the app caches it locally with offline reading, manual refresh and saved-search notifications through FCM. Local profile/preferences stay local. Prune expired cache without losing saved items.

### C-003 Assistant and ALH
Server-side AI (developer's own key, server only; provider selectable: Anthropic, OpenAI-compatible or Gemini) extracts and summarizes once per listing; an in-app Q&A assistant is phase 2. 10,000-user cost trial. Optional profession/age/education profile, announcement Q&A, matching, text then speech. Preserve the user's “ALH” term for later resolution.

### C-004 Revenue
Small banners, restrained splash/fullscreen ads, seven-day/five-session protection, lifetime non-consumable Pro and restore. No ad while reading or applying.

### C-005 Extraction integrity — official sources only
Source-native typed fields (such as a portal's deadline or quota property) require type/range and official-origin validation. Fields derived from free text or AI candidates (such as age, education and KPSS) require schema validation, a verbatim quote found in fetched text and a recorded confidence threshold; otherwise they stay "unknown" with the original text available. Official channels are the only data sources; competitor apps, aggregators and news portals are never fetched for data. Each text extractor ships only after per-field precision/recall on labeled real samples (≥50 per source).

### C-006 Premium experience bar
The app must feel premium and simple: skeleton loaders (no bare spinners), spring/interruptible transitions, haptics on key actions, deadline countdowns, plain-language states, filter chips + bottom sheet with live result count, onboarding ≤4 skippable steps. Hard accessibility floor: WCAG AA contrast, 48dp targets, screen-reader labels, no clipping at 1.3x text scale, light/dark parity. Every production claim includes a release-device UX pass.

## Security

### C-020 Secrets
Never commit real `.env`, signing/ad/AI keys. No developer API secret in a distributed binary. Validate untrusted HTML/XML/PDF and outbound URLs. Keep all existing `.gitignore` secret rules.

### C-021 Privacy
Minimize profile fields; local by default, deletable/exportable. The backend holds only an anonymous device ID, FCM token and saved-search filters, deletable from the app; store declarations and PRIVACY.md must be updated before release. Explicit user action before sending profile/announcement to AI. No hidden telemetry.

## Operations

### C-030 Platform truth
Server push is best effort at the OS level; never promise guaranteed delivery. Backend fetch must respect reasonable per-source rates and never bypass login/CAPTCHA/WAF. Handle permission denial and offline mode.

## Development

### C-040 Repo standard
Follow `ORTAK_UYGULAMA_STANDARDI.md`; reuse `napp_core`, `napp_pro`, `napp_ads`. Check new-package licenses. Keep one runnable check for nontrivial logic. Release/device checks precede production claim.
