# Current Architecture

## Scope

Verified repository reality. Recheck `git status` and source on resume.

## Runtime

- Flutter Android/iOS shell was generated with `tool/new_app.dart`.
- `lib/main.dart` initializes `SettingsStore`, theme, `napp_pro` lifetime purchase, and `napp_ads` policy/controllers. `lib/ads_state.dart` restores/stores ad timing and session state. Pro state loads before ad initialization.
- `pubspec.yaml` references tagged `napp_core`, `napp_pro`, `napp_ads`; `napp_core` has a Git-source override because `napp_ads`/`napp_pro` declare it as hosted. No local-path override remains.

## Domains

### Listings

**Status:** VERIFIED for two sources incl. detail and local catalogue. `lib/listings/kariyer_feed.dart` fetches `https://kariyerkapisi.gov.tr/RSS` with timeout/size bound, parses up to 200 items, validates official detail URLs, deduplicates and preserves the source calendar date. `lib/listings/kariyer_detail.dart` reads the portal's two public read calls (`api.kariyerkapisi.gov.tr/api/ilan/GetIlanPreviewPublic`, `api/altilan/GetAltIlanInfoByIlanIdPublic`); field names verified against live responses 2026-09-27. `lib/listings/sbb_feed.dart` reads `kamuilan.sbb.gov.tr` (server-rendered ASP.NET): GET home for the WebForms triple (`__VIEWSTATE`, `__VIEWSTATEGENERATOR`, `__EVENTVALIDATION` — omitting them yields intermittent 500s), POST `ddl_yil=<year>`, parse `ilanDetay.aspx?kod=` items for kurum, "N ... ALACAK" quota text, Turkish date range and logo-hash publication date; item URL serves the official PDF (session cookie + Referer needed for direct fetch; host geo-blocks non-TR IPs). Live checks 2026-09-27: `tool/check_live_feed.dart` 22 items, `tool/check_live_detail.dart` 3 details, `tool/check_live_sbb.dart` 31 SBB items. `lib/data/listing_store.dart` (sqflite, schema v2) persists both sources with structured fields (deadline, quota, places) plus quote-backed condition fields (kpss, education, maxAge, quotaType with verbatim sentence quotes; v1→v2 migration tested), merges without resetting saved flags, prunes unsaved items older than 45 days, and stores named saved searches. `lib/listings/extract_conditions.dart` deterministically extracts KPSS puan türü/taban, yaş sınırı, eğitim and kota tipi from notice text — a field is stored only with its verbatim source sentence and only within validated ranges; detail page shows "Şart alanları" with quotes (live coverage on 12 real listings: KPSS türü %67, taban %50, yaş %42, eğitim %92; BDDK false-positive regression test in place). Saved searches can filter on yaş/eğitim/KPSS against extracted fields. Legacy `kamubul.saved_urls` bookmarks migrate into the database on first run. Documented blockers: İŞKUR public search sits behind session/JSF flows; ilan.gov.tr search API is an undocumented Kong-gateway surface (bundle endpoints 404); Resmî Gazete needs windows-1254 legacy markup handling plus per-document classification. Background fetch and notifications are absent.

### UI, monetization and settings

**Status:** VERIFIED. `lib/home_page.dart` renders the local catalogue: cards show title/category/date plus cached deadline, kontenjan and places from detail reads ("belirtilmemiş" when absent), expired badges in error color; tap opens `lib/listings/kariyer_detail_page.dart` (loading/error/content, apply button) whose success callback caches structured fields into the store. Filters: title search, category chips (İŞKUR tab intentionally empty until PB-003), "Son 30 gün" chip, optional place filter; saved searches are named chips with create/apply/rename-by-save/delete flows; URL bookmarks moved to database-backed saved listings that survive source removal. Settings/theme/Pro/About and banner slot unchanged. `napp_pro` product is `kamubul_pro_lifetime`; `napp_ads` provides policy/controllers. No assistant API, notification UI or second-source scraper exists. Obfuscated release APK ran on emulator 2026-09-27: catalogue refresh, detail caching, bookmark and saved-search persistence across restart verified via UI automation.

## External Dependencies

- Tagged `napp_kit` packages provide settings/theme, purchases and ads.
- Kariyer Kapısı public RSS is integrated; all other official sources are linked but not automatically fetched.

## Known Unknowns

- Access/redistribution terms and stable page structure for İŞKUR, ilan.gov.tr, Resmî Gazete and municipalities.
- Source freshness, extraction accuracy, iOS device behavior and store product configuration. Contact email is still a development placeholder if `CONTACT_EMAIL` is not supplied; do not publish with it. `PRIVACY.md` is a development disclosure, not final store review.
