# Architecture

## Repo layout (monorepo, pnpm workspaces + Turborepo)

```
growonline/   # repo dir on disk is `auto-website` for historical reasons
  apps/
    landing/                  # Next.js on Netlify — public marketing site + public API routes
    dashboard/                # Next.js on Netlify — operator UI + protected API routes
    live-sites/               # Next.js on Netlify — multi-tenant, serves all demo + live customer sites by subdomain
    assistant/                # Netlify Functions site — Twilio webhook + Claude tool-use loop
    workers/                  # Netlify Functions site — Inngest functions for discovery, outreach, sitegen, analysis
    demo-template-contractor/ # Next.js template (built and copied/cloned by sitegen)
  packages/
    db/                       # Drizzle schema, migrations, typed query helpers
    core/                     # business logic: scoring, dedup, stage computation
    data-sources/             # modular source adapters (google-maps, yelp, fb, ...)
    service-modules/          # modular service definitions (also expose AssistantTools)
    outreach/                 # rule engine, channel adapters (email, sms, postcard)
    sitegen/                  # template forking, AI customization, build, deploy
    llm/                      # wrapped Claude client, prompt cache helpers
    shared/                   # types, env schema (Zod), utilities
```

TypeScript end-to-end. Shared types via `packages/shared`. Five Netlify sites total, all in one repo (per-site `netlify.toml` declares base directory).

## Deployment (all-Netlify)

Everything ships on Netlify primitives. No AWS account required for MVP. Long-running work is reshaped into cursor-resumable chunks orchestrated by **Inngest** (durable workflow engine, runs on top of Netlify Functions).

| Component | Service |
|---|---|
| Landing site (`apps/landing`) | Netlify site (Next.js) |
| Operator dashboard (`apps/dashboard`) | Netlify site (Next.js, behind auth) |
| Multi-tenant customer sites (demo + live) (`apps/live-sites`) | Netlify site (Next.js), wildcard custom domain `*.growonline.app` |
| Assistant (Twilio webhook) (`apps/assistant`) | Netlify site (Functions only) |
| Workers (`apps/workers`) | Netlify site (Inngest functions running on Netlify Functions) |
| Public API + webhooks (Stripe, Twilio, form posts) | Colocated as Next.js route handlers in `landing` and `dashboard`, or Netlify Functions in dedicated sites |
| Workflow / queue / cron / retries | **Inngest** (third-party, free tier ample for MVP) |
| Primary DB | **Netlify DB (Neon Postgres)** with JSONB columns |
| Object storage | **Netlify Blobs** (built static demo artifacts, image originals) |
| Image transforms | **Netlify Image CDN** |
| Email sending | **Resend** (replaces SES — better DX from serverless, similar deliverability with proper warmup) |
| SMS | Twilio |
| Payments | Stripe |
| LLM | Anthropic Claude API |
| Secrets | Netlify env vars + Netlify Secrets Controller for sensitive values |
| Observability | Sentry (errors, perf), Netlify Analytics for traffic, Inngest dashboard for job runs |
| CI/CD | GitHub → Netlify Git integration (per-site builds on push) |

**DB:** Netlify DB (Neon Postgres) with JSONB columns for the document-shaped business aggregate. The data-access layer (`packages/db`, Drizzle) hides JSONB path expressions behind typed helpers.

**Why Inngest:** Netlify has no native queue / fan-out / retry primitives — only cron + background-fire-and-forget. Inngest gives us durable steps, retries, scheduled events, fan-out, sleep, and a dashboard, while still running the actual function code on Netlify Functions. Without it we'd reinvent state machines on top of cron + DB rows.

**What does not fit serverless and how we cope:**
- *Long crawls* (data source pagination, hours of work) — chunked into 15-min Inngest steps with a cursor in DB. Each step picks up where the last left off.
- *Demo builds* (`next build`) — fit comfortably in a single Background Function (~30-90s for a small site).
- *Warm sandboxes for live AI rebuilds during a demo chat* — would need persistent compute. Deferred from MVP. When added post-MVP, options: (a) accept ~30-60s cold rebuilds with status streaming, (b) add one Fly Machine specifically for sitegen.

**Subdomain routing:** `apps/live-sites` owns the wildcard custom domain (`*.growonline.app`). Next.js middleware reads the `host` header, looks up the slug in DB, and renders the right tenant — same code path serves demo and live sites, distinguished by `status` on the row.

## Data model (high level)

