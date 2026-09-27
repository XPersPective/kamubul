# Target Architecture — KamuBul

## Objective

Release a premium Flutter Android/iOS app for current Turkish public-sector jobs from official channels. Users discover relevant announcements, understand sourced conditions and open the original application page. The core is local and account-free. Restrained ads and lifetime Pro use the existing template. An in-app assistant is prepared for a secure API trial.

## Target State

### Sources and catalogue

- Cover Kariyer Kapısı, İŞKUR public jobs, ilan.gov.tr personnel, relevant Resmî Gazete notices, municipalities and other official institutions. Source registry records fetch method, parser version, rate limit, attribution and last success/failure.
- Prefer a published feed/API. When absent, fetch public HTML and structurally extract listings, details and official application links. Bound time/size/requests, validate links and fields, detect layout drift, and never bypass login/CAPTCHA. Parse PDF text only when reliable; otherwise present the original document. Source failure is visible and preserves cached listings.
- Fetch on open, manual refresh and best-effort background schedule; dedupe, expire and prune old unsaved listings. Store bookmarks locally. Never promise instant delivery from device-only polling.
- Tabs/categories: all, İŞKUR/public worker, personnel, municipality. Support profession, location and last-30-days filters. Listings can have multiple categories. Original application URL opens externally.

### Local experience

- Device database for announcements, bookmarks, optional profile, subscriptions, notification history and refresh state. No user registration or developer-owned server for the core.
- Local notifications for newly found matching announcements; permission and duplicate controls. Android/iOS scheduled checks are best effort. Manual refresh always works.
- Clear issuer, source, publication/deadline, location, profession and explicit conditions. Unknown conditions remain unknown. Accessible light/dark/system UI, responsive text/tablet and useful offline/empty/error states.
- Retain `ORTAK_UYGULAMA_STANDARDI.md` features: About, open-source/privacy/licenses, Turkish and English plus 71-language target, RTL, branded icon/splash, review/share, safe import/export, CI and release-device checks.

### Assistant — working label “İlan Rehberi”

- In-app text chat about an announcement: age/KPSS/education conditions, optional profile comparison, find relevant current/cached announcements. Cite exact source passage; say when a condition is not stated. Never claim eligibility or modify application code.
- Commands such as “benim için yeni ilanları bul” trigger the same bounded refresh/search service as the UI; the model cannot make arbitrary network requests or change app state without a visible user action. Questions like “35 yaş sınırı var mı?” and “60 KPSS gerekiyor mu?” must report the notice's actual wording and link.
- Prepare a testable API connection, request limits and cost metering. Never embed a developer-paid secret in the mobile app. Trial may use an opt-in user key stored securely or an explicitly approved minimal proxy. A central API requires an infrastructure decision. OS speech-to-text can follow text chat; live voice chat later.
- Optional system share sends only the selected official notice URL to a user-chosen assistant app; do not rely on ChatGPT or Gemini being installed or accepting a prestarted voice conversation.
- User mentioned “ALH” alongside the assistant; preserve the term until its intended meaning is clear, without inventing a separate service.

### Revenue

- Reuse `napp_ads` small banner, first-7-days/5-sessions fullscreen protection, consent and rewarded policy; no ad interrupts applications. Reuse `napp_pro` non-consumable lifetime purchase/restore. Pro sees no ads. Do not promise unlimited ongoing paid AI under one-time Pro.
- Evaluate a limited seven-day assistant trial only after actual per-user cost and abuse caps are measured. Ads are an uncertain offset, not a committed AI budget. Do not promise a subscription or price before the store economics are approved.

## UI blueprint for continuation

| Screen | Main content | Primary action | Required states |
| --- | --- | --- | --- |
| Announcements | Calm blue brand header, refresh age, search, horizontal category chips, cards with issuer/category/date/source/deadline | Open verified official application page | Loading, zero matching, offline with last known data, source failure |
| Detail | Official title, institution, place, dates, cited conditions, original notice/document | Apply on the official site | Unknown/expired deadline, unavailable original, saved |
| Saved | User bookmarks retained when source drops an item | Open or unsave | Empty, expired, offline |
| İlan Rehberi / ALH | Selected notice context, sourced chat transcript, optional profile, API consent/usage | Ask in text; later microphone | No API configured, quota reached, uncertain answer, provider failure |
| Sources | Each official source and its latest successful check/coverage status | Open source or retry | Source unavailable, parser changed |
| Settings | Category/location notifications, light/dark/system, profile/privacy, Pro, language, About | Save preferences or restore purchase | Permission denied, purchase pending/error |

Use `napp_core` theme tokens and brand color; 48dp minimum touch targets, readable contrast, large text, RTL-safe dates/numbers and tablet width cap. Free banner occupies its own slot and collapses on load failure; Pro has no reserved ad space. App-open ads appear only on a loading screen after the template's guard; neither reading nor applying has a fullscreen ad. Build the actual detail and source-status data from validated models, not decorative sample values.

## 10,000-user assistant budget checkpoint

At the [GPT-5.6 Luna list price](https://developers.openai.com/api/docs/models/gpt-5.6-luna) observed 2026-09-27 ($0.20/M input tokens, $1.20/M output tokens), 10,000 monthly users asking 2 / 10 / 50 questions each with 1,000/200, 2,000/400, 4,000/800 input/output tokens would cost about **$8.80 / $88 / $880 per month for model text only**. With 20% of users dictating 30 seconds per question at the then-listed [gpt-4o-mini-transcribe estimate](https://developers.openai.com/api/docs/pricing) of $0.003/min, add **$6 / $30 / $150**. These are illustrative, exclude hosting, tool calls, taxes and abuse, and must be recalculated against real token traces and current prices. Formula: `users × questions × (input_tokens × input_rate + output_tokens × output_rate) / 1,000,000`. Revenue requires real fill rate/eCPM and purchase conversion; never treat estimates as guarantees.

## Open Target Decisions

### TD-001 — Centrally paid AI

**Status:** OPEN. User wants the API ready to connect and test. A serverless binary cannot protect a centrally billed key. User-key and approved-proxy routes remain alternatives.

### TD-002 — Source access

**Status:** OPEN per source. User authorizes public page extraction when no feed/API exists. Before shipping, check source terms, automation limits and parser reliability; record blocked sources honestly.

### TD-003 — ALH

**Status:** OPEN. Meaning of “ALH” in the latest message is not established; do not omit it or assign it invented behavior.

## Success Conditions

- Real official listings appear with source and application links, refresh and persistence. Every requested source has an adapter or an explicit documented blocker.
- Categories, preferences and notifications work on release devices within platform limits.
- In-app assistant trial answers with source citations and no exposed developer key, with measurable caps/cost.
- Purchase restore and ad behavior pass real-device tests; Pro generates no ad requests.
- Analysis, tests, Android/iOS release, security/accessibility/privacy checks pass. Unverified work stays in tasks.
