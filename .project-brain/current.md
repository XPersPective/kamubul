# Current Architecture

## Scope

Verified repository reality. Recheck `git status` and source on resume.

## Runtime

- Flutter Android/iOS shell was generated with `tool/new_app.dart`.
- `lib/main.dart` initializes `SettingsStore`, theme, `napp_pro` lifetime purchase, and `napp_ads` policy/controllers. `lib/ads_state.dart` restores/stores ad timing and session state. Pro state loads before ad initialization.
- `pubspec.yaml` references tagged `napp_core`, `napp_pro`, `napp_ads`; `napp_core` has a Git-source override because `napp_ads`/`napp_pro` declare it as hosted. No local-path override remains.

## Domains

### Listings

**Status:** VERIFIED for first source incl. detail. `lib/listings/kariyer_feed.dart` fetches `https://kariyerkapisi.gov.tr/RSS` with timeout/size bound, parses up to 200 items, validates official detail URLs, deduplicates and preserves the source calendar date. `lib/listings/kariyer_detail.dart` reads the portal's two public read calls (`api.kariyerkapisi.gov.tr/api/ilan/GetIlanPreviewPublic`, `api/altilan/GetAltIlanInfoByIlanIdPublic`) with the same bounds; field names verified against live responses 2026-09-27. It extracts kurum, deadline, apply URL (e-Devlet or kurum, https-only), per-position unvan/kontenjan/places and condition highlights. `dart run tool/check_live_feed.dart` read 22 items and `dart run tool/check_live_detail.dart` verified 3 details live on 2026-09-27. The feed carries no deadline; the detail call supplies deadline/quota/places. Other requested source adapters, local listing database, background fetch and notifications are absent.

### UI, monetization and settings

**Status:** VERIFIED. `lib/home_page.dart` has announcement cards (tap opens `lib/listings/kariyer_detail_page.dart`: loading/error/content states, kurum, kontenjan, son başvuru, yerler, kadrolar, öne çıkan şartlar, apply button), search/category chips, external official link, URL bookmarks, sources page, assistant placeholder, settings/theme/Pro/About and banner slot. `napp_pro` product is `kamubul_pro_lifetime`; `napp_ads` provides policy/controllers. Bookmarks are URL-only in `SettingsStore`; without cached listings they cannot display offline after restart. No assistant API, local database, notification UI or second-source scraper exists. `assets/brand/kamubul_icon.png` was generated and converted to Android/iOS icons. Obfuscated release APK was built and run on the emulator on 2026-09-27 after the final date/icon edit: home and detail screens verified with live listings, test-ad banner only.

## External Dependencies

- Tagged `napp_kit` packages provide settings/theme, purchases and ads.
- Kariyer Kapısı public RSS is integrated; all other official sources are linked but not automatically fetched.

## Known Unknowns

- Access/redistribution terms and stable page structure for İŞKUR, ilan.gov.tr, Resmî Gazete and municipalities.
- Source freshness, extraction accuracy, iOS device behavior and store product configuration. Contact email is still a development placeholder if `CONTACT_EMAIL` is not supplied; do not publish with it. `PRIVACY.md` is a development disclosure, not final store review.
