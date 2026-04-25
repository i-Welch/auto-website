# Architecture

## Repo layout (monorepo, pnpm workspaces + Turborepo)

```
auto-website/
  apps/
    landing/            # public marketing site at yourbrand.com (Next.js on Netlify)
    dashboard/          # operator UI (Next.js on Netlify, behind auth)
    api/                # Netlify Functions: webhooks, form posts, short APIs
    assistant/          # Twilio webhook (Netlify Function) + Claude tool-use loop
    live-sites/         # multi-tenant Next.js app serving customer sites (Netlify)
    worker-discovery/   # Fargate worker: data source crawlers
    worker-outreach/    # Fargate worker: outreach dispatcher (scheduled + event-driven)
    worker-sitegen/     # Fargate worker: demo/live site generation + deploy, warm sandboxes
    worker-analysis/    # Fargate worker: site-analysis audits from landing submissions
    demo-template-contractor/  # Next.js template, the "fork source" for site gen
  packages/
    db/                 # data access layer, schemas, migrations
    core/               # business logic: scoring, dedup, stage computation
    data-sources/       # modular source adapters (google-maps, yelp, fb, ...)
    service-modules/    # modular service definitions
    outreach/           # rule engine, channel adapters (email, sms, postcard)
    sitegen/            # template forking, AI customization, build + deploy
    assistant-tools/    # Claude tool definitions (update site, update GBP, etc.)
    llm/                # wrapped Claude client, prompt cache helpers
    shared/             # types, config schema, utilities
  infra/                # IaC (CDK or Terraform)
```

TypeScript end-to-end. Shared types via `packages/shared`.

## Deployment (Netlify-first hybrid)