```
business           (id, canonical name/address/phone, score, value_score, status flags, raw jsonb)
business_source    (business_id, source, external_id, raw jsonb, confidence, last_seen)
business_audit     (business_id, field, old_value, new_value, actor, at)
contact            (business_id, kind[email|phone|facebook|...], value, verified, do_not_contact)

outreach_send      (id, business_id, channel, service_module, template_id, content, sent_at, status)
outreach_event     (send_id, kind[opened|clicked|replied|bounced|unsubscribed], at, payload)
conversion         (business_id, stripe_customer_id, converted_at, touch_sends jsonb)

demo_site          (business_id, slug, blob_prefix, current_version, built_at, expires_at, status)
demo_version       (id, demo_site_id, version, blob_prefix, built_at, build_log_ref, status)
live_site          (business_id, slug, custom_domain?, current_version, deployed_at)

customer           (id, business_id, stripe_customer_id, stripe_subscription_id, status)
change_log         (id, business_id, surface[site|gbp|directory|...], actor[ai|human|owner], diff, reversible_ref, applied_at)

assistant_thread   (customer_id, twilio_phone, messages jsonb)
service_instance   (customer_id, service_module_id, config jsonb, state jsonb)
operator_task      (kind, business_id?, customer_id?, payload, status, assignee, created_at)

analysis_request   (id, business_id?, submitted_url, submitted_email, business_name?, status, report jsonb, created_at, emailed_at)
contact_submission (id, name, email, message, source_page, created_at, operator_task_id)
```

Stage is a view/computed field off `business` + related rows, not a stored column.

## Modular interfaces

### Data source
```ts
interface DataSource {
  id: string;
  mode: 'continuous' | 'on_demand';
  discover(input: DiscoveryQuery): AsyncIterable<RawBusinessRecord>;
  enrich?(business: Business): Promise<EnrichmentPatch>;
}
```
Runner invokes `discover` on a schedule, pushes records into a normalization + dedup pipeline.

### Service module
Service modules are the single source of truth for *any* action taken on a business — initial onboarding runs, background jobs, operator-triggered changes, and **the AI assistant**. The assistant does not have its own parallel set of "update X" implementations; it calls the same service-module tools that everything else calls.

```ts
interface ServiceModule<TIn, TOut> {
  id: string;
  appliesTo(business: Business): boolean;
  inputSchema: ZodSchema<TIn>;     // strict, validated
  outputSchema: ZodSchema<TOut>;
  run(input: TIn, ctx: Ctx): Promise<TOut>;

  // LLM-facing surface — every module exposes one or more tools the assistant can call
  tools: AssistantTool[];
}

interface AssistantTool {
  name: string;                    // unique, stable, snake_case
  description: string;             // what it does, when to use it, when NOT to use it
  inputSchema: ZodSchema;          // converted to JSONSchema for Claude tool use
  examples: Array<{                // few-shot examples embedded in the tool prompt
    situation: string;
    input: unknown;
    outcome: string;
  }>;
  requiresConfirmation: boolean;   // if true, assistant must show preview + get "yes" before calling
  run(input: unknown, ctx: AssistantCtx): Promise<ToolResult>;
}
```

**Registry** in `packages/service-modules/index.ts` enumerates all modules. A single helper (`buildAssistantToolset(customer)`) walks the registry, filters to modules whose `appliesTo` matches the customer's business, and returns the flat list of `AssistantTool`s to hand to Claude at conversation start. Adding a new service module automatically extends the assistant's capabilities — no separate assistant-side wiring.

**Contract every module must satisfy:**
- Strict, Zod-validated inputs and outputs — the LLM cannot pass arbitrary shapes.
- Natural-language `description` and `examples` written for an LLM reader: what the tool does, the fields it needs, and which adjacent tools it shouldn't be confused with.
- `requiresConfirmation: true` for any tool that mutates customer-visible state (site copy, GBP, directory listings). The assistant loop enforces a preview-then-confirm cycle before invoking these.
- Every successful `run` writes a `change_log` entry with enough info to reverse.
- Errors return structured failure results the LLM can reason about (never raw exceptions to the model).

### Outreach channel
```ts
interface OutreachChannel {
  id: 'email' | 'sms' | 'postcard';
  send(business: Business, content: RenderedContent): Promise<SendResult>;
  trackInbound?(payload): Promise<InboundEvent>;
}
```

### Rule engine (outreach)
Declarative per-niche playbook: ordered steps with wait/skip conditions. AI drafts playbooks; operator edits as YAML/TS config.

## Site generation pipeline

Implemented as an Inngest function in `apps/workers`. Single Background Function invocation handles the full build for a small site (well under the 15-min cap).

