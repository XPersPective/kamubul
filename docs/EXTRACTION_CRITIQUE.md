# Extraction interrogation — 2026-10-05

1. Previous fixes: 7468dfc preserved full table text; 257635f validated labels; a976a17 persisted all source identities and bounded inference; 60eaadf refreshed indexes while processing and removed hidden input truncation. They fixed data transport and budget symptoms, but did not fix the extraction contract: `workers/src/extract.js:15` requests only education, KPSS and age. No quota/date/position inventory contract exists there. I did not evaluate the complete named-notice corpus before publishing 13.
2. End-to-end divergence: official ilan.gov list → `sources.js:38` index with null deadline → `sources.js:68` full detail text only → `pipeline.js:183` condition-only inference → `pipeline.js:201` updates only requirementGroups → `listing_store.dart:617` shared projection → `home_page.dart:2134` quota chip and `official_listing_page.dart:277` quota display read the untouched null quota. The source contains a position table but the inference contract never requests its counts.
3. Defaults: Qwen runs first, all notices compete for 30 hourly / 150 daily calls (`wrangler.jsonc:24`); valid JSON ends external inference even with missing topics (`extract.js:246`). These defaults delay mechanically recoverable notices. They were insufficient for the user's current mechanical-first requirement.
4. Filtering: source HTML is converted to row-preserving plain text (`sources.js:24`); original text remains available. Groups are capped at 30 (`extract.js:98`), short/oversize inputs are marked checked (`pipeline.js:188`), empty results are marked checked (`pipeline.js:197`). Those checked flags conflate attempted and complete. The quota display does not count groups; “Kadro 1” is an index (`official_listing_page.dart:146`), misleading for a register application without vacancies.
5. Deletable behavior: unconditional AI-first scheduling and terminal success for empty/partial extraction must go. Shared cache, durable source text, queue budgets and native IDs serve the requirement and remain. I did not prove every legacy phone extraction helper is unreachable beyond previously audited active paths.
6. Verification: 243 Worker tests, build/signing and native offline exact-text reading passed. These do not prove quota/date/table extraction quality. Live D1 now confirms null quota in every named ilan.gov example, pending budget errors for Sabancı, Ahi Evran, ministry and TİBU, and checked empty groups for Eskişehir. I did not manually verify every official notice or real-phone typography before publication.
7. Simplest architecture: store each official notice and its complete text on the server. Extract explicit source metadata and table rows mechanically, validate against the same stored text, and call Qwen only for missing information. Persist one versioned result with evidence, completeness and provenance; both cards and details read it. Keep unknown values unknown, distinguish a register application from a vacancy, preserve original text offline, and show the requested AI warning when AI contributes.

## Verdict: architecture fights the requirement, rewrite the offending layer

### Findings
| # | Symptom (user's words) | Root cause (file:line) | Class | Severity | Decision it forces |
|---|---|---|---|---|---|
| 1 | kontenjan karta girmemiş | workers/src/extract.js:15; pipeline.js:201 | wrong contract | high | extract and persist notice metadata plus position counts with evidence |
| 2 | hâlâ birçoğu ayıklanamıyor | workers/src/pipeline.js:188; extract.js:246 | wrong completion state | high | mechanical first, explicit quality assessment, AI for gaps |
| 3 | kadro bir diyor | lib/listings/official_listing_page.dart:146 | misleading presentation | medium | distinguish position labels from person counts and register notices |
| 4 | ayrıntının mizanpajı çok kötü | lib/listings/official_listing_page.dart:253; 161 | layout | medium | compact facts, readable position sections and expandable evidence |

### Deleted (things this critique kills)
- AI-first default for every notice: mechanically recoverable facts must not consume the AI queue.
- Attempted-equals-complete flag: valid JSON or an empty result does not establish extraction quality.
- Generic numbered vacancy heading for a register application: a condition group is not a vacancy count.

### Kept under suspicion (with the exact test that would acquit it)
- Table flattening: acquittal test = real Sabancı/Ahi Evran/TİBU rows retain headers, counts and row-specific conditions.
- Shared client projection: acquittal test = incoming revision changes quota, dates and groups consistently on card and detail, including offline reload.
- Qwen cache: acquittal test = partial response is labeled partial, evidence rejects invented counts, and same version/text performs no repeat inference.

### Honest verification ledger
- Verified by me: code flow above; live named records have stored ilan.gov text but missing quotas and budget-limited extraction; previous automated and offline text checks.
- Only the user can verify: readability on their own phone and preferred visual density; this does not replace emulator, source and automated verification by me.
