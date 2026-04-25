# MVP Plan — 10 Paying Austin Contractors

Goal: 10 active $50/mo subscribers, all home-service contractors in Austin metro.

Constraint: single operator (you) + AI coding assistance. Keep infra small, defer anything not directly on the conversion path.

## Phases

### Phase 0 — Foundations (week 1)
Stand up scaffolding so all later work has a place to land. **All-Netlify, no AWS.** Walk-through in `phase-0-plan.md`.
- Monorepo (pnpm + Turborepo), TypeScript, shared ESLint/Prettier.
- Five Netlify sites in one repo: `apps/landing`, `apps/api`, `apps/live-sites`, `apps/assistant`, `apps/workers`. Each connected to GitHub for auto-deploy. **No operator dashboard** — operators use the bearer-auth'd API + scripts + DB.
- Provision **Netlify DB (Neon Postgres)**. `packages/db` (Drizzle) with initial migrations (`business`, `business_source`, `contact`, `business_audit`).
- **Inngest** wired to `apps/workers` for durable workflows / cron / fan-out / retries.
- **Resend** account + Sentry project. Env vars in Netlify per site.
- (Optional, only if domain ready) Custom domains: apex → landing, `api.` → operator API, `*.` wildcard → live-sites. (`dash.growonline.app` reserved for a future operator UI; unused at MVP.)
- **Done when:** all 5 sites build green, `db.healthcheck` Inngest function runs end-to-end against Neon, Sentry captures errors from web + workers, CI green on `master`.

### Phase 1 — Discovery for Austin contractors (week 2)
Narrow, focused discovery — just enough to produce a candidate list.
- `packages/data-sources` interface.
- Adapters: Google Maps Places, Yelp Fusion, Texas SOS business registrations, simple Facebook page scraper.
- Dedup pipeline: normalize + fuzzy-merge, write to `business`.
- Presence scoring config (YAML) + scorer in `packages/core`.
- One-off CLI: `pnpm discover --metro=austin --niche=contractor`.
- **Done when:** 500+ Austin contractor records in DB, deduped, scored. Human can eyeball top 50 and nod.

### Phase 2 — Demo site generator (weeks 3-4)
The wow factor. This is where most eng time lives.
- `apps/demo-template-contractor` — one polished Next.js contractor template, static-exportable. Hand-designed (not AI-generated) for the first version — needs to look real.
- `packages/sitegen`:
  - Template fork into tmp workspace.
  - Claude code-edit loop to customize copy + image selection.
  - `next build` static export, upload artifacts to **Netlify Blobs** under `demos/{slug}/v{N}/`.
  - Update `demo_site.current_version` pointer.
- Inngest function `sitegen.build` orchestrates the steps above, triggered for the top-N scored businesses.
- `apps/live-sites` middleware reads the host header → looks up `slug.current_version` → serves the matching blob prefix. Same app handles demo and live tenants.
- Wildcard custom domain `*.growonline.app` on the `growonline-live-sites` Netlify site (Pro tier required).
- Photo pipeline: Google Maps photos → stock fallback → AI-gen last resort.
- **Done when:** 25 demo sites live at real subdomains, each convincingly personalized. You show 3 to non-tech friends, they believe they're real.

### Phase 3 — Outreach (week 5)
Email only for MVP. SMS/postcard deferred.
- SES production access, 2-3 warmed subdomains.
- `packages/outreach` channel interface + SES email adapter.
- Rule engine with one playbook for contractors: day-0 email, day-3 follow-up, day-10 final.
- LLM-authored personalization (hyper-personalized per business) with prompt caching.
- Human-in-loop review via the operator API: drafts are persisted with status `pending_review`. Operator runs `pnpm tsx scripts/outreach-review.ts` to list/edit/approve/reject — script wraps `GET /outreach/pending` + `POST /outreach/:id/approve|reject`.
- Unsubscribe link + do-not-contact list enforcement.
- Inbound reply tracking (SES inbound → `outreach_event`).
- **Done when:** 50 emails sent (operator-approved), open/click tracking working, at least 1 reply.

### Phase 4 — Conversion + live site (week 6)
Turn a demo into a paying customer.
- Stripe product + price ($50/mo). Checkout link on every demo.
- Stripe webhook → customer record + magic-link email.
- Multi-tenant live-site Next.js app on Netlify (`apps/live-sites`): reads business config from DB, renders same template dynamically. Routed via subdomain.
- On conversion, flip demo subdomain to serve the live app instead of the S3 static. 301 at the edge.
- **Done when:** end-to-end test — demo → Stripe test payment → magic-link click → live site visible at subdomain.

