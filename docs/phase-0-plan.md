# Phase 0 — Step-by-Step Execution Plan (all-Netlify)

We walk this top to bottom. Each step has: who does it, what it does, the commands, and how we verify.

Legend:
- 👤 **You** do it (account creation, paste a value, click a button).
- 🤖 **I** do it (run commands, write files).
- ✅ Verification before moving on.

No AWS. No Fargate. No SQS. No CloudFront. Everything is Netlify + a small set of SaaS partners (Inngest, Resend, Sentry, Anthropic, Stripe, Twilio).

---

## Step 1 — Decisions to lock in 👤

Locked in:

| Decision | Value |
|---|---|
| Brand name (display) | **GrowOnline** |
| Brand slug | **growonline** |
| npm scope | **@growonline** |
| Apex domain | **growonline.app** |
| Subdomain layout | apex → landing, `api.growonline.app` → operator API, `*.growonline.app` → customer demo + live sites. `dash.growonline.app` reserved (no UI for MVP). |
| Operator email | `isaac.welch@upstart.com` (change if you want a separate ops address) |

Note: `.app` is HSTS-preloaded, so HTTPS is mandatory. Netlify's auto-provisioned Let's Encrypt certs handle this; just don't expect plain-HTTP fallback to work anywhere.

---

## Step 2 — Local toolchain 👤

Your machine has asdf with node 22.0.0 available but not selected. Run:

```bash
cd /Users/isaac.welch/personal/auto-website
asdf set nodejs 22.0.0
node --version           # v22.x
corepack enable
corepack prepare pnpm@9 --activate
pnpm --version           # 9.x
```

CLIs we'll use:

```bash
brew install netlify-cli gh jq
netlify --version
gh --version
```

✅ All tools return versions.

---

## Step 3 — SaaS accounts 👤

Create the ones you don't already have. Don't paste keys yet — Step 4 lists what to copy.

| Service | URL | Notes |
|---|---|---|
| **Netlify** | https://app.netlify.com | Free tier OK for MVP. Connect GitHub. |
| ~~Inngest~~ | — | **Deferred**. Starting with raw Netlify Scheduled + Background Functions. Add Inngest if/when we need durable retries or fan-out. |
| **Resend** | https://resend.com | Free tier 3k emails/month. Add a domain later for production sending. |
| **Sentry** | https://sentry.io | Free dev tier. Create project `growonline` (Next.js platform). |
| **Anthropic** | https://console.anthropic.com | Create API key. |
| **Stripe** | https://dashboard.stripe.com | Test mode. |
| **Twilio** | https://www.twilio.com/console | Don't buy a number yet (Phase 5). |
| **Google Cloud** | https://console.cloud.google.com | Enable Places API (New). Defer to Phase 1 if you want. |
| **Yelp Fusion** | https://docs.developer.yelp.com | Defer to Phase 1. |
| **hCaptcha** | https://dashboard.hcaptcha.com | Defer to Phase 5.5. |

✅ Accounts exist; tabs open.

---

## Step 4 — Secrets to collect 👤

Paste these in a single chat message when ready. Mark anything deferred with `LATER`.

```
ANTHROPIC_API_KEY=
SENTRY_DSN_WEB=
SENTRY_DSN_WORKERS=
STRIPE_SECRET_KEY=          (sk_test_...)
STRIPE_PUBLISHABLE_KEY=     (pk_test_...)
STRIPE_WEBHOOK_SECRET=      (LATER — generated in Phase 4)
TWILIO_ACCOUNT_SID=         LATER
TWILIO_AUTH_TOKEN=          LATER
RESEND_API_KEY=
OPERATOR_API_KEY=           (we generate this in Step 9 — `openssl rand -hex 32`)
GOOGLE_PLACES_API_KEY=      LATER
YELP_API_KEY=               LATER
HCAPTCHA_SITE_KEY=          LATER
HCAPTCHA_SECRET_KEY=        LATER
```

Database URL comes from Netlify DB in Step 7 — not from you.

---

## Step 5 — Monorepo scaffold 🤖

I create at the repo root:
- `package.json` (root, private, workspaces)
- `pnpm-workspace.yaml`
- `turbo.json`
- `tsconfig.base.json`
- `.nvmrc` (`22`)
- `.npmrc`, `.editorconfig`
- `.prettierrc.json`, `.prettierignore`
- `eslint.config.mjs` (flat config, TS + Next presets)
- `.gitignore` (additions: `.netlify/`, `.turbo/`, `node_modules/`, `dist/`, `.next/`, `.env*`)
- `.github/workflows/ci.yml` (lint + typecheck on PR)

