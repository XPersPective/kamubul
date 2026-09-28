# Current Architecture — KamuBul

Verified repository reality as of 2026-09-28. Recheck Git and live sources on resume.

## Runtime and product shell

- Flutter Android/iOS project. `lib/main.dart` loads local settings, theme, lifetime Pro (`napp_pro`) and restrained ads (`napp_ads`). App locale is Turkish only. The current Android release APK was built, installed and visually checked on an emulator on 2026-09-28; iOS device and store purchase tests remain open.
- Onboarding collects optional city, age, education and KPSS into a local saved search. No user account or app server. `PRIVACY.md` and the contact email need release review.

## Official catalogue

- `lib/data/catalogue_refresh.dart` is the shared foreground/background refresh path. It preserves cached listings on source failures and feeds `ListingStore` (SQLite schema v3). Saved records survive pruning; refreshed structured fields update saved and unsaved records without erasing existing detail values. Cross-source fingerprint dedupe is in `lib/data/dedupe.dart`.
- Kariyer Kapısı uses its public `GetIseAlimPage` list call for title, category and deadline, enriches publication dates from RSS, and falls back to RSS if the list call fails. Live API check on 2026-09-28: 26 records with deadlines, including two “Yurt Dışı Eğitim” notices that are not job opportunities; both list parsers now exclude that category and shared matching hides existing cached copies. The official RSS also returns five future-dated records before their publication day; shared search/alert matching suppresses them until that day while saved records remain visible. On tap, public preview/sublisting calls load institution, positions, quota, places, conditions and application URL; supported fields are cached.
- SBB `kamuilan.sbb.gov.tr` uses the official server-rendered WebForms list (GET tokens, POST year) to obtain institution, title, category, quota and date range; the official detail is a PDF. Resmî Gazete adapter reads legacy archive markup, classifies personnel notices and uses a bundled public CA chain to complete TLS; recent live yield is zero. İŞKUR and ilan.gov.tr adapters remain blocked by documented WAF/session endpoints. Municipality coverage is absent.
- `lib/listings/extract_conditions.dart` parses KPSS, age, education and quota type only with an exact source sentence; absent or unproven fields remain unspecified. The available live sample is 12 Kariyer listings; the required ≥50-per-source precision/recall evaluation has not been completed. AI candidate extraction is absent.

## User experience

- `lib/home_page.dart` shows a locally cached catalogue, title search, category/place/age/education/KPSS filters, saved searches, bookmarks, source failures and refresh status. The İşçi category can include official SBB worker listings; the live Android check on 2026-09-28 returned zero current worker records, and İŞKUR remains blocked. Cards show official source, publication date, deadline/countdown, quota and places when known; a saved “Sizin için” search highlights only records matching its populated filters. City matches require a structured place, since an institution name can contain a city without the job being there. Saved-search application synchronizes the search field and filter state. Kariyer detail is an in-app structured view with cited condition text and a fixed application CTA; loading uses card skeletons. SBB/RG open an in-app summary first; the official document opens only by explicit button.
- `lib/ui/premium.dart` has shape/motion tokens, skeletons, shared-axis transition and countdown helper. The revised list header/cards and future-date filtering were visually checked in an Android release APK on 2026-09-28 (83 currently visible from 88 cached records). Phone/tablet/1.3× widget and golden tests exist. Formal contrast/TalkBack review, iOS pass and further visual refinement remain.
- `lib/listings/listing_guide.dart` provides a deterministic, citation-backed answer for a selected Kariyer listing. SBB/RG show their source-native quota/deadline and state that unextracted conditions are unknown. It has no network AI. The assistant API, editable profile, ALH meaning and speech input are unresolved.

## Alerts

- `lib/notifications/alert_service.dart` uses Android Workmanager 12-hour best-effort checks and local notifications. The scheduled check refreshes official sources before matching saved searches. Per-search instant/digest/off, quiet hours, daily cap, deferred queue, deadline reminders and in-app notification history are implemented. iOS device behavior and notification-tap routing remain unverified.

## External dependencies and constraints

- `napp_core`, `napp_pro`, `napp_ads` come from tagged `napp_kit`; `napp_core` has a Git override to match the package graph. Developer-paid AI key is not embedded in the app. The configured local OpenCode Zen endpoint returned HTTP 402 for one model and 403 for another in a 2026-09-28 trial, so an in-app paid AI path is not verified. Store products, source terms and redistribution require review before release.
