# Project Constraints

## User Requirements

### C-001 Official sources
Use official channels: feed/API first, otherwise public page parsing. Include İŞKUR, ilan.gov.tr, Resmî Gazete, Kariyer Kapısı, municipalities and other trustworthy institutions. Keep original application URL.

### C-002 Local-first
No app account or developer server for core. Local listings/profile/preferences. Open/manual refresh and best-effort one or two background checks daily; user-selected category notifications. Prune expired cache without losing saved items.

### C-003 Assistant and ALH
Prepare in-app API assistant for 10,000-user cost trial. Optional profession/age/education profile, announcement Q&A, matching, text then speech. Preserve the user's “ALH” term for later resolution.

### C-004 Revenue
Small banners, restrained splash/fullscreen ads, seven-day/five-session protection, lifetime non-consumable Pro and restore. No ad while reading or applying.

### C-005 Extraction integrity — official sources only
Structured fields (kontenjan, yaş, eğitim, KPSS, şehir, deadline, application link) reach the UI only when they pass the mechanical gates: schema validation, verbatim source quote found in fetched text, confidence threshold. Otherwise the field is "unknown" and the raw sentence is shown. Official channels are the only data sources; competitor apps, aggregators and news portals are never fetched for data. Each extractor ships only after per-field precision/recall on labeled real samples (≥50 per source).

### C-006 Premium experience bar
The app must feel premium and simple: skeleton loaders (no bare spinners), spring/interruptible transitions, haptics on key actions, deadline countdowns, plain-language states, filter chips + bottom sheet with live result count, onboarding ≤4 skippable steps. Hard accessibility floor: WCAG AA contrast, 48dp targets, screen-reader labels, no clipping at 1.3x text scale, light/dark parity. Every production claim includes a release-device UX pass.

## Security

### C-020 Secrets
Never commit real `.env`, signing/ad/AI keys. No developer API secret in a distributed binary. Validate untrusted HTML/XML/PDF and outbound URLs. Keep all existing `.gitignore` secret rules.

### C-021 Privacy
Minimize profile fields; local by default, deletable/exportable. Explicit user action before sending profile/announcement to AI. No hidden telemetry.

## Operations

### C-030 Platform truth
Background scheduling is discretionary. Do not claim instant push from device-only polling. Handle permission denial and offline mode.

## Development

### C-040 Repo standard
Follow `ORTAK_UYGULAMA_STANDARDI.md`; reuse `napp_core`, `napp_pro`, `napp_ads`. Check new-package licenses. Keep one runnable check for nontrivial logic. Release/device checks precede production claim.
