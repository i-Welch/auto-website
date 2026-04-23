# Round 2 Questions

Answer inline under each question (like qna-1.md).

## 1. Discovery Engine

1. **Data source trust hierarchy** — When Google says a business is at 123 Main St and state registration says 125 Main St, which wins? Do you store all variants and pick one for display, or pick a "source of truth" per field?
A: Store all variants. We can even use this to call out inconsistencies that we can fix when reaching out to the businesses.

2. **Dedup keys** — What's your match key? Phone number is most reliable but businesses share lines. Name+address fuzzy match? Do you need a human-review queue for ambiguous merges?
A: We should use name, address, phone number, etc to try and build a deduping algorithm

3. **Rate limit budget** — Google Maps Places API is ~$17/1k calls. At national scale (30M+ SMBs), a full rescan costs $500k+. What's the actual rescan strategy — tiered by score? Only rescan "hot" leads?
A: We should rescan places we think are high value and skip out lower values scans. I'll give the first pass call to your judgement.

4. **Scoring weights** — Who decides the weights for the presence score (no website = +X, parked domain = +Y, Facebook only = +Z)? Is this a config file, a DB table, or learned from conversion data?
A: Start with a config file we will manually update and over time we can use conversion data to update it automatically.

5. **"Lucrative business" config** — You said configs modulate score based on most lucrative/highest-response. Is there a feedback loop from conversion data back into the scoring, or is it manually tuned?
A: feedback loop from conversion data.

## 2. Data Store / CRM

6. **Computed stage** — What signals compute each stage? (e.g., "demo built" = demo URL exists; "replied" = inbound message received). Write these out — it defines your whole event schema.
A: I think this can be easily inferred from the behavior and can be extensible. I don't think its important to fully enumerate them here

7. **Schema flexibility** — "Store everything we find" sounds like JSONB/document store. Are you OK with Postgres+JSONB, or do you want a proper document DB? This affects query patterns.
A: I think document store is probably ideal here.

8. **Enrichment triggers** — When does enrichment run? On-demand before outreach? Scheduled? When score crosses a threshold?
A: Before outreach. We will decide who to prioritize for outreach based on scores.

9. **Audit trail** — Do you need a full history of every field change per business, or just current state? Matters for "why did we reach out to this lead" debugging.
A: Audit trails would be good.

## 3. Outreach Package

10. **Outreach orchestration** — One business could get email → postcard → SMS over weeks. Is this a state machine per business? Who decides the next channel — a rule engine or the LLM?
A: We should have a rule engine which decies what outreach any given type of business gets and in what order. AI can write the first pass of this engine.

11. **Service modules** — How are these defined? A config/registry of service types (restaurant-doordash, ecommerce-etsy, etc.) that the outreach LLM pulls from? Who authors them?
A: These are going to be written in code. A "service module" should have a structured type of input and output and should be configured what types of business it applies to. These will be configued in code at the time the service module is defined.

12. **Conversion attribution** — If a business gets email + postcard + SMS and converts, which channel gets credit? Last-touch? Or do you need multi-touch?
A: multi-touch

13. **LLM outreach quality control** — AI-generated outreach at scale risks deliverability issues (spam filters hate templated LLM output). Are you OK with a human-in-the-loop review for the first N per day until confidence is high?
A: Yes human in the loop at first is fine.

14. **Sender infrastructure** — Cold email at volume requires domain warming, multiple sending domains, SPF/DKIM/DMARC. Are you planning to use SES, SendGrid, Instantly, or build your own?
A: Which would you recommend to keep costs down and deliverability high.

## 4. Demo Website Builder

15. **Vercel cost model** — A demo per business at national scale = millions of deployments. Vercel pricing can explode. Have you checked if this fits, or should demos be static HTML on S3/CF until conversion, then migrated to Vercel on activation?
A: Static S3 at first then converted to vercel sounds good. Is there a way we can build in vercel then deploy to s3 based on the next.js output, only to later use that same code to deploy a next.js site

16. **Template authoring** — Who writes the niche templates? You? AI-generated? A freelancer? And how do you version them?
A: AI generated

17. **"Fork template + customize" pipeline** — Is this a code-gen pipeline (AI writes TSX files and commits) or data-driven (template reads from a CMS with per-business data)? These have very different cost/maintenance profiles.
A: AI driven

18. **Demo expiration** — If they don't convert, does the demo stay up forever? 30 days? Deleted? This affects storage and also re-outreach possibilities.
A: 30 days. We should update the place the dead link directs to so that they land on a page saying "Hey! it's been a while since we sent this so we took down the site, if you want to see it reach out to us here ->" with a link to give us their contact info and it will automatically trigger re-engagement. This doesn't have to be fully built out for MVP

19. **Domain research** — What does this mean concretely? Check availability via a registrar API (Namecheap, Cloudflare) and suggest 3-5 options in the outreach? Is domain purchase included in $50/mo or a one-time add-on?
A: Yeah this means check availability for good domains via a registrar. AI should come up with options to find good fits for the business. If it is cheap we should include it in the $50/mo if not we may have to include it as an addon price if that they want a more expensive domain but we shouldn't reach out to suggest a domain which costs over 100$

20. **Photos** — Demos need images. Pull from Google Maps (licensing risk), use stock (generic feel), or AI-generate (uncanny)? Which is the default?
A: We should have all 3 be viable. Using stock, Google Maps, AI generated and using AI to augment and update Google Maps and stock photos.

## 5. Online Presence Management

