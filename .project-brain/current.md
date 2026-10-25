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
Status: OBSERVED
Sources: `lib/**`, `test/**`, `packages/kamubul_core/lib/**`
- Flutter app supports Turkish listing search, details, local saved items and criteria, themes, assistant and subscription UI.
- Open product acceptance tracked in PB-032–PB-038; older machine/evidence logs are not current acceptance proof.

### Official sources, extraction and assistant
Status: OBSERVED
Sources: `workers/src/**`, `workers/test/**`, `workers/migrations/**`
- Worker owns source ingestion, catalog and assistant endpoints; D1 persists catalog and processing state.
- Source coverage, evidence-backed extraction precision, assistant reporting and server entitlement remain open product work (PB-030, PB-031, PB-036–PB-038).

### Growth research
Status: OBSERVED
Sources: `docs/growth/**`, `docs/PLAY_GROWTH_AUDIT.md`
- Research and product strategy are maintained as repository docs. Prior findings must be rechecked before being represented as current.
- Store listing changes, screenshot production, experiments and publication are outside this plan.

## Known Unknowns
- Existing implementation and older reports need fresh checks before task completion; no release or remote publishing state is asserted here.