Web surfaces, short-lived APIs, and the database run on Netlify. Long-running and stateful workers run on a small Fargate cluster (only place Netlify can't go: 15-min function cap and no warm pinned sandboxes). Demo static hosting stays on S3+CloudFront for wildcard-subdomain ergonomics and the versioned-path scheme used by the live-edit flow.

| Component | Service |
|---|---|
| Landing site (`apps/landing`) | Netlify (Next.js) |
| Operator dashboard (`apps/dashboard`) | Netlify (Next.js, behind auth) |
| Public API + webhooks (Stripe, Twilio, SES inbound, form posts) | Netlify Functions |
| Edge routing for demos / live sites | Netlify Edge Functions (where colocated) + CloudFront Functions for `*.yourbrand.com` lookups |
| Primary DB | **Netlify DB (Neon Postgres)** with JSONB columns |
| Long-running workers (`worker-discovery`, `worker-outreach`, `worker-sitegen`, `worker-analysis`) | ECS Fargate, queue-driven |
| Job queue | SQS (one queue per worker class) |
| Scheduled triggers | EventBridge cron → SQS |
| Object storage | S3 (demo static sites, site assets, outreach creative) |
| CDN for demo subdomains | CloudFront in front of S3, wildcard `*.yourbrand.com` |
| Live customer sites | Multi-tenant Next.js app on Netlify, slug-routed via DB lookup |
| Email sending | Amazon SES, 3-5 warmed subdomains rotated |
| SMS | Twilio |
| Payments | Stripe |
| Secrets | Netlify env vars (web), SSM Parameter Store (workers) |
| Observability | Sentry (errors, perf, tracing) |
| CI/CD | GitHub Actions → Netlify deploy (web) + ECR → ECS deploy (workers) |

**DB choice:** Netlify DB (Neon Postgres) with JSONB for the document-shaped business aggregate. Reverts the earlier Atlas pick — keeping the DB inside Netlify simplifies env wiring, branching, and credentials. Tradeoff acknowledged: nested-document ergonomics are worse than Mongo, so we pay it in a small data-access layer (`packages/db`) that hides JSONB path expressions behind typed helpers.

**Why not all-Netlify?** `worker-discovery` paginates data sources for hours; `worker-sitegen` pins warm sandboxes per chat session for fast AI rebuilds; both blow the 15-min Background Function cap. They stay on Fargate and talk to Netlify's API and DB over the public endpoints (Neon connection over TLS).

## Data model (high level)

```
business           (id, canonical name/address/phone, score, value_score, status flags, raw jsonb)
business_source    (business_id, source, external_id, raw jsonb, confidence, last_seen)
business_audit     (business_id, field, old_value, new_value, actor, at)
contact            (business_id, kind[email|phone|facebook|...], value, verified, do_not_contact)

outreach_send      (id, business_id, channel, service_module, template_id, content, sent_at, status)
outreach_event     (send_id, kind[opened|clicked|replied|bounced|unsubscribed], at, payload)
conversion         (business_id, stripe_customer_id, converted_at, touch_sends jsonb)

demo_site          (business_id, slug, s3_key, built_at, expires_at, status)
live_site          (business_id, vercel_project_id, domain, deployed_at)

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

1. Trigger: business passes score threshold + has sufficient data.
2. `sitegen` worker pulls business record.
3. Forks `demo-template-contractor` into a temp workspace.
4. Claude (with code-editing tool use) customizes: hero copy, services section, photos, NAP block, CTA.
5. Run `next build && next export`.
6. Upload `out/` to S3 under `demos/{slug}/`.
7. Wildcard CloudFront + Lambda@Edge maps `{slug}.yourbrand.com` → S3 prefix.
8. Record `demo_site` row with expiry.

On conversion:
1. Same codebase checked out, configured as a live Vercel project (or a slug routed through one multi-tenant Next.js app pulling config from DB — MVP chooses the latter for simplicity).
2. Subdomain routed to Vercel deployment.
3. Demo S3 entry flagged `converted`, 301 from CloudFront → live site.

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

Public marketing site, deployed to Vercel at the apex domain (`yourbrand.com`). The apex sits on Vercel; `*.yourbrand.com` wildcard still points at CloudFront for demos + live customer sites, routed via DNS / edge rules.

**Stack:**
- Next.js (App Router), server components, Tailwind. Same component library as the demo template so visual brand is consistent.
- Hosted on Vercel (separate project from customer sites).
- Uses Vercel Analytics for marketing funnel metrics.

**Routes / surfaces:**
- `/` — hero, how-it-works, sample gallery, pricing, analysis CTA.
- `/analyze` — form page (URL + email). POSTs to `/api/analyze` (Next.js route handler).
- `/analyze/submitted` — confirmation page ("check your inbox in a few minutes").
- `/contact` — contact form. POSTs to `/api/contact`.
- `/privacy`, `/terms`, `/unsubscribe` — legal + unsubscribe handler (writes to `contact` do-not-contact list).

**Analysis submission flow:**
1. Landing form → `POST /api/analyze` (rate-limited, hCaptcha verified, MX-checked).
2. Handler creates `analysis_request` row, matches/creates a `business` by domain lookup, enqueues SQS job for `worker-analysis`.
3. `worker-analysis` runs the audit: headless Chrome / Lighthouse run + reuse of scoring pipeline for NAP/directory/GBP checks. Writes `report` JSON onto the row.
4. Worker sends the report email via SES (using the same infra as cold outreach) with a CTA to the generated demo.
5. Business now enters the CRM as an inbound lead (`source: landing_analysis`) and is eligible for the standard outreach pipeline, with priority boost since they opted in.

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
- Magic-link tokens single-use, 15-min TTL.
- Operator dashboard behind SSO (Cognito or simple email-link auth for MVP).
- S3 demo bucket: CloudFront-only via OAC.
- No customer logins in MVP — everything happens via SMS.

## Key cost levers
- Data source tiering (don't burn Google Maps $ on low-score leads).
- Demo-on-S3 until conversion (Netlify hosts the live multi-tenant app, demos stay static).
- Prompt caching on Claude calls (templates + business record).
- LLM usage metered per-business to catch runaway costs.
- Fargate worker count kept minimal (3-4 services, scale-to-zero where possible).
