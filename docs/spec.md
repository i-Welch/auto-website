# Product Spec — AI-Native Digital Agency for SMBs

## One-liner
Autonomous system that discovers SMBs with weak online presence, builds personalized demo websites, runs multi-channel outreach, converts them to a $50/mo subscription, and manages their ongoing online presence via an AI text assistant.

## Target (MVP)
- **Niche:** Home-service contractors (HVAC, plumbing, electrical, roofing, landscaping).
- **Geography:** Austin metro.
- **Success:** 10 paying customers at $50/mo.

## Core loop
1. **Discover** businesses from modular data sources.
2. **Enrich** the high-scoring subset with deeper data pulls.
3. **Score** each business by weak-presence signals × business-value signals.
4. **Build** a personalized static demo site for high-score candidates.
5. **Reach out** via a rule-engine-orchestrated, multi-channel sequence (email → SMS → postcard).
6. **Convert** via demo-link → Stripe Checkout → auto-publish to subdomain.
7. **Manage** site + presence via AI SMS assistant (Claude + Twilio), weekly LLM-generated reports.

## Product surfaces
- **Marketing landing page** (`yourbrand.com`) — inbound top of funnel. See "Landing page" section.
- **Lead-facing:** demo sites (S3/CloudFront), outreach messages, landing page on demo expiration.
- **Customer-facing:** live Next.js site (Vercel), Twilio SMS assistant, weekly email reports, magic-link email auth.
- **Operator-facing:** internal dashboard for human-in-loop review of outreach, directory submission tasks, billing escalations, service-module config.

## Landing page
The public marketing site at the apex domain. Also functions as a second top-of-funnel by generating inbound leads via a free SEO/quality analysis tool.

**Sections:**
- Hero — value prop, example demo site link, primary CTA ("Get a free analysis of your site").
- How it works — 3-step flow (we find your business, we build a demo, you pay to go live).
- Free Site Analysis — the lead magnet. User enters their existing site URL + email (both required). We run an automated audit and email the report within minutes. Email capture feeds the CRM as an inbound lead with source `landing_analysis` — outreach loop re-engages via the standard pipeline.
- Sample demo gallery — a few anonymized example demo sites we built.
- Pricing — single $50/mo plan, what's included.
- Contact us — simple form (name, email, message). Submissions create an `operator_task` and notify the operator inbox.
- Footer — legal (privacy, terms, CAN-SPAM address), unsubscribe link.

**Free Site Analysis details:**
- Inputs: site URL, email (required, validated), optional business name.
- Validation: MX check on the email domain; reject duplicate submissions within 24h per URL+email pair; hCaptcha on submit; per-IP throttling.
- Audit dimensions (automated, reuse the presence-scoring pipeline):
  - Lighthouse-style perf / accessibility / SEO / best-practices scores via a headless Chrome runner.
  - Mobile friendliness, SSL, page weight, load time.
  - Meta tags, title, description, canonical, robots.
  - Schema.org / local-business structured data presence.
  - NAP consistency vs Google Maps / Yelp records (if matched).
  - GBP completeness (photos, hours, categories, review count).
  - Directory presence (Yelp, BBB, Facebook, Apple Maps).
- Output: HTML email with a per-dimension score, top-3 called-out issues, and a CTA to "see what a new site would look like — we'll build a free demo." Clicking the CTA triggers a demo-build job against the submitted business.
- Every submission stored as an `analysis_request` row, linked to a `business` record (matched by domain or created fresh). The business is then an inbound lead in the same CRM as cold-discovery businesses — all downstream outreach, scoring, and assistant flows apply.

**Contact form:** same treatment — creates an `operator_task` + emails the operator inbox, no auto-reply beyond a confirmation page.

## Data sources (modular)
All data sources implement a shared interface so new sources are plug-in. Each source emits candidate business records tagged with source + confidence.
- Google Maps Places API
- Yelp Fusion
- Facebook Pages (scraped)
- BBB
- Yellow Pages
- State business registrations (Texas SOS for MVP)
- Future: Apple Maps, Nextdoor, Angi, industry-specific directories

Data source runs are either **continuous low-rate** (respect rate limits, stream records) or **on-demand enrichment** (triggered before outreach).

## Deduplication
All variants stored; dedup algorithm merges using name + address + phone + domain fuzzy match. Ambiguous merges flagged to human review queue. Each business record has a canonical ID with a history of source variants.

## Presence scoring
Weighted score from config (manual initially, tuned by conversion-data feedback loop over time):
- Missing website / parked domain / single-page site
- No / outdated Google Business Profile
- No social presence (FB, Yelp)
- Missing directory listings
- Incomplete NAP (name/address/phone inconsistency)
- Low review count

