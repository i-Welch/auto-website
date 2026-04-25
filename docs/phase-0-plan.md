# Phase 0 — Step-by-Step Execution Plan (all-Netlify)

We walk this top to bottom. Each step has: who does it, what it does, the commands, and how we verify.

Legend:
- 👤 **You** do it (account creation, paste a value, click a button).
- 🤖 **I** do it (run commands, write files).
- ✅ Verification before moving on.

No AWS. No Fargate. No SQS. No CloudFront. Everything is Netlify + a small set of SaaS partners (Inngest, Resend, Sentry, Anthropic, Stripe, Twilio).

---

## Step 1 — Decisions to lock in 👤

Paste these in chat:

| Need | Why | Example |
|---|---|---|
| **Brand name (display)** | Hero copy, email from-name | `LocalPulse` |
| **Brand slug (lowercase, no spaces)** | npm scope, env prefixes | `localpulse` |
| **Apex domain** (or "later") | Netlify custom domain | `localpulse.com` |
| **Operator email** | Where ops alerts go | `you@example.com` |

Defaults if you say "use whatever":
- Brand: `auto-website` / `@auto-website`
- Domain: defer (we use Netlify-issued URLs)
- Operator email: your `isaac.welch@upstart.com`

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
| **Inngest** | https://app.inngest.com | Free tier covers ~50k function runs/month. Sign in with GitHub. |
| **Resend** | https://resend.com | Free tier 3k emails/month. Add a domain later for production sending. |
| **Sentry** | https://sentry.io | Free dev tier. Create project `auto-website` (Next.js platform). |
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
INNGEST_EVENT_KEY=          (Inngest dashboard → Events → create key)
INNGEST_SIGNING_KEY=        (Inngest dashboard → Apps → reveal signing key)
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
pnpm -F @auto-website/db build
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
pnpm -F @auto-website/db db:migrate
pnpm -F @auto-website/db db:studio   # optional, opens Drizzle Studio
```

✅ Tables `business`, `business_source`, `contact`, `business_audit` exist.

---

## Step 9 — Scaffold the five Netlify sites 🤖

I create:

```
apps/landing/        — Next.js 15 + Tailwind. /, /api/health, Sentry wired.
apps/dashboard/      — Next.js 15 + Tailwind. /, /api/me (placeholder).
apps/live-sites/     — Next.js 15. middleware reads host → DB → renders placeholder. No-op for unknown subdomains.
apps/assistant/      — Netlify Functions site. /twilio (signature-verified placeholder).
apps/workers/        — Netlify Functions site + Inngest. /api/inngest serves the Inngest handler with one demo function.
```

Plus per-app `netlify.toml` declaring the base directory and build command. Plus a `packages/shared` `loadEnv()` helper that reads + validates env vars per app.

You then locally:

```bash
pnpm install
pnpm -F @auto-website/landing dev   # http://localhost:3000
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
| `<brand>-landing` | `apps/landing` | apex domain in Step 13 |
| `<brand>-dashboard` | `apps/dashboard` | `app.<domain>` |
| `<brand>-live-sites` | `apps/live-sites` | wildcard `*.<domain>` |
| `<brand>-assistant` | `apps/assistant` | called by Twilio webhook |
| `<brand>-workers` | `apps/workers` | called by Inngest |

✅ All five sites build green and serve their `*.netlify.app` URLs.

---

## Step 11 — Wire Inngest to the workers site 👤 + 🤖

1. 👤 In Inngest dashboard → **Apps → New App** → name `auto-website`. Copy the `INNGEST_EVENT_KEY` and `INNGEST_SIGNING_KEY` (you put these in Step 4's list).
2. 👤 Add both to the `<brand>-workers` site's env vars in Netlify.
3. 👤 Register the workers app's Inngest URL: `https://<workers-site>.netlify.app/api/inngest` in the Inngest dashboard.
4. 🤖 The workers site already has `/api/inngest` serving an Inngest handler with one demo function `db.healthcheck` that runs `SELECT NOW()` against `DATABASE_URL` and writes a row to a `_healthcheck` table.
5. 👤 In the Inngest dashboard → **Functions** → trigger `db.healthcheck` manually.

✅ Inngest run shows `success`, the workers site logs the timestamp, the `_healthcheck` row exists in Neon.

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
   - `<brand>-landing` → apex `<domain>`
   - `<brand>-dashboard` → `app.<domain>`
   - `<brand>-live-sites` → wildcard `*.<domain>` (Pro tier or higher required for wildcard custom domains; verify your plan)
   - `<brand>-assistant` and `<brand>-workers` → no public custom domains needed; keep `.netlify.app`
3. 👤 Follow Netlify's DNS instructions (records depend on whether you use Netlify DNS or external).
4. 🤖 I'll ship a small script `scripts/dns-check.ts` that polls until cert + DNS are healthy.

✅ Visiting `https://<domain>` returns the landing site over HTTPS. `https://app.<domain>` returns the dashboard.

---

## Step 14 — Phase 0 done-criteria check 🤖

Final checklist:
- [ ] All 5 Netlify sites green and reachable.
- [ ] `apps/landing/api/health` returns 200.
- [ ] Workers site's `/api/inngest` endpoint registered with Inngest.
- [ ] `db.healthcheck` Inngest function ran successfully end-to-end.
- [ ] `_healthcheck` row exists in Neon.
- [ ] Sentry has events from both web and workers, separable by tag.
- [ ] CI green on `master`.
- [ ] `pnpm db:migrate` is reproducible (drop DB → re-migrate → schema rebuilt cleanly).
- [ ] Phase-0 docs reflect the all-Netlify reality (this file + `architecture.md` + `mvp-plan.md`).

✅ Phase 0 done. Ready for Phase 1 (Discovery).

---

## Things explicitly deferred from Phase 0

Originally listed in `mvp-plan.md` Phase 0; cheaper to add when their phase needs them:
- Resend domain verification + warmup → Phase 3 (Outreach).
- Wildcard `*.<domain>` cert if your Netlify plan doesn't include it yet → Phase 2 (Demo builder) — that's when the wildcard is actually used.
- hCaptcha site/secret keys → Phase 5.5 (Landing analysis).
- Twilio number → Phase 5 (Assistant).
- Google Maps + Yelp keys → Phase 1 (Discovery).

---

## Open questions before we start at Step 2

1. Brand name + slug + domain (or "use defaults / defer domain")?
2. Drizzle ORM OK, or do you want Prisma instead?
3. Inngest OK as the workflow layer, or do you want to start with raw Netlify Scheduled + Background Functions and add Inngest later?
4. Operator-dashboard auth at MVP: **email magic-link via Resend** (simplest, no third party) — confirm or pick something else (Clerk, Auth.js w/ providers)?
5. One Netlify team for all five sites, or split (e.g. operator-only sites in a private team)?

Answer those and we run Step 2.
