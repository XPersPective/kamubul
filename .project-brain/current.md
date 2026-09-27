# Current Architecture

## Scope

Verified repository reality. Recheck `git status` and source on resume.

## Runtime

- Flutter Android/iOS shell was generated with `tool/new_app.dart`.
- `lib/main.dart` initializes `SettingsStore`, theme, `napp_pro` lifetime purchase, and `napp_ads` policy/controllers. `lib/ads_state.dart` restores/stores ad timing and session state. Pro state loads before ad initialization.
- `pubspec.yaml` references tagged `napp_core`, `napp_pro`, `napp_ads`; `napp_core` has a Git-source override because `napp_ads`/`napp_pro` declare it as hosted. No local-path override remains.

## Domains

### Listings

**Status:** VERIFIED for first source. `lib/listings/kariyer_feed.dart` fetches `https://kariyerkapisi.gov.tr/RSS` with timeout/size bound, parses up to 200 items, validates official detail URLs, deduplicates and preserves the source calendar date. `dart run tool/check_live_feed.dart` read 22 valid items on 2026-09-27. Feed has no deadline. Other requested source adapters, local listing database, background fetch and notifications are absent.

### UI, monetization and settings

**Status:** VERIFIED. `lib/home_page.dart` has announcement cards, search/category chips, external official link, URL bookmarks, sources page, assistant placeholder, settings/theme/Pro/About and banner slot. `napp_pro` product is `kamubul_pro_lifetime`; `napp_ads` provides policy/controllers. Bookmarks are URL-only in `SettingsStore`; without cached listings they cannot display offline after restart. No assistant API, local database, notification UI or second-source scraper exists. `assets/brand/kamubul_icon.png` was generated and converted to Android/iOS icons. Android release APK opened in emulator with live listings on 2026-09-27 before the final date/icon edit; repeat device run is required for that edit.

## External Dependencies

- Tagged `napp_kit` packages provide settings/theme, purchases and ads.
- Kariyer Kapısı public RSS is integrated; all other official sources are linked but not automatically fetched.

## Known Unknowns

- Access/redistribution terms and stable page structure for İŞKUR, ilan.gov.tr, Resmî Gazete and municipalities.
- Source freshness, extraction accuracy, iOS device behavior and store product configuration. Contact email is still a development placeholder if `CONTACT_EMAIL` is not supplied; do not publish with it. `PRIVACY.md` is a development disclosure, not final store review.