### Phase 5 — Assistant (week 7)
The retention story.
- Twilio number provisioned, webhook points at `apps/assistant`.
- Claude tool-use loop with tools: `get_business_data`, `propose_site_change`, `apply_site_change`, `create_operator_task`.
- Site changes generate a preview (rebuild to a `{slug}-preview` subdomain) and require explicit "yes".
- `change_log` + undo-last-change tool.
- Operator inbox for escalations.
- Identity: phone-number match at signup, reject others.
- **Done when:** you text the assistant as a test customer, change hours + swap a photo, and the live site updates after confirmation.

### Phase 5.5 — Landing page + free analysis (week 7, parallel with assistant)
Inbound funnel. Can be built in parallel with the assistant since they share no code.
- `apps/landing` on Netlify at `growonline.app`: hero, how-it-works, sample gallery, pricing, contact, analyze CTA.
- `/analyze` form (URL + email, hCaptcha, MX check) → `POST /api/analyze` → `analysis_request` row + SQS job.
- `worker-analysis`: headless Chrome Lighthouse runner + reuse presence-scoring checks (NAP, GBP, directories). Writes report JSON.
- SES email with the report + CTA to an auto-built demo (triggers `worker-sitegen` against the submitted business).
- `/contact` form → `contact_submission` + `operator_task` + operator email.
- Legal pages: privacy, terms, unsubscribe handler.
- **Done when:** submit a URL as a test user, receive a real report email within 5 minutes with a working demo link. Contact form delivers to operator inbox.

### Phase 6 — Weekly report + GBP request (week 8)
- LLM-generated weekly email using: site analytics (Vercel), review deltas (GBP API read-only once linked), outreach activity.
- AI-drafted GBP manager-access request sent on day-1 of each customer relationship. Human reviews, then sends.
- **Done when:** first customer receives week-1 report.

### Phase 7 — Launch to Austin (weeks 9-12)
Ship outreach, iterate, hit 10 paying.
- Build demos for top 300 scored Austin contractors.
- Send 50/week with human review.
- Reply-handling loop: AI drafts reply, human approves.
- Tune: scoring weights, template design, copy, subject lines based on what converts.
- **Done when:** 10 active $50/mo subscribers.

## Deferred (explicitly not in MVP)
- SMS and postcard outreach channels
- Voice assistant
- Directory auto-submission (human does these manually for first 10 customers)
- Domain research / purchase automation
- Square/Toast/Clover review integration
- Demo-expiration re-engagement landing page
- Operator UI of any kind (we use API + scripts + DB instead; `dash.growonline.app` reserved if ever needed)
- Tiered pricing
- White-label / multi-tenant for agencies
- PII compliance tooling
- Automatic scoring-weight learning (manual tuning only)
- AI-generated templates (one hand-designed template suffices)
- Niches beyond contractors
- Metros beyond Austin

## Risks + mitigations
| Risk | Mitigation |
|---|---|
| Cold email deliverability tanks | SES + warmed subdomains + human review + low daily volume until reply rate is healthy |
| Demo quality not convincing | Hand-design template; validate with 3 non-tech friends before any outreach |
| Google Maps API costs spike | Only hit Places API for top-scored leads (tiered rescan) |
| Claude code-gen produces broken sites | CI-level `next build` gate in sitegen pipeline; fail loudly, don't publish |
| No replies at all | Cut message length, personalize harder, switch to postcard or door-knocking as a manual backup |
| Low reply → conversion rate | Add a phone number on the demo for direct call; manual conversion for the first 10 is fine |
| Stripe / payment edge cases | Human review on every failed payment |

## Operational cadence during launch (Phase 7)
- Daily: review outreach drafts queue, approve/edit/send 10-15.
- Daily: check reply inbox, respond within 4h.
- Weekly: re-score and add new candidates from fresh discovery runs.
- Weekly: review conversion data, adjust scoring weights manually.

## Definition of Done (MVP)
- 10 customers paying $50/mo via Stripe.
- Each has a live site on their subdomain.
- Each has received at least one weekly report.
- At least 3 have made a change via the SMS assistant.
- No more than ~5 hours/week operator time to keep the system running (excluding feature work).
