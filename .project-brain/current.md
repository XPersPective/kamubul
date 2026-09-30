# Current Architecture — KamuBul

Reconciled 2026-09-30 against the other agent's `origin/master:346863e`.
The 2026-09-28 sections below describe the prior mobile baseline; the Remote
backend section supersedes their no-backend/no-AI/schema-v3/RG claims. Current
reality: shared Dart core, SQLite v4, optional remote snapshot and opt-in FCM
registration, native Dart backend (Firestore/files); no Cloudflare implementation
or deployed application backend. Source parsers and fixtures moved into
`packages/kamubul_core`; RG was removed from active scope.

2026-09-30 checks on the integrated code: 104 core tests, 37 backend tests and
83 Flutter tests passed. Core/backend analysis clean. Flutter analysis reports
two pre-existing unnecessary imports in `test/remote_sync_test.dart:8-9`;
this documentation review did not edit application or test source. No live source, FCM,
AI, deployment or release-device verification was performed in this review.
Free Cloudflare + FCM migration is a proposal, recorded in
`docs/CLOUDFLARE_FCM_YOL_HARITASI.md`, not present architecture.

## Cloud account bootstrap — verified in consoles 2026-09-30

- Cloudflare Workers Free ($0); test Worker `kamubul-api-dev` contains only the dashboard Hello World template. Worker URL: `https://kamubul-api-dev.devx8585.workers.dev`. Public response unverified: the in-app browser blocked navigation (`ERR_BLOCKED_BY_CLIENT`). No catalogue, device registry, Cron or FCM sender is deployed.
- Empty private D1 `kamubul-dev`, ID `3fbb739f-891c-4da1-821e-417018139721`, automatic Eastern Europe region, connected to that test Worker as `DB`. Dashboard production/preview binding values both point to this development database; no real production resource exists.
- Existing Firebase project `kamubul-3ae6e` is Spark (no-cost $0/month); FCM HTTP v1 is Enabled. Registered Android app `com.crazypenguin.kamubul`, app ID `1:1003012781397:android:c474608bf0e36534ae2bdc`, sender ID `1003012781397`.
- Android configuration download did not return a file path; installation into the app is unverified. No server private key, API token, billing upgrade or real device push was created/performed. Console screenshots are local ignored evidence under `.project-brain/.cache/`.

## Runtime and product shell

- Flutter Android/iOS project. `lib/main.dart` loads local settings, theme, lifetime Pro (`napp_pro`) and restrained ads (`napp_ads`). App locale is Turkish only. The current Android release APK was built, installed and visually checked on an emulator on 2026-09-28. An obfuscated release APK (`--obfuscate --split-debug-info` outside the repo at `D:/repositories/kamubul-debug-info`) built and launched cleanly on 2026-09-28 after a clean secret scan (no signing/ad/AI keys in the tree; verification build is debug-signed). Branded splash is wired: Android `launch_background` + `values-v31` window colors and iOS `LaunchImage` generated from the brand icon. iOS device tests, store purchase sandbox and store publishing remain open (no Apple host; store account/signing/publishing are owner operations). The store build should add `--strip` (the verification build emitted the known DWARF warning) and must not use the placeholder contact email.
- Onboarding collects optional city, age, education and KPSS into a local saved search. No user account or app server. `PRIVACY.md` and the contact email need release review.

## Official catalogue

- `docs/SOURCE_REGISTRY.md` is the source registry required by target.md: per source it records fetch method, parser files, self-imposed rate limit, attribution, last success/failure and robots/geo constraints ("kayıt yok" where unmeasured — never invented). Usage-terms verification remains a release gate (TD-002).

- `lib/data/catalogue_refresh.dart` is the shared foreground/background refresh path. It preserves cached listings on source failures and feeds `ListingStore` (SQLite schema v3). Saved records survive pruning; refreshed structured fields update saved and unsaved records without erasing existing detail values. Cross-source fingerprint dedupe is in `lib/data/dedupe.dart`. `ListingStore.close()` closes only injected test databases — sqflite shares one instance per path, and the getter reopens a handle another caller closed.
- Kariyer Kapısı uses its public `GetIseAlimPage` list call for title, category and deadline, enriches publication dates from RSS, and falls back to RSS if the list call fails. Live API check on 2026-09-28: 26 records with deadlines, including two “Yurt Dışı Eğitim” notices that are not job opportunities; both list parsers now exclude that category and shared matching hides existing cached copies. The official RSS also returns five future-dated records before their publication day; shared search/alert matching suppresses them until that day while saved records remain visible. On tap, public preview/sublisting calls load institution, positions, quota, places, conditions and application URL; supported fields are cached.
- SBB `kamuilan.sbb.gov.tr` uses the official server-rendered WebForms list (GET tokens, POST year) to obtain institution, title, category, quota and date range; the official detail is a PDF. Resmî Gazete adapter reads legacy archive markup, classifies personnel notices and uses a bundled public CA chain to complete TLS; recent live yield is zero. İŞKUR and ilan.gov.tr adapters remain blocked by documented WAF/session endpoints. Municipality coverage is absent.
- `lib/listings/extract_conditions.dart` extracts KPSS type/score, age limit, education and quota type only with an exact source sentence; absent, conflicting or unproven fields remain unspecified (whole-text single-distinct-value abstention; trap sentences for document uploads, preferences, salary caps, list markers and law-clause boilerplate produce no values). Labeled evaluation is complete: 55 Kariyer and 55 SBB fixtures (`test/fixtures/eval/`) score all 11 fields at precision/recall 1.000 (`dart run tool/eval_extraction.dart`); `test/extraction_eval_test.dart` gates policy-enabled fields at the 0.95 precision bar in CI, and policy-closed fields degrade to raw text in the detail page, guide and local store. AI candidate extraction is absent and remains behind TD-001.

