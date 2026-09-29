# Target Architecture — KamuBul

## Objective

Release a premium Flutter Android/iOS app for current Turkish public-sector jobs from official channels. Users discover relevant announcements, understand sourced conditions and open the original application page. The app is account-free. **Revision 2026-09-29:** a serverless Firebase/Google Cloud backend (no self-managed host) fetches official sources on a schedule, extracts structured fields, serves a read-only JSON catalogue and sends FCM push notifications for the user's saved searches; the app reads that catalogue and keeps a local cache. The backend has no UI. Restrained ads and lifetime Pro use the existing template.

## Target State

### Sources and catalogue

- Cover Kariyer Kapısı, İŞKUR public jobs, ilan.gov.tr personnel, SBB Kamu İlanları, municipalities and other official institutions. **Resmî Gazete is out of scope (2026-09-29)**: it produced no recruitment notices; its adapter is removed from the backend and later from the app. Only jobs in Türkiye (public personnel and public worker notices) are in scope; the earlier geo note is a technical fact about the source (SBB may reject non-TR IPs), not a content filter. Source registry records fetch method, parser version, rate limit, attribution and last success/failure.
- **Official channels only.** Competitor apps and aggregators (memurlar.net, kariyer.net, news portals, store scrapes) are never data sources; they are feature research only. Every listing carries its official source and application URL.
- Prefer a published feed/API. When absent, fetch public HTML and structurally extract listings, details and official application links. Bound time/size/requests, validate links and fields, detect layout drift, and never bypass login/CAPTCHA. Parse PDF text only when reliable; otherwise present the original document. Source failure is visible and preserves cached listings.
- Feasibility facts (checked 2026-09-28): Kariyer Kapısı publishes RSS and its own site uses a public listing JSON read call, both integrated. İŞKUR public search remains behind a WAF/session flow; ilan.gov.tr public search gateway is not yet validated. [Resmî Gazete robots.txt](https://www.resmigazete.gov.tr/robots.txt) does not disallow crawling and archive paths are predictable (`/eskiler/YYYY/MM/YYYYMMDD.htm`); [kamuilan.sbb.gov.tr](https://kamuilan.sbb.gov.tr) may block non-Turkish IPs. Record geo/robots constraints in the source registry and verify usage terms before release.

### Structured listing data — extraction pipeline

- Internal schema v1 per listing: title, institution, unvan, şehir/il, kontenjan (number of positions), deadline (validThrough), datePosted, education requirement, KPSS puan türü + taban puan, yaş sınırı, quota type (kadro/işçi, 4/B, 375/B, engelli, eski hükümlü), conditions text, official application URL, source citations. Age limit and KPSS fields have no schema.org equivalent — they are custom extension fields in the internal schema (standard reference: [schema.org JobPosting](https://schema.org/JobPosting), [Google Job Posting](https://developers.google.com/search/docs/appearance/structured-data/job-posting)).
- Deterministic per-source parsers run first. An AI extractor may run as a **candidate generator** (returns JSON against the schema), but a field enters the app only after three mechanical gates: strict JSON-schema validation, a verbatim source quote located in the fetched text for that field, and a per-field confidence threshold. A field failing any gate stays "unknown" and the raw sentence is shown instead (structured-output guarantees schema shape, not truth — [OpenAI Structured Outputs](https://openai.com/index/introducing-structured-outputs-in-the-api/), [Gemini responseSchema](https://ai.google.dev/gemini-api/docs/structured-output)).
- Every value parsed from free text displays its quoted source sentence on demand; source-native structured properties retain their official field and URL as evidence. Unknown stays explicitly "belirtilmemiş".
- Accuracy bar: before any extractor ships, per-field precision/recall is measured on a labeled set of real announcements (≥50 per source). Extractors below the recorded bar degrade to raw-text display. PDF parsing only when born-digital and table-aware; scanned or chaotic PDFs show the original document ([PDF parsing study](https://arxiv.org/html/2410.09871v1)).
- **Backend fetch (revision 2026-09-29):** Cloud Scheduler triggers a Cloud Run job (Dart, reusing the shared parsers) about three times a day at reasonable intervals; per-source polite rate limits, bounded time/size, layout-drift detection and visible per-source status. The job writes the catalogue (Firestore) and publishes a gzipped static snapshot (`/v1/listings.json`, Firebase Hosting CDN) so client reads do not incur Firestore per-read cost. The app also fetches on open and manual refresh, dedupes, expires and prunes old unsaved listings, and stores bookmarks locally. The embedded on-device fetch remains a fallback until the backend is proven. İŞKUR and ilan.gov.tr from server IPs must be re-tested live; if still blocked, record the blocker honestly and never bypass a WAF, login or CAPTCHA.
- Tabs/categories: all, İŞKUR/public worker, personnel, municipality. Support profession, location and last-30-days filters. Listings can have multiple categories. Original application URL opens externally.
- **Default filters ship out of the box**: şehir/ilçe, yaş aralığı, eğitim, KPSS puan türü, kurum, unvan, kontenjan, quota type, date. Users create **saved searches ("etiketler")** — named, reusable filter sets combining any fields — edit them anytime, and apply them as one-tap tabs. The optional local profile (şehir, yaş, eğitim, KPSS skoru) feeds a match highlight on listings ("profiline uygun") and pre-fills the first saved search during onboarding.

### Local experience

- Device database for announcements, bookmarks, optional profile, subscriptions, notification history and refresh state. No user registration. **Revision 2026-09-29:** the backend stores only an anonymous device ID (Firebase Anonymous Auth + App Check), the FCM token and the saved-search filters needed for matching; a "delete my notification data" control removes them; the local profile stays local except the filter fields inside a saved search.
- Notifications are keyed to saved searches, not just categories: each saved search has its own mode — instant / daily digest / off — plus an optional deadline reminder (X days before the application deadline). Cross-source reposts dedupe to one notification; digests run in daytime windows with quiet hours; overflow lands in an in-app notification center; taps deep-link to the listing ([Apple HIG Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)). Permission and duplicate controls; **server-side FCM push (revision 2026-09-29)** matches new listings to each device's saved-search filters deterministically and sends instant or digest pushes within quiet hours and the daily cap; delivery is still best effort at the platform level, and manual refresh always works. Deadline reminders may stay local. A soft pre-permission explanation appears at a high-intent moment (after the first saved search), never on first launch.
- Clear issuer, source, publication/deadline, location, profession and explicit conditions. Unknown conditions remain unknown. Accessible light/dark/system UI, responsive text/tablet and useful offline/empty/error states.
- Retain `ORTAK_UYGULAMA_STANDARDI.md` features that fit this product: About, open-source/privacy/licenses, branded icon/splash, review/share, safe import/export, CI and release-device checks. The interface is Turkish only, as the user explicitly specified on 2026-09-27.

### Server-side AI extraction and summary (revision 2026-09-29)

- After the deterministic parsers, the backend calls an LLM (Gemini API or Vertex AI with the developer's own key/service account, held only on the server) **once per new listing**, not per user or per tag: it returns candidate structured fields and a short bullet summary. Cost is independent of the user count.
- A consumer Gemini subscription does not grant API access; the API/Vertex is billed separately. The developer chooses the provider and budget; the key never enters the app.
- Every AI field passes the three C-005 gates (strict schema, verbatim quote located in the fetched text, confidence threshold). Failing fields stay "belirtilmemiş" with the raw sentence. Summaries are labelled as AI summaries. Tag matching stays deterministic on validated fields; the model never decides eligibility or matches.
- Measure real token cost and precision/recall on the labeled corpus before enabling any AI field in production.

### Assistant — working label “İlan Rehberi”

- In-app text chat about an announcement: age/KPSS/education conditions, optional profile comparison, find relevant current/cached announcements. Cite exact source passage; say when a condition is not stated. Never claim eligibility or modify application code.
- Commands such as “benim için yeni ilanları bul” trigger the same bounded refresh/search service as the UI; the model cannot make arbitrary network requests or change app state without a visible user action. Questions like “35 yaş sınırı var mı?” and “60 KPSS gerekiyor mu?” must report the notice's actual wording and link.
- Prepare a testable API connection, request limits and cost metering. Never embed a developer-paid secret in the mobile app. Trial may use an opt-in user key stored securely or an explicitly approved minimal proxy. A central API is now possible through the same Firebase/Cloud Run backend with caps and cost metering. OS speech-to-text can follow text chat; live voice chat later.
- Optional system share sends only the selected official notice URL to a user-chosen assistant app; do not rely on ChatGPT or Gemini being installed or accepting a prestarted voice conversation.
- User mentioned “ALH” alongside the assistant; preserve the term until its intended meaning is clear, without inventing a separate service.
- The assistant is **phase 2** and premium-grade: it reuses the extraction pipeline's quote-grounded field evidence, so any fact it states about a listing is the same cited evidence the UI shows — the assistant never invents a structured field.

### Revenue

- Reuse `napp_ads` small banner, first-7-days/5-sessions fullscreen protection, consent and rewarded policy; no ad interrupts applications. Reuse `napp_pro` non-consumable lifetime purchase/restore. Pro sees no ads. Do not promise unlimited ongoing paid AI under one-time Pro.
- Evaluate a limited seven-day assistant trial only after actual per-user cost and abuse caps are measured. Ads are an uncertain offset, not a committed AI budget. Do not promise a subscription or price before the store economics are approved.

## Competitor landscape (researched 2026-09-27)

- [İŞKUR Mobil](https://play.google.com/store/apps/details?id=tr.gov.iskur.iskurapp&hl=tr): 1M+ installs, **2.91★/55K reviews**. Applications, CV, tracking — but poor stability/UX complaints and no kamu-kadro discovery, no structured conditions, no quality alerts. No public API (institution-only SOAP).
- [memurlar.net](https://play.google.com/store/apps/details?id=net.memurlar&hl=tr): 1M+ installs, 4.0★. News + salary + ilan mix; top complaint is ads burying content; ilanlar are raw news text with no structured filters.
- [Kamu Kadro](https://play.google.com/store/apps/details?id=com.kamukadro.app&hl=tr): only ~100 installs but the closest analog — profile matching, deadline reminders, structured detail screen, filters (kurum/şehir/unvan/eğitim/KPSS), bookmarks. Immature; proves the concept is open.
- [Güncel Kamu İlanları](https://play.google.com/store/apps/details?id=com.mtlive.guncelkamuilanlari&hl=tr): stale since 2022; its liked 18:00 daily digest is the notification pattern users remember.
- Official portals ([Kariyer Kapısı](https://kariyerkapisi.gov.tr/isealim), ilan.gov.tr, kamuilan.sbb.gov.tr): mandatory application channels but **no discovery, no alerts, no mobile app** — they host applications, not candidate experience. KPSS prep apps (Bilgi Sarmal, Yediiklim) carry no ilan tracking at all.
- General TR job apps set the alert UX bar: kariyer.net "İş Alarmı" (saved-search alerts on every search screen).
- **Differentiation targets — every one must exist in KamuBul:** structured per-listing fields with quoted evidence (no incumbent has it at scale); saved-search tags with instant/digest modes + deadline reminders; local-profile match highlight; official-source badge with cross-source dedupe; freshness guarantee with visible per-source status; ad-light reading (no news clutter); offline saved listings; special-quota filters (engelli, eski hükümlü, 4/B, 375/B); premium dark/light accessibility; phase-2 grounded assistant.

## UI blueprint for continuation

| Screen | Main content | Primary action | Required states |
| --- | --- | --- | --- |
| Announcements | Calm blue brand header, refresh age, search, horizontal category chips, cards with issuer/category/date/source/deadline | Open in-app listing detail | Loading, zero matching, offline with last known data, source failure |
| Detail | Official title, institution, place, dates, cited conditions, original notice/document | Apply on the official site | Unknown/expired deadline, unavailable original, saved |
| Saved | User bookmarks retained when source drops an item | Open or unsave | Empty, expired, offline |
| İlan Rehberi / ALH | Selected notice context, sourced chat transcript, optional profile, API consent/usage | Ask in text; later microphone | No API configured, quota reached, uncertain answer, provider failure |
| Sources | Each official source and its latest successful check/coverage status | Open source or retry | Source unavailable, parser changed |
| Settings | Category/location notifications, light/dark/system, profile/privacy, Pro, language, About | Save preferences or restore purchase | Permission denied, purchase pending/error |

Use `napp_core` theme tokens and brand color; 48dp minimum touch targets, readable contrast, large text, Turkish dates/numbers and tablet width cap. Free banner occupies its own slot and collapses on load failure; Pro has no reserved ad space. App-open ads appear only on a loading screen after the template's guard; neither reading nor applying has a fullscreen ad. Build the actual detail and source-status data from validated models, not decorative sample values.

**Premium UX system — hard requirements.** Material 3 Expressive direction ([m3.material.io](https://m3.material.io/blog/material-3-expressive)): dynamic color from brand tokens, physics-based spring motion that is interruptible, shape-morph state changes, expressive typography. Official M3E widgets are not fully stable in Flutter ([status](https://docs.flutter.dev/ui/design/material/material-3)) — build with current Material 3 APIs and adopt M3E widgets as they land. Lists use skeleton loaders, never bare spinners ([NN/g](https://www.nngroup.com/articles/progress-indicators/)); list→detail uses hero/shared-axis transitions ([Material motion](https://m3.material.io/styles/motion/overview-system)); every tappable surface answers within 100 ms; haptics on save, filter commit and apply ([Flutter HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html)). Filter chips lead to a bottom-sheet panel showing a live result count before applying ([NN/g bottom sheets](https://www.nngroup.com/articles/bottom-sheets/)). The detail screen shows title, kurum, şehir, kontenjan, a deadline countdown badge and a sticky apply CTA above the fold; conditions render as scannable chips, each backed by its quoted source sentence. Empty/error/offline states are plain-language with a next action; offline shows last cached data. Onboarding is ≤4 skippable steps that create the profile and the first saved search. Accessibility is a hard bar: WCAG AA contrast ([WCAG 2.2](https://www.w3.org/WAI/WCAG22/quickref/)), 48dp targets, Semantics labels for TalkBack/VoiceOver, no clipping at 1.3x text scale, light/dark parity.

## 10,000-user assistant budget checkpoint

At the [GPT-5.6 Luna list price](https://developers.openai.com/api/docs/models/gpt-5.6-luna) observed 2026-09-27 ($0.20/M input tokens, $1.20/M output tokens), 10,000 monthly users asking 2 / 10 / 50 questions each with 1,000/200, 2,000/400, 4,000/800 input/output tokens would cost about **$8.80 / $88 / $880 per month for model text only**. With 20% of users dictating 30 seconds per question at the then-listed [gpt-4o-mini-transcribe estimate](https://developers.openai.com/api/docs/pricing) of $0.003/min, add **$6 / $30 / $150**. These are illustrative, exclude hosting, tool calls, taxes and abuse, and must be recalculated against real token traces and current prices. Formula: `users × questions × (input_tokens × input_rate + output_tokens × output_rate) / 1,000,000`. Revenue requires real fill rate/eCPM and purchase conversion; never treat estimates as guarantees.

## Open Target Decisions

### TD-001 — Centrally paid AI

**Status:** DIRECTION DECIDED 2026-09-29. The user will use their own API key (Gemini API/Vertex) held server-side in the Firebase/Cloud Run backend for extraction and summaries; the app never carries the key. A free-form in-app assistant remains phase 2 behind caps and cost metering.

### TD-002 — Source access

**Status:** OPEN per source. User authorizes public page extraction when no feed/API exists, including from the backend at reasonable intervals. Server IP reachability (İŞKUR WAF, ilan.gov.tr session gate, SBB geo) must be tested live before claiming coverage. Redistribution of listings from the backend requires a terms check. Before shipping, check source terms, automation limits and parser reliability; record blocked sources honestly. Known technical realities (2026-09-27 research, see Sources and catalogue): SPA-internal endpoints, SBB non-TR geo-block, per-site usage terms — each adapter must ship with honest per-source status and fixtures.

### TD-003 — ALH

**Status:** OPEN. Meaning of “ALH” in the latest message is not established; do not omit it or assign it invented behavior.

## Success Conditions

- Real official listings appear with source and application links, refresh and persistence. Every requested source has an adapter or an explicit documented blocker.
- Every source-native structured field is type/range and origin validated; every text-derived field is schema-validated and backed by a verbatim source quote. Per-field precision/recall on labeled real samples meets the recorded bar before a text extractor ships; failing fields degrade to raw text, never to guessed values.
- Saved searches ("etiketler") with default filters work; notifications honor per-search instant/digest modes, dedupe, quiet hours and deadline reminders on release devices within platform limits.
- Premium UX bar passes review: skeleton loaders, spring transitions, haptics, deadline countdowns, WCAG AA contrast, 48dp targets, 1.3x text scale, light/dark parity — verified on release devices.
- In-app assistant trial answers with source citations and no exposed developer key, with measurable caps/cost.
- Purchase restore and ad behavior pass real-device tests; Pro generates no ad requests.
- Analysis, tests, Android/iOS release, security/accessibility/privacy checks pass. Unverified work stays in tasks.