21. **GBP access flow** — Investigation complete? Google's process requires owner verification (postcard or phone). You can request manager access via email. Do we treat this as a post-signup onboarding task with AI text guiding them through granting access?
A: Yes lets do that

22. **Directory submission automation** — Most directories (Yelp, BBB, Apple Maps) don't have clean APIs. Are you OK with either (a) human VAs executing AI-generated scripts, or (b) scraping/automation that risks account bans?
A: We can start with human in the loop for the first few customers. Revisit in the future.

23. **SEO scope** — Your answer was "uncertain, is this valuable?" Proposal: skip generic SEO for MVP, only do local-SEO basics (schema markup, NAP consistency, GBP optimization). These are automatable and high-value. Agree?
A: Agree

24. **Reviews integration** — For review request automation you'd need their customer contacts. Options: (a) POS integration (Square/Toast/Clover) — complex but powerful; (b) owner uploads CSV; (c) QR code at checkout. Which for MVP?
A: Lets say we can integrate with Square/Toast/Clover as per MVP

## 6. Payment / Subscription

25. **Activation flow** — Owner clicks demo → clicks "Pay $50/mo" → Stripe checkout → what happens next? Auto-publish to subdomain immediately? Gate on email verification? Gate on a 5-min onboarding call/chat?
A: Yes. Make sure to flesh this out. I trust your judgement

26. **Domain ownership** — If they already have a domain, we need DNS access or transfer. What's the automated flow — AI texts them instructions + a verification code?
A: Defer this for now.

27. **Refund/cancellation** — Cancel-anytime, pro-rate, or 30-day minimum? Does the site go down immediately on cancel or end-of-period?
A: Allow people to cancel anytime and we will take down the site immediately. If they just stop paying or there is a failure to pay lets flag it as needing human investigation and let a human make a final call to terminate them.

28. **Weekly report content** — Who generates this? LLM from raw metrics? What metrics do we even have access to (GBP insights API, site analytics, review counts)? Spec this out — it's your retention story.
A: LLM should do this based on services and data based on things like google review, site analytics, etc. Let AI do a first pass at what we have in here but a lot of this will depend on the specific services we build out and what data sources we have access to for a business.

## 7. AI Assistant (Twilio + Perplexity)

29. **Perplexity for this use case** — Perplexity is optimized for search/research, not tool-calling or structured outputs. For "text 'change my hours to 9-5'" you need strong tool-use. Claude or GPT-4 are stronger there. Is Perplexity a hard requirement or preference?
A: Lets go with claude for now. Could perplexity Computer not do it?

30. **Ambiguity handling** — Owner texts "update my site with the new menu" — the AI needs to ask clarifying questions, handle images, confirm before publishing. Is there an explicit confirmation step before any write, or does it just apply?
A: The AI should be smart enough to ask clarification questions but we should generate a demo link for the customer first to confirm the changes to the site and only if the user signs off on the changes in the demo link should the website changes be commited publicly. Other service updates should follow a similar "you confirm you want change x,y,z" and the user has to say yes before the changes are made.

31. **Human escalation queue** — You mentioned guardrails notify a human. Who's the human? Is there a support inbox/dashboard? SLA expectations?
A: We will setup an email inbox for the humans working with this product. Just make it an email that gets sent.

32. **Identity verification** — How do you confirm the texter is the owner and not a disgruntled ex-employee? Phone number match at signup only, or periodic re-auth?
A: Lets just go with a signup match for now and handle auth at some point in the future. We will probably want an email auth at some point as well.

33. **Change audit log** — Every AI-driven change should be logged and reversible. Undo via text ("undo last change")?
A: Makes sense. This should be for all changes AI or otherwise.

## Cross-cutting / Architecture

34. **Monorepo or multi-repo?** Discovery, CRM, site generator, assistant, billing — one repo with packages, or separate services?
A: Monorepo

35. **Deployment target** — You mentioned Vercel for generated sites. What about the backend (discovery workers, CRM API, assistant)? Vercel functions, Fly.io, Railway, AWS?
A: Lets go with a simple AWS service deployment.

36. **Language/framework** — Next.js for sites is decided. Backend — also TypeScript/Node (shared types with frontend) or Python (better for scrapers/ML)?
A: Next.js for front-ends. Typescript/Node for backend.

37. **Secrets & API keys** — Google Maps, Yelp, Stripe, Twilio, LLM APIs. Vault? Just env vars per environment?
A: Env vars are fine

38. **Observability** — How do you know the discovery worker is running, the outreach is sending, demos are being built? Logging/metrics stack from day one?
A: Sentry for observability

39. **Multi-tenant or single-tenant?** You're the sole operator, but do you plan to white-label this later (sell to agencies)? Affects data model now.
A: No plan today to whie label

40. **Compliance** — Storing PII (business owner names, phones, emails) at scale. CCPA deletion requests? GDPR isn't US but if you hit a business with an EU owner...?
A: Don't worry about it today

## Biggest decisions to nail before building

- **A.** Build demo BEFORE outreach is decided — but at what scale? 100 demos a day? 10k? This determines infra choices.
A: Yes we build before outreach

- **B.** What's the ONE niche for the first 100 customers? You said no hard filter, but for MVP proof, picking one (e.g., contractors in Texas) lets you tune the entire loop end-to-end before generalizing.
A: What would the best niche be?

- **C.** What's the "definition of done" for MVP — your first paying customer, or 10, or a working demo for a judge?
A: 10 Paying customers is the milestone we want
