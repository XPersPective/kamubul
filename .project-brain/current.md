# Current Architecture

Repository snapshot observed 18 October 2026; runtime/release lines updated 27 November 2026.

## Runtime
- Flutter/Dart app `com.crazypenguin.kamubul`, version 1.2.8+23 (`pubspec.yaml`) on Android (Google Play production `1.2.8 (23)`, `completed`, `edit 06324903882028974132`) and iOS (App Store `1.2.6 (118)` `READY_FOR_SALE`; `1.2.8 (121)` uploaded via `run 45972927890` and submitted `Waiting for Review` with automatic release). Store state, IDs and release commands: `docs/RELEASES.md`.
- iOS native bridges in `ios/Runner/AppDelegate.swift` mirror Android (calendar, deadline reminders, trial hash, secure push) and verify StoreKit 2 current entitlements (`verified_store_adapter.dart`). iOS ads/Pro are gated by `lib/store_features.dart`; production/test IDs are bound by `tool/ios/ads_config.py`.
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
- `site/` — Turkish GitHub Pages site (privacy/support/landing).

## Domains

### Mobile product
Status: VERIFIED
Sources: `lib/**`, `packages/kamubul_core/**`, `ios/**`, `android/**`, `test/**`
- Android/iOS listing browse, filtering, saved searches, local notifications, calendar export, awaited UMP/ATT ad consent (`lib/data/ad_consent.dart`), and verified StoreKit 2 local entitlement check (`lib/data/verified_store_adapter.dart`) are verified by 233 Flutter tests and 7 Python iOS config tests.
- TalkBack/device acceptance and iOS account-gated features are tracked in `PB-032`, `PB-035`, `PB-036`, `PB-039`–`PB-041` (`docs/PRODUCT_RUNTIME_ACCEPTANCE_2026-10-25.md`).

### Official sources, extraction and assistant
Status: VERIFIED
Sources: `workers/**`, `docs/SOURCE_REGISTRY.md`, `docs/EXTRACTION_EVALUATION_2026-10-25.md`
- Worker owns source ingestion, catalog and assistant endpoints; D1 persists catalog and processing state (306 Worker tests passing; live version `8edaf025-2b97-4d8f-a318-38f7bda0f245`, Alibaba Cloud Qwen Token Plan `qwen3.8-flash` + automatic Cloudflare Workers AI fallback, verified 27.11.2026).
- Official source coverage (`PB-030`, `docs/SOURCE_REGISTRY.md`, `PB-045`) and evidence-backed extraction precision/recall (`PB-031`, `docs/EXTRACTION_EVALUATION_2026-10-25.md`) are verified; assistant reporting (`PB-037`, `ADR-002`) and server Play/App Store entitlement (`PB-038`) remain open.

### Growth research, store assets and release automation
Status: VERIFIED
Sources: `docs/**`, `.github/**`, `site/**`, `tool/**`, `AGENTS.md`
- Store release state, SEO copy (`docs/growth/STORE_COPY.md`), framed 7-scene screenshots (`tool/brand/ios_store_frames.py`), and CI/release workflows (`.github/workflows/`) are documented in `docs/RELEASES.md` and `docs/IOS_RELEASE.md`.

## Known Unknowns
- Existing implementation and older reports need fresh checks before task completion; no release or remote publishing state is asserted here.

## Session audit 07.11.2026
- Source/account/runtime readbacks: `.project-brain/audits/2026-11-07-kamubul.md`; active acceptance: `PB-044`, `PB-045` (`DONE`).
- Android `1.2.5 (20)` built, signed, uploaded, and committed (`completed`) on Google Play production (`edit 17496769459339978662`, SHA-256 `f769753a492a62b5896f556448e56c4c05d1e62f4623da90f1e5eb1ddc84e4c3`).
- iOS `1.2.5 (112)` built and uploaded via GitHub Actions `run 42328466180`, validated (`VALID`), and attached to App Store version `e53880c3-e5b5-4428-be98-ed0528919b31` with updated Turkish metadata, `advertising: true` age rating, and updated subscription `kamubul_pro_monthly` (`6826881201`) localization. Submitting `1.2.5` for review is gated only on publishing the **App Privacy** tracking/purchases questionnaire in the App Store Connect web UI (`STATE_ERROR.BINARY_INDICATES_APP_TRACKS_USERS`) and attaching the first subscription (`FIRST_SUBSCRIPTION_MUST_BE_SUBMITTED_ON_VERSION`) on the version page.