## User experience

- `lib/home_page.dart` shows a locally cached catalogue, title search, category/place/age/education/KPSS filters, saved searches, bookmarks, source failures and refresh status. The İşçi category can include official SBB worker listings; the live Android check on 2026-09-28 returned zero current worker records, and İŞKUR remains blocked. Cards show official source, publication date, deadline/countdown, quota and places when known; a saved “Sizin için” search highlights only records matching its populated filters. City matches require a structured place, since an institution name can contain a city without the job being there; `lib/data/turkish_cities.dart` canonicalizes the 81 il names and the city picker queries Kariyer Kapısı with its own `il` list filter, whose returned URLs get the verified city added to their places (`ListingStore.addVerifiedCity`, live-checked 2026-09-28: Ankara returns 7 of 27 items). Saved-search application synchronizes the search field and filter state. Kariyer detail is an in-app structured view with cited condition text and a fixed application CTA; loading uses card skeletons. SBB/RG open an in-app summary first; the official document opens only by explicit button.
- `lib/ui/premium.dart` has shape/motion tokens, skeletons, shared-axis transition and countdown helper. The revised list header/cards and future-date filtering were visually checked in an Android release APK on 2026-09-28 (83 currently visible from 88 cached records). Phone/tablet/1.3× widget and golden tests exist, plus a WCAG AA contrast gate (tests) and a formal input-response measurement on the emulator (`integration_test/input_latency_test.dart` via `test_driver`, profile build: visible tap response medians 17–65ms with a worst sample of 88ms, under the 100ms bar; debug build medians 57–92ms). Every page route now uses the spring tokens via `sharedAxisRoute`. iOS pass remains open (no Apple host); further visual refinement is open-ended.
- `lib/listings/listing_guide.dart` provides a deterministic, citation-backed answer for a selected Kariyer listing. SBB/RG show their source-native quota/deadline and state that unextracted conditions are unknown. It has no network AI. Saved-search profile fields (age/education/KPSS) are editable from the manage sheet and travel with the PB-006 backup. The assistant API, the meaning of "ALH" (TD-003 — do not invent) and speech input are unresolved; the paid AI path stays behind TD-001.

## Alerts

- `lib/notifications/alert_service.dart` uses Android Workmanager 12-hour best-effort checks and local notifications. The scheduled check refreshes official sources and up to five saved-search cities before matching saved searches. Per-search instant/digest/off, quiet hours, daily cap, deferred queue, deadline reminders and in-app notification history are implemented. Notification taps (live and cold start) route to the local listing detail and fall back to the official URL for pruned records (`alertTapUrl` bridge + `consumeLaunchAlertTap`); widget-tested (3 tests). A device tap-test is impossible on the network-less emulator — it cannot receive notifications; iOS device behavior also remains unverified (no Apple host). Emulator/no-network means background refresh and purchase flows have no device evidence beyond offline-graceful behavior.

## External dependencies and constraints

- `napp_core`, `napp_pro`, `napp_ads` come from tagged `napp_kit`; `napp_core` has a Git override to match the package graph. Developer-paid AI key is not embedded in the app. The configured local OpenCode Zen endpoint returned HTTP 402 for one model and 403 for another in a 2026-09-28 trial, so an in-app paid AI path is not verified. Store products, source terms and redistribution require review before release.

## Remote backend (implemented in the repo 2026-09-29; not deployed)

- `packages/kamubul_core` holds the pure-Dart code shared by app and server (parsers, extraction, dedupe, filter matching, snapshot schema v1, remote client, provider-agnostic AI layer, push planner). The app keeps thin bridge files under `lib/` that re-export it. The extraction gate (0.95) and its fixtures now live in the package.
- `backend/` is the UI-less service: `bin/job.dart` (fetch → merge → detail/AI → publish snapshot → match and send FCM) and `bin/server.dart` (`/v1/listings.json`, `/v1/sources.json`, `/v1/health`, `PUT|DELETE /v1/devices/{id}`), storage behind an interface (Firestore for Google, files for any VPS), Dockerfile, Firebase Hosting/Firestore config and docker-compose.
- The app reads the snapshot only when built with `--dart-define=KAMUBUL_API=...`; otherwise it behaves as before. Per-source fallback to the embedded fetch is implemented and tested. Server push registration is opt-in and deletable; local schema is v4 (AI summary column).
- Verified here: package and backend tests, compiled binaries, a local API smoke test, and a subset of app tests in a scratch copy with stubbed `napp_*`. Not verified: deployment, real FCM/AI/source calls, Android/iOS builds, the `home_page.dart`/`main.dart` glue. See tasks PB-010..PB-014.