Second score: **business-value estimate** (niche multiplier, review volume as proxy for revenue, years in business). Outreach priority = presence-score × value-score.

## Service modules (extensible)
Each service module is code-defined with:
- Typed input (what data from the business record)
- Typed output (content/action produced)
- Eligibility rules (which business types)
- Cost envelope

Initial modules:
- Website build (demo + live)
- Google Business Profile audit + manager-access request
- Directory audit + submission (human-in-loop initially)
- Local-SEO basics: schema markup, NAP consistency, GBP optimization
- Weekly analytics report
- AI SMS assistant
- Review-request automation (Square / Toast / Clover integration)
- Niche-specific add-ons (e.g., restaurant → DoorDash setup; e-commerce → Etsy/Amazon storefront)

All $50/mo at MVP. Tier architecture ready but not exposed.

## Outreach
- **Rule engine** decides channel sequence per business (AI-drafted ruleset, operator-tunable).
- **Channels:** email (primary, Amazon SES + warmed subdomains), SMS, physical postcard.
- **Personalization:** LLM-authored using full business record. Human-in-loop review for first N/day until quality confidence.
- **Attribution:** multi-touch model, every send recorded against the business.
- **Unsubscribe:** required in every email; unsubscribe adds business to do-not-contact list.
- **Owner contact discovery:** data sources produce emails/phones; for contact-less businesses, fall back to Facebook/Instagram/Etsy DMs.

## Demo sites
- **Stack:** Next.js with `output: 'export'` for demos → static HTML deployed to S3 + CloudFront.
- **Same codebase redeploys to Vercel** on conversion, unlocking dynamic features.
- **AI-generated templates** per niche, versioned in the repo. Contractor template first.
- **AI code-gen pipeline:** reads business record, forks template, customizes TSX, builds, deploys. Every deploy logged.
- **Content:** AI-authored copy (hyper-personalized). Photos: Google Maps (where permissible), stock, or AI-generated, with AI augmentation.
- **Subdomain:** `{slug}.yourbrand.com` for both demo and live.
- **Domain research:** registrar API (Cloudflare/Namecheap); AI suggests 3-5 names. Domains ≤$100/yr bundled into $50/mo; pricier ones pitched as add-on.
- **Demo expiration:** 30 days. After expiry, subdomain serves a re-engagement landing page with contact-capture form that re-triggers outreach.

## Payment
- **Stripe** only. Cancel-anytime, site taken down immediately on cancel.
- **Involuntary churn** (failed payment): flag for human review, human makes final call to terminate.
- **$50/mo flat** MVP; tier infrastructure present but unused.

## Activation flow
1. Owner clicks demo link, sees site + "Claim this site — $50/mo" CTA.
2. Stripe Checkout (email captured there).
3. Webhook creates customer + business link.
4. Magic-link verification email sent.
5. On verify, site auto-publishes at subdomain within 60s.
6. Onboarding SMS introduces the assistant, asks for first change.
7. Background: AI-drafted GBP manager-access request queued for human review, sent within 24h.
8. Day-7 analytics check-in SMS.

No forced calls. Async onboarding.

## AI SMS assistant
- **Model:** Claude with tool use.
- **Transport:** Twilio SMS (text only MVP; voice deferred).
- **Scope:** "change anything" — site content, hours, photos, menu/services, announcements, GBP details, directory listings.
- **Flow:** owner texts → AI asks clarifying questions if ambiguous → generates a preview (demo link for site changes, textual confirmation for service changes) → owner confirms → change applied.
- **Identity:** signup phone-number match MVP; email auth added later.
- **Audit:** every change (AI or human) logged + reversible via "undo last change".
- **Escalation:** unhandleable requests emailed to an operator inbox.

## Weekly reports
LLM-generated per customer, using whatever data sources we have (GBP Insights, site analytics, review deltas, directory status). Anchors retention. Format evolves with available data.

## CRM / data store
- **Document store** (likely MongoDB or Postgres-JSONB; defer choice to architecture doc).
- **Business record** is the central aggregate: all source variants, all enrichment, all outreach, all interactions, all service-module state.
- **Stage** is computed, not stored — derived from signals (has-demo-url, last-outreach-at, stripe-customer-id, etc.).
- **Audit trail** on all field changes.

## Observability
Sentry for errors + metrics. Per-service health: discovery throughput, outreach send rate, demo build success rate, assistant response latency.

## Compliance (MVP scope)
- CAN-SPAM: unsubscribe link + physical address in every email.
- Do-not-contact list is honored across all channels and sources.
- PII deletion, CCPA, GDPR: deferred.

## Explicitly out of scope for MVP
- Multi-tenant / white-label
- Voice calls
- Free trials or tiered pricing
- Domain transfer / DNS automation for existing domains
- Non-US businesses
- Restaurant / e-commerce niches
