# Phase 1 — Discovery + Ranking MVP

The top of the funnel. Goal: a local CLI that, given `--metro=austin --niche=contractor`, returns ~500 deduped, scored Austin home-service contractors ranked from "best lead" to "worst lead."

We deliberately keep this **local-first** — no Netlify deploys, no scheduled crawlers, no operator API. Just a script + Neon DB + the modular pieces that the rest of the system will reuse later. Once it works locally and we trust the rankings, we'll deploy as a scheduled function in Phase 1.5.

---

## Why local-first

Phase 0 has 14 steps to spin up 5 Netlify sites + Sentry + cert + DNS. None of that is on the path to "do we have a list of good leads to talk to?" By keeping discovery local for now we:
- Iterate fast on adapters, dedup, and scoring without redeploying.
- Test against the real Neon DB so the schema and queries are production-shape.
- Park the Netlify infra work and pick it up when we actually need a deployed surface.

---

## Sub-phases

### 1.0 — Minimum infra (~half day) 🤖 + 👤
Skip every Phase 0 step except the bare minimum to get a DB and a workspace.

- 🤖 Scaffold monorepo: root `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `tsconfig.base.json`, lint/format/CI configs, `.gitignore`.
- 🤖 Scaffold `packages/db` (Drizzle, Postgres) + `packages/shared` (env schema with Zod).
- 🤖 Initial schema migration: `business`, `business_source`, `contact`, `business_audit` (per the data model in `architecture.md`).
- 👤 Provision Netlify DB (Phase 0 Step 7) — *only* this step. Skip the 5 site creations. Paste the `NETLIFY_DATABASE_URL` back to me.
- 🤖 Run migrations against Neon.

✅ `pnpm db:studio` shows empty tables. Local toolchain works.

---

### 1.1 — Data source interface + Google Maps adapter (~1 day) 🤖 + 👤

Build the modular plug-in surface and one working adapter.

- 🤖 `packages/data-sources/src/types.ts` — the `DataSource` interface from `architecture.md`. Plus `RawBusinessRecord` shape, `DiscoveryQuery`, `EnrichmentPatch`.
- 🤖 `packages/data-sources/src/google-maps/` — adapter using the **Places API (New)**:
  - `searchText` for queries like `"HVAC contractor Austin TX"`.
  - `placeDetails` for the per-result detail fetch (hours, photos, website, etc.).
  - Pagination via `nextPageToken`.
  - Rate-limit aware: backoff + a cost counter logged per run so we don't get surprised.
- 🤖 Niche config in `packages/data-sources/src/niches/contractor.ts` — list of GMaps category strings + canonical seed queries:
  ```
  ['HVAC contractor', 'plumber', 'electrician', 'roofer', 'landscaper',
   'general contractor', 'remodeler']
  ```
- 🤖 Geography config: a `metros/austin.ts` with the Austin metro bounding box + a list of seed query strings combining each niche with each city/neighborhood.
- 👤 Provide `GOOGLE_PLACES_API_KEY` (Google Cloud Console → enable Places API (New) → create + restrict an API key).
- 🤖 `scripts/probe-gmaps.ts` — small script that runs ONE query (`"HVAC contractor Austin TX"`) and prints raw results. Smoke test before going wider.

✅ `pnpm tsx scripts/probe-gmaps.ts` prints 20 real Austin HVAC businesses with name, address, phone, website status. Logs API call count + cost estimate.

---

### 1.2 — Normalization + persistence (~1 day) 🤖

Pull from Google Maps into the DB.

- 🤖 `packages/core/src/normalize.ts` — converts a `RawBusinessRecord` into the shape we store: canonical name, address (street/city/state/zip parsed), phone (E.164), website URL (or null), category list, plus the raw payload preserved in `business_source.raw`.
- 🤖 `packages/core/src/ingest.ts` — pipeline: source iter → normalize → upsert into `business_source` (one row per source per business) → upsert into `business` (one canonical row, with `score` left null at this stage).
- 🤖 `scripts/discover.ts --metro=austin --niche=contractor [--limit=N] [--source=gmaps]`:
  - Loads the metro + niche configs.
  - Iterates seed queries through the configured sources.
  - Writes `business_source` rows. Lets dedup (next sub-phase) collapse to canonical `business` rows.
  - Persists a `discovery_run` row for audit (when we ran, source, query count, results count, cost estimate).
- 🤖 Add `discovery_run` table to the migrations.

✅ `pnpm tsx scripts/discover.ts --metro=austin --niche=contractor --limit=50` populates `business_source` with ~50 raw records and a single `discovery_run` row. Drizzle Studio shows the data.

---

### 1.3 — Deduplication (~1.5 days) 🤖

Collapse `business_source` rows into a single canonical `business` row each.

- 🤖 `packages/core/src/dedup.ts`:
  - Match keys (in priority order): exact phone (E.164) → exact website domain → fuzzy name + address (Levenshtein on normalized name + zip match).
  - Returns a match score + reason. Threshold splits into auto-merge / human-review / no-match.
  - Edge cases: businesses sharing a phone (suite numbers in addresses), franchises (chain name + different addresses must NOT merge).
- 🤖 `dedup_candidate` table: ambiguous matches that scored between auto-merge and no-match. Operator can resolve later via a script. For MVP, log + skip — we'll come back if it matters.
- 🤖 Dedup runs as a stage in `ingest.ts` after each source pull. Idempotent — re-running discovery doesn't duplicate.
- 🤖 `scripts/dedup-stats.ts` — prints counts: source rows, distinct businesses, ambiguous candidates, recent merges.

✅ Re-run `discover.ts` with the same args → no duplicate `business` rows. Manually inspect 20 random businesses in Drizzle Studio — none look like accidental merges or splits.

---

### 1.4 — Presence scoring (~1 day) 🤖

The "how weak is their online presence" score. Higher = better lead.

- 🤖 `packages/core/src/scoring/presence.ts`:
  - Inputs: a single `business` row with its `business_source` joins.
  - Signals (from data we already have via Google Maps):
    - **No website** → +50 pts.
    - **Website domain that 3xx-redirects, returns 4xx/5xx, or returns a parked-domain page** → +40 pts (synchronous HEAD/GET inside the scorer; cache result on the business row).
    - **Website is a Facebook/Yelp/LinkedIn URL (not a real site)** → +30 pts.
    - **Few or no photos** (<3 GMaps photos) → +10.
    - **No hours listed** → +5.
    - **No description** → +5.
    - **<10 reviews** → +5.
    - **GMaps "claimed" status unverified** → +10.
    - Composite score 0-150ish.
- 🤖 Weights live in `packages/core/src/scoring/weights.ts` — a typed object, easy to edit.
- 🤖 Scorer runs in batch over all businesses without a recent score: `scripts/score.ts --metro=austin`.
- 🤖 Persist `business.score` + `business.score_breakdown` (JSONB with each signal's contribution).

✅ All Austin contractors have a `score`. `select * from business order by score desc limit 25;` returns visibly weak-presence businesses (no site, parked domains, sparse listings).

---

### 1.5 — Value scoring + ranking (~half day) 🤖

The "how much is this lead worth if we land them" score.

- 🤖 `packages/core/src/scoring/value.ts`:
  - Signals:
    - **Review count** (capped, log-scaled — proxy for how busy they are). Not quality of reviews, just volume.
    - **Years in business** (if available from GMaps).
    - **Niche multiplier** from `weights.ts` (HVAC > general contractor > landscaper, tunable).
    - **Service-area indicator** (mobile service or storefront — both fine).
- 🤖 Composite ranking: `priority = presence_score * value_multiplier`. Stored on `business.priority`.
- 🤖 `scripts/list-top.ts --metro=austin --niche=contractor --limit=50` prints a clean table sorted by priority with reasons.

✅ Top 25 by priority all look like plausible "I would pay $50/mo for this" candidates. You eyeball-validate by clicking through 5 of them on Google Maps and nodding.

---

### 1.6 — Multi-source enrichment (~2-3 days) 🤖 + 👤

GMaps gives us *who exists*. Marketplace presence (Angi, HomeAdvisor, Thumbtack, Houzz) tells us *who is already paying for leads but hasn't built their own funnel* — the strongest possible buying signal for our offer. State licensing data validates *who is a legit licensed business*.

All sources here run in **enrich mode**: they attach `business_source` rows to existing businesses (matched via the dedup keys from 1.3), feed signals into scoring, and only add a new `business` row when they find something GMaps genuinely missed.

#### 1.6a — Yelp Fusion (~half day) 🤖 + 👤
The clean one. Real API, generous limits.
- 👤 Provide `YELP_API_KEY` (Yelp Fusion developer portal).
- 🤖 `packages/data-sources/src/yelp/` adapter using `businesses/search` + `businesses/{id}`.
- Signals added: Yelp review count, Yelp rating, Yelp claimed status, "no Yelp profile" flag.

#### 1.6b — Texas state licensing (~half day) 🤖
High-quality government data. Bulk download, no API key, no scraping risk.
- TDLR (Texas Department of Licensing and Regulation) — covers HVAC, electrical, and several other trades. Bulk CSV of active license holders is publicly downloadable.
- TSBPE (Texas State Board of Plumbing Examiners) — separate board for plumbers, also has public license lookup.
- 🤖 `packages/data-sources/src/tx-licensing/`:
  - Periodic bulk-download script (monthly is enough — licenses don't churn fast).
  - Match by name + phone + zip; ambiguity goes to the dedup-candidate queue.
- Signals added: license type(s), license number(s), license active/expired status, years licensed.
- Why this matters: a contractor with no website but an active TDLR HVAC license is a high-confidence real business — strong positive signal vs. someone we can't verify exists.

#### 1.6c — Marketplace presence checks (~1.5 days) 🤖 + 👤
Honest framing: **none of these have public APIs, all have anti-bot protections.** We do *presence checks only* (does this business have a profile here? what's the review count?), not full crawls. One HTTP request per business per marketplace, polite delays, realistic User-Agent. Treat results as best-effort — when we get blocked or hit a captcha, we skip and log, we don't retry forever.

Adapters:
- `packages/data-sources/src/marketplaces/angi/`
- `packages/data-sources/src/marketplaces/homeadvisor/` (same parent as Angi, often shares profile data)
- `packages/data-sources/src/marketplaces/thumbtack/`
- `packages/data-sources/src/marketplaces/houzz/` (remodelers, cabinet folks, designers)

Each implements:
```ts
interface MarketplaceAdapter {
  id: string;
  presenceCheck(business: Business): Promise<MarketplacePresence | null>;
}
type MarketplacePresence = {
  found: boolean;
  profileUrl?: string;
  reviewCount?: number;
  rating?: number;
  yearsOnPlatform?: number;
  badges?: string[];   // "Top Pro", "Elite Service", etc. — signal of investment
};
```

Operational rules:
- Per-adapter rate limit: max 1 request/second.
- Per-adapter circuit breaker: if 3 consecutive requests return blocking responses (403/captcha/Cloudflare challenge), halt that adapter for the run.
- Cache results for 30 days — same business, same marketplace, no re-fetch.
- Headless browser (Playwright) only if plain HTTP doesn't work; chromium spin-up costs more, use sparingly.
- ToS: we crawl public pages at human-rate volumes for our own evaluation. Document this; don't overdo it.

#### Scoring signals added by 1.6
These get added to `packages/core/src/scoring/presence.ts` and `value.ts`:
- **Listed on Angi/HomeAdvisor/Thumbtack but no own website** → +25 pts presence (high-intent: already paying for leads).
- **Listed on 3+ marketplaces** → +10 pts value (busy enough to spread across platforms = real money on the line).
- **High review count on a marketplace + low review count on Google** → +5 pts presence (their funnel is the marketplace, not their own brand).
- **Active state license** → +10 pts value (verified real business).
- **No marketplace presence + no website + claimed on GMaps** → -10 pts presence (probably small/local-only/not buying leads, less likely to convert).

#### 1.6 deliverables
- 🤖 All adapters above implemented.
- 🤖 `scripts/enrich.ts --metro=austin --niche=contractor [--source=yelp|angi|...|all]` runs enrichment over the existing `business` table.
- 🤖 Scoring re-run picks up the new signals.
- 🤖 `scripts/enrichment-stats.ts` prints per-source coverage (% of businesses for which we got data, % blocked, average response time).

✅ At least 60% of Austin contractors have ≥1 enrichment source row beyond GMaps. Top-25 ranking visibly shifts after enrichment in a way that improves eyeball quality (1.7 should re-validate post-enrichment).

---

### 1.7 — Manual tuning + golden-set validation (~half day) 👤 + 🤖

Sanity check before automation.

- 👤 Pick 10 businesses from the top-50 list. For each, manually rate "good lead" / "meh" / "no" based on a 30-second look at their online presence.
- 👤 Pick 10 from the bottom 100. Same exercise.
- 👤 Tell me where the rankings are wrong.
- 🤖 We adjust weights (`scoring/weights.ts`) iteratively. Save the validation set as `scripts/golden-set.ts` so we can re-evaluate the rankings against it whenever we change weights.

✅ At least 7 of the top 10 feel like real leads. At least 8 of the bottom 10 feel like rightly-deprioritized ones.

---

### 1.8 — Phase 1 done-criteria check 🤖

- [ ] `pnpm tsx scripts/discover.ts --metro=austin --niche=contractor` runs end-to-end with no errors.
- [ ] `pnpm tsx scripts/enrich.ts --metro=austin --niche=contractor --source=all` runs end-to-end with no errors.
- [ ] At least 500 unique Austin contractors in the `business` table.
- [ ] Every business has a `score`, `priority`, and at least one `business_source` row.
- [ ] At least 60% of businesses have ≥1 enrichment source row (Yelp / TX license / marketplace) on top of GMaps.
- [ ] Re-running discovery + enrichment does not create duplicates.
- [ ] Dedup stats: <5% of records flagged as ambiguous candidates needing manual review.
- [ ] Top-25 by priority passes eyeball validation, post-enrichment.
- [ ] Cost report: total Google Maps spend documented (<$10 for ~500 records). Marketplace adapters' block-rate documented; coverage acceptable per our judgment.

✅ Phase 1 done. Move to Phase 2 (Demo site generator) — we have a queue of leads ready to receive demos.

---

### 1.9 — Deferred from Phase 1 (next when needed)

- Scheduled re-scans (becomes a Netlify Scheduled Function). Wait until we know how often we want fresh data.
- Additional enrichment sources we can add later if signal quality demands: Facebook Pages, BBB, Yellow Pages, Nextdoor (limited partner API only), Porch, Bark, Texas SOS general business registrations.
- Headless-browser fallback for marketplaces that hard-block plain HTTP — only build this if presence-check coverage from 1.6c is too low to be useful.
- The operator API for inspecting/editing scoring weights — direct DB / `weights.ts` edit is fine for now.
- Owner-contact discovery (email/phone for the actual person). Belongs to Phase 3 (Outreach), not discovery.
- Conversion-data feedback loop into scoring weights. Needs conversion data to exist first — Phase 7+.

---

## Required from you before we start

| Item | When needed | Where to get it |
|---|---|---|
| `NETLIFY_DATABASE_URL` | Sub-phase 1.0 | Provision Netlify DB per Phase 0 Step 7, paste the env var value back here |
| `GOOGLE_PLACES_API_KEY` | Sub-phase 1.1 | Google Cloud Console → enable **Places API (New)** → create restricted key |
| `YELP_API_KEY` | Sub-phase 1.6a | Yelp Fusion developer portal |
| (no key needed) | Sub-phase 1.6b | TDLR + TSBPE bulk downloads are public |
| (no key needed) | Sub-phase 1.6c | Marketplace adapters are public-page presence checks |

Plus a one-time decision before we start coding:

1. **1.6 scope.** Do you want all three sub-pieces (Yelp + TX licensing + marketplaces), or trim? Recommend **all three** — Yelp is cheap, TX licensing is free + high-value, marketplaces are the real differentiator for our buying-signal model.
2. **Marketplace ToS posture.** I'm proposing public-page presence checks at human-rate volumes. Acceptable risk to you, or do you want to skip 1.6c and rely on 1.6a + 1.6b only?
3. **Cost ceiling for the first Austin run?** Recommend **$10 hard cap** on Google Maps spend (tracked live, aborts on hit).
4. **Ranking persistence:** keep score history or just current score? Recommend **just current** for MVP, with `business_audit` capturing changes if we ever care.

Answer those + provide the keys, and I start at sub-phase 1.0.