1. Trigger: business passes score threshold + has sufficient data, or analysis-request CTA fires, or operator forces a rebuild.
2. Inngest step `prepare-workspace`: pull business record, clone `demo-template-contractor` into a tmp directory.
3. Inngest step `customize`: Claude tool-use loop edits TSX (hero copy, services, photos, NAP, CTA). Edits constrained to a file allowlist.
4. Inngest step `build`: `pnpm next build` → static export to `out/`. Failure here aborts the version flip; current live version remains.
5. Inngest step `upload`: write `out/` to **Netlify Blobs** under `demos/{slug}/v{N}/`.
6. Inngest step `flip-pointer`: update `demo_site.current_version = N`.
7. `apps/live-sites` middleware reads the slug from the host, looks up `current_version`, and serves the matching blob prefix. No CDN invalidation needed — the pointer is the source of truth.

On conversion:
1. `customer` row links to `business`. `demo_site.status = 'converted'`.
2. The same `apps/live-sites` app continues to serve the same slug — only the `status` flag changes. No redeploy, no migration.
3. Future edits via the assistant go through the same sitegen pipeline, producing new `demo_version` rows. Undo = flip the pointer back.

## Assistant loop

1. Twilio webhook → `assistant` service.
2. Identify customer by `From` phone.
3. Load `assistant_thread` (last N turns).
4. Build the toolset by calling `buildAssistantToolset(customer)` — this gathers tools from every service module that `appliesTo` the customer. Plus a small set of always-on tools (`get_business_data`, `create_operator_task`, `undo_last_change`).
5. Claude invocation with that toolset.
6. For any tool where `requiresConfirmation` is true, the assistant loop intercepts the call, generates a preview (demo URL for site edits; text diff for other services), sends it to the owner, and only invokes the underlying `run` after an explicit "yes".
7. On confirm, tool runs + writes `change_log` row.
8. Unhandleable → `create_operator_task` + email to operator inbox.

Because the assistant's capabilities come entirely from the service-module registry, shipping a new module (e.g., `square-reviews-integration`) immediately gives the assistant the ability to manage that surface for eligible customers — no changes to the assistant service itself.

## Landing page (`apps/landing`)

Public marketing site, deployed to Netlify at the apex domain. Apex (`growonline.app`) → landing site. Wildcard `*.growonline.app` → `apps/live-sites`. Both are Netlify sites with their own custom-domain config.

**Stack:**
- Next.js (App Router), server components, Tailwind. Same component library as the demo template so visual brand is consistent.
- Netlify-hosted (separate site from customer sites).
- Netlify Analytics for marketing funnel metrics.

**Routes / surfaces:**
- `/` — hero, how-it-works, sample gallery, pricing, analysis CTA.
- `/analyze` — form page (URL + email). POSTs to `/api/analyze` (Next.js route handler).
- `/analyze/submitted` — confirmation page ("check your inbox in a few minutes").
- `/contact` — contact form. POSTs to `/api/contact`.
- `/privacy`, `/terms`, `/unsubscribe` — legal + unsubscribe handler (writes to `contact` do-not-contact list).

**Analysis submission flow:**
1. Landing form → `POST /api/analyze` (rate-limited, hCaptcha verified, MX-checked).
2. Handler creates `analysis_request` row, matches/creates a `business` by domain lookup, sends an Inngest event `analysis.requested`.
3. Inngest function (in `apps/workers`) runs the audit: Lighthouse via `@netlify/lighthouse-plugin` or a hosted Lighthouse runner + reuse of scoring pipeline for NAP/directory/GBP checks. Writes `report` JSON onto the row. Same function fans out to `sitegen.requested` to build a demo for the submitted business.
4. Function sends the report email via Resend with a CTA to the generated demo URL.
5. Business now enters the CRM as an inbound lead (`source: landing_analysis`) and is eligible for the standard outreach pipeline, with a priority boost since they opted in.

**Contact submission flow:**
1. `POST /api/contact` validates + rate-limits.
2. Creates `contact_submission` + linked `operator_task`, emails operator inbox.
3. Response page confirms receipt.

**Bot / abuse protection:**
- hCaptcha on all forms.
- Per-IP + per-email throttling in the API route.
- Disposable-email-domain blocklist.

## Security / access
- Stripe webhook signature verified.
- Twilio webhook signature verified.
- Inngest webhooks verified via signing key.
- Magic-link tokens single-use, 15-min TTL.
- Operator dashboard behind email magic-link auth (no separate SSO for MVP).
- Netlify Blobs accessed only via server-side functions with the site's Blobs scope; no public read URLs.
- No customer logins in MVP — everything happens via SMS.

## Key cost levers
- Data source tiering (don't burn Google Maps $ on low-score leads).
- Single multi-tenant Next.js app for all customer sites — one Netlify site, not one per customer.
- Prompt caching on Claude calls (templates + business record).
- LLM usage metered per-business to catch runaway costs.
- Inngest free tier covers MVP volume; upgrade only when invocations cross threshold.
- Netlify Functions invocation count tracked; consolidate paths if approaching plan limits.