Then you:

```bash
pnpm install
pnpm lint
pnpm typecheck
git add -A && git commit -m "chore: monorepo scaffold"
git push
```

✅ CI green on the push.

---

## Step 6 — Phase-0 packages 🤖

Only what's needed to verify end-to-end. Other packages get scaffolded in their phase.

- `packages/shared` — env schema (Zod), shared types, brand constants.
- `packages/db` — Drizzle ORM, Postgres driver, migrations folder, initial schema:
  - `business` (id, slug, canonical name/address/phone, score, value_score, status, raw jsonb)
  - `business_source` (business_id, source, external_id, raw jsonb, confidence, last_seen)
  - `contact` (business_id, kind, value, verified, do_not_contact)
  - `business_audit` (business_id, field, old_value, new_value, actor, at)
- Drizzle Kit config + scripts: `db:generate`, `db:migrate`, `db:studio`.

You then:

```bash
pnpm install
pnpm -F @growonline/db build
```

✅ DB package compiles. (We run migrations against Neon in Step 8.)

---

## Step 7 — Provision Netlify DB (Neon Postgres) 👤

1. In Netlify dashboard → **Add new site → Import an existing project** → pick `i-Welch/auto-website`. Skip build settings for now (per-site `netlify.toml` files arrive in Step 9).
2. Open the new site → **Extensions** → search **Netlify DB** → **Install**. This provisions a Neon Postgres database for this site and exposes `NETLIFY_DATABASE_URL` as a build/runtime env var.
3. Copy the value of `NETLIFY_DATABASE_URL` (Site settings → Environment variables) and paste it back to me in chat — I need it once locally to run migrations from your laptop.

✅ DB provisioned. Connection string in hand.

---

## Step 8 — Run initial migrations 🤖

Local migration run against the freshly provisioned Neon DB:

```bash
export DATABASE_URL='<paste from Step 7>'
pnpm -F @growonline/db db:migrate
pnpm -F @growonline/db db:studio   # optional, opens Drizzle Studio
```

✅ Tables `business`, `business_source`, `contact`, `business_audit` exist.

---

## Step 9 — Scaffold the five Netlify sites 🤖

I create:

```
apps/landing/        — Next.js 15 + Tailwind. /, /api/health, Sentry wired.
apps/api/            — Netlify Functions site. Bearer-auth middleware. /healthz (anon), /me (auth) returns the calling token's role.
apps/live-sites/     — Next.js 15. middleware reads host → DB → renders placeholder. No-op for unknown subdomains.
apps/assistant/      — Netlify Functions site. /twilio (signature-verified placeholder).
apps/workers/        — Netlify Functions site. One Scheduled Function `cron-healthcheck` (every 5 min) and one Background Function `db-healthcheck-background` that both run a DB query and write to `_healthcheck`.
```

Plus `scripts/` at repo root with two starter scripts:
- `scripts/operator-ping.ts` — calls `GET https://<api-site>.netlify.app/me` with `OPERATOR_API_KEY` and prints the response.
- `scripts/db-stats.ts` — connects to Neon directly and prints row counts per table.

Plus per-app `netlify.toml` declaring the base directory and build command. Plus a `packages/shared` `loadEnv()` helper that reads + validates env vars per app.

You then locally:

```bash
pnpm install
pnpm -F @growonline/landing dev   # http://localhost:3000
```

✅ Each app boots locally without errors.

---

## Step 10 — Five Netlify sites, one repo 👤

We create one Netlify site per app — keeps deploys, env vars, and domains scoped cleanly.

For each of the 5 apps below, in Netlify dashboard:
1. **Add new site → Import an existing project → GitHub → `i-Welch/auto-website`**.
2. Set **Base directory** to `apps/<name>`.
3. Set the **Build command** and **Publish directory** as the per-site `netlify.toml` already specifies (Netlify auto-detects, so usually just confirm).
4. Add env vars from Step 4. The DB extension only needs to be installed once — re-use `NETLIFY_DATABASE_URL` across sites by either re-installing the extension on each or pasting the value as a manual env var.
5. Trigger initial deploy.

| Site name | Base dir | What it serves |
|---|---|---|
| `growonline-landing` | `apps/landing` | apex `growonline.app` |
| `growonline-api` | `apps/api` | `api.growonline.app` (operator API) |
| `growonline-live-sites` | `apps/live-sites` | wildcard `*.growonline.app` |
| `growonline-assistant` | `apps/assistant` | called by Twilio webhook |
| `growonline-workers` | `apps/workers` | called by Inngest |

