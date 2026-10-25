# Current Architecture

Repository snapshot observed 18 October 2026; runtime/release lines updated 25 October 2026.

## Runtime
- Flutter/Dart app `com.crazypenguin.kamubul`, version 1.2.4+19 (`pubspec.yaml`) on Android (Google Play) and iOS (App Store, iPhone, Türkiye). Store state, IDs and release commands: `docs/RELEASES.md`.
- iOS native bridges in `ios/Runner/AppDelegate.swift` mirror Android (calendar, deadline reminders, trial hash, secure push). iOS ads/Pro gated by `lib/store_features.dart`.
- Cloudflare Worker + D1 + Queues in `workers/`; Firebase is used for FCM.
- Flutter local state/cache and core matching code in `lib/` and `packages/kamubul_core/`.

## Map
- `lib/` — mobile application, settings, listings, assistant and notifications.
- `packages/kamubul_core/lib/` — criteria matching, parsing and deadline planning.
- `workers/src/` — API, ingestion, extraction, assistant and queue processing.
- `workers/migrations/` — D1 schema migrations.
- `test/`, `integration_test/`, `workers/test/` — app, device-flow and Worker checks.
- `docs/growth/STRATEGY.md` — handoff entry for sourced growth research.
- `docs/growth/USER_OBJECTIVE_2026-10-16.md` — user's full product/growth objective.
- `docs/SA015_ACCEPTANCE_2026-10-16.md` — deadline reminder device acceptance record.
- `docs/RELEASES.md` — single source for released versions, store state, IDs and release commands.
- `docs/IOS_RELEASE.md` — iOS pipeline details; `.github/workflows/ios-*.yml`, `android-screenshots.yml` — CI build/upload/capture.
- `tool/brand/ios_store_frames.py` — App Store and Play screenshot frames from real captures.
- `site/` — Turkish GitHub Pages site (privacy/support URLs used by stores).
- `AGENTS.md` — Project Brain workflow pointer.

## Domains

### Mobile product
Status: VERIFIED
Sources: `lib/**`, `test/**`, `integration_test/**`, `packages/**`, `android/**`, `ios/**`, `pubspec.yaml`
- Flutter app supports Turkish listing search, details, local saved items and criteria, themes, assistant and subscription UI (`222/222` widget/unit tests passing).
- Position-level accessible matching (`PB-034`) and deterministic saved-search notification update tests (`PB-042`) are verified.
- Runtime billing/TalkBack/device acceptance and iOS account-gated features are tracked in `PB-032`, `PB-035`, `PB-036`, `PB-039`–`PB-041` (`docs/PRODUCT_RUNTIME_ACCEPTANCE_2026-10-25.md`).

### Official sources, extraction and assistant
Status: VERIFIED
Sources: `workers/**`, `docs/SOURCE_REGISTRY.md`, `docs/EXTRACTION_EVALUATION_2026-10-25.md`
- Worker owns source ingestion, catalog and assistant endpoints; D1 persists catalog and processing state (`300/300` Worker tests passing).
- Official source coverage (`PB-030`, `docs/SOURCE_REGISTRY.md`) and evidence-backed extraction precision/recall (`PB-031`, `docs/EXTRACTION_EVALUATION_2026-10-25.md`) are verified; assistant reporting (`PB-037`, `ADR-002`) and server Play entitlement (`PB-038`) remain open.

### Growth research, store assets and release automation
Status: VERIFIED
Sources: `docs/**`, `.github/**`, `site/**`, `tool/**`, `AGENTS.md`
- Store release state, SEO copy (`docs/growth/STORE_COPY.md`), framed 7-scene screenshots (`tool/brand/ios_store_frames.py`), and CI/release workflows (`.github/workflows/`) are documented in `docs/RELEASES.md` and `docs/IOS_RELEASE.md`.

## Known Unknowns
- Existing implementation and older reports need fresh checks before task completion; no release or remote publishing state is asserted here.
