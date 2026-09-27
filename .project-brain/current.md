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

**Status:** VERIFIED. `lib/home_page.dart` renders the local catalogue: cards show title/category/date plus cached deadline, kontenjan and places from detail reads ("belirtilmemiş" when absent), countdown badges ("Son N gün"/"Bugün son gün"/"Süre doldu", error color when urgent), expired badges; tap opens `lib/listings/kariyer_detail_page.dart` via shared-axis transition (loading/error/content states with quoted "Şart alanları" and apply button) whose success callback caches structured fields. Skeleton card loaders replace the initial spinner. Filters: title search, category chips, "Son 30 gün", optional place filter, live "N ilan" count; haptics on bookmark/filter/card open; saved searches are named chips with create/apply/rename/delete and per-search notification modes. `lib/ui/onboarding_page.dart` (fresh installs, ≤4 skippable steps) collects şehir/eğitim/yaş/KPSS, creates the "Sizin için" saved search and asks notification permission — fresh-install walkthrough verified on emulator. Settings/theme/Pro/About and banner slot unchanged. `napp_pro` product is `kamubul_pro_lifetime`; `napp_ads` provides policy/controllers. No assistant API or second-source scraper exists. Obfuscated release APK ran on emulator 2026-09-27: catalogue refresh, detail caching, bookmarks, saved searches, notifications and onboarding verified via UI automation.

### Notifications

**Status:** VERIFIED on Android emulator. `lib/notifications/alert_service.dart` wraps flutter_local_notifications (channel `kamubul_alerts`) and workmanager (12h periodic, connected constraint, `@pragma('vm:entry-point')` dispatcher). `lib/data/search_alerts.dart` holds the pure decision logic: per-saved-search instant/digest/off modes, per-search seen-URL sets, daily instant cap (6), quiet hours 22:00-08:00 suppress instant, digest fires once per day per search, deadline reminders once per saved listing within 3 days. Android manifest gained POST_NOTIFICATIONS/RECEIVE_BOOT_COMPLETED/WAKE_LOCK; app gradle enables core library desugaring (flutter_local_notifications requirement). Device-verified: primer → system permission granted → digest notification posted ("Kamu ozet: 177 yeni ilan"); instant suppressed during quiet hours by design. SettingsStore persists seen sets, digest days and the reminder list. iOS side unverified (no Apple host). In-app notification center and cross-source fingerprint dedupe are not built.

### Assistant (deterministic core)

**Status:** VERIFIED on Android emulator. `lib/listings/listing_guide.dart` renders the deterministic "Rehber yanıtı": the selected listing's KPSS türü/taban, yaş sınırı, eğitim and kota tipi answered from the PB-007 extraction pipeline, each field with its verbatim source sentence, unknowns shown as "belirtilmemiş"; reached via "Rehbere sor" on any listing card. No network AI, no key, no hallucination surface. The AI chat connection (central key or user key), dedicated profile editor and speech input remain blocked/pending TD-001/TD-003 decisions.

## External Dependencies

- Tagged `napp_kit` packages provide settings/theme, purchases and ads.
- Kariyer Kapısı public RSS is integrated; all other official sources are linked but not automatically fetched.

## Known Unknowns

- Access/redistribution terms and stable page structure for İŞKUR, ilan.gov.tr, Resmî Gazete and municipalities.
- Source freshness, extraction accuracy, iOS device behavior and store product configuration. Contact email is still a development placeholder if `CONTACT_EMAIL` is not supplied; do not publish with it. `PRIVACY.md` is a development disclosure, not final store review.