✅ All five sites build green and serve their `*.netlify.app` URLs.

---

## Step 11 — Verify workers + scheduled functions 👤 + 🤖

1. 🤖 The `growonline-workers` site has:
   - `cron-healthcheck.ts` — a **Netlify Scheduled Function** declared in `netlify.toml` to run every 5 minutes. Inserts a row into `_healthcheck` with `source='scheduled'`.
   - `db-healthcheck-background.ts` — a **Netlify Background Function** (`*-background.ts` naming convention) that does the same insert with `source='background'`. Triggered manually for verification.
2. 👤 Trigger the background function once: `curl -X POST https://growonline-workers.netlify.app/.netlify/functions/db-healthcheck-background`.
3. 👤 Wait up to 5 minutes for the scheduled function to fire on its own.
4. 👤 Confirm both rows exist:
   ```bash
   psql "$DATABASE_URL" -c "select source, count(*) from _healthcheck group by source;"
   ```

✅ `_healthcheck` has rows from both `scheduled` and `background`. Function logs in the Netlify dashboard show successful executions.

---

## Step 12 — Sentry verification 👤

I added a `/api/boom` route to `landing` and a `/api/boom` function to `workers` that throws once. Hit each:

```bash
curl -i https://<landing>.netlify.app/api/boom
curl -i https://<workers>.netlify.app/api/boom
```

✅ Both errors show up in Sentry, tagged with `service: landing` and `service: workers` respectively. (We then remove the boom routes.)

---

## Step 13 — Domain + DNS 👤 + 🤖

Skip if deferring the domain.

1. 👤 Buy domain (Cloudflare Registrar at-cost) or move it onto Cloudflare DNS.
2. 👤 In Netlify, on each site, add the appropriate custom domain:
   - `growonline-landing` → apex `growonline.app`
   - `growonline-api` → `api.growonline.app`
   - `growonline-live-sites` → wildcard `*.growonline.app` (Pro tier or higher required for wildcard custom domains; verify your plan)
   - `growonline-assistant` and `growonline-workers` → no public custom domains needed; keep `.netlify.app`
3. 👤 Follow Netlify's DNS instructions (records depend on whether you use Netlify DNS or external).
4. 🤖 I'll ship a small script `scripts/dns-check.ts` that polls until cert + DNS are healthy.

✅ Visiting `https://growonline.app` returns the landing site over HTTPS. `https://api.growonline.app/healthz` returns `{ ok: true }`. `https://api.growonline.app/me` returns 401 without a bearer, 200 with the right token.

---

## Step 14 — Phase 0 done-criteria check 🤖

Final checklist:
- [ ] All 5 Netlify sites green and reachable.
- [ ] `apps/landing/api/health` returns 200.
- [ ] `apps/api/healthz` returns 200; `/me` requires bearer token.
- [ ] `scripts/operator-ping.ts` succeeds with the issued `OPERATOR_API_KEY`.
- [ ] Workers site's scheduled function fires at least once on its own; background function fires on POST.
- [ ] `_healthcheck` table has both `scheduled` and `background` rows.
- [ ] Sentry has events from landing, api, and workers, separable by service tag.
- [ ] CI green on `master`.
- [ ] `pnpm db:migrate` is reproducible (drop DB → re-migrate → schema rebuilt cleanly).
- [ ] Phase-0 docs reflect the all-Netlify reality (this file + `architecture.md` + `mvp-plan.md`).

✅ Phase 0 done. Ready for Phase 1 (Discovery).

---

## Things explicitly deferred from Phase 0

Originally listed in `mvp-plan.md` Phase 0; cheaper to add when their phase needs them:
- Resend domain verification + warmup → Phase 3 (Outreach).
- Wildcard `*.growonline.app` cert if your Netlify plan doesn't include it yet → Phase 2 (Demo builder) — that's when the wildcard is actually used.
- hCaptcha site/secret keys → Phase 5.5 (Landing analysis).
- Twilio number → Phase 5 (Assistant).
- Google Maps + Yelp keys → Phase 1 (Discovery).

---

## Decisions locked in

- **Brand:** GrowOnline / `growonline` / `@growonline` / `growonline.app`.
- **ORM:** Drizzle.
- **Workflow layer:** start with raw Netlify Scheduled + Background Functions. Inngest deferred — revisit when we need durable retries / fan-out / step orchestration (likely Phase 1 or 3).
- **Operator interface:** no GUI. Bearer-auth'd operator API + scripts + direct DB. `dash.growonline.app` reserved if a UI ever happens.
- **Netlify team:** one team for all five sites.

Ready to run Step 2.
