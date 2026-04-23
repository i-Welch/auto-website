1. SMB Discovery Engine

  The core loop starts here — finding businesses with no/weak online presence.

  - What data sources? Google Maps API gives you business name, address, phone, category, and website (if listed). Are you also scraping Yelp, BBB, Yellow Pages, or state business registrations?
  A: We want to use google maps, yelp, facebook, BBB, Yellow Pages and state business registrations. The "data sources" should ideally be modular so it is easy to add new ways to pull data about potentional clients. Because we have all these different data sources we definitely want to have a deduping mechanism to map what we find in each of these places back to a unified record of a business.
  - How do you define "weak" presence? No website at all is easy. But what about a business with a Facebook page and no site? A site that's a single page from 2014? A GoDaddy parked domain? Where's the cutoff?
  A: We should define a list of services we provide, managing facebook pages, managing yelp pages, managing websites, keeping google info up to date, etc. and based on how many of these we detect a business already has we can give it a weighted score. Ideally we start with lower scored websites and depending on the score and the expected cost appitite of the customer we can increase or decrease the monthly / onboard rate of the service.
  - Geography scoping — are you scanning by zip code, city, or county? Do you start with one metro area to prove the model or go national from day one?
  A: National day 1 but this can be modulated by how we implement the data sources.
  - Business filtering — do you target specific niches (restaurants, salons, contractors, dentists) or cast a wide net? Some niches convert better than others. Contractors and home services tend to have the worst web presence and the highest willingness to pay.
  A: We should not hard filter any business but we should be able to add configs which modulate the score we give business when deciding which to reach out to based on data we collect on the most lucritive and the most high response businesses.
  - How often do you re-scan? New businesses open constantly. Is this a one-time batch per area or a recurring crawl?
    A: We will want to rescan daily but due to how long the scans take there is probably going to be a way for data sources to collect data continously but slowly to not hit rate limits and incrimentally send data back to the system.

  2. SMB Data Store / CRM

  You need a structured way to track every business you find and every interaction.

  - What's the lifecycle? Something like: discovered → audited → demo built → outreach sent → opened → replied → converted → active customer → churned?
  A: Yeah effectively that needs to be the lifecycle. Instead of having an explicit "stage" we should calculate stage based on information we have tracked about a customer/lead.
  - What do you store per business? Name, address, phone, email, category, existing web presence (URLs), Google Maps listing quality score, outreach history, demo site URL, subscription status?
  A: We will want to store everything about a business we find and generate at all points in the lifecycle of an engagement. This should be easily updatable over time and scoped to a buisness. We'll also need to remember we will need to have this structured in such a way which can easily be deduped from sources so we don't try and reach out to the same business multiple times.
  - How do you find the owner's email? Google Maps doesn't give you email. Are you scraping it from existing websites, using Hunter.io / Apollo, or relying on a contact form / phone-based outreach?
  A: We will want to build out an outreach module which can automate outreach to a business based on what data we have. Pulling data about the owner should be done via the data sources. With that in mind data sources should not always be automatic but in some cases should be done for "enrichment" purposes.
  - Do you deduplicate? Same business listed differently on Google vs Yelp vs state records.
  A: Yes

  3. Outreach Package

  This is where you differentiate from "just another cold email."
  *Note*
  We will probably also want to add service modules which we provide to specific types of customers. For instance we can provide restraunt customers with the ability to setup their integration with doordash. Or help people who sell products online setup storefronts on Amazon or Etsy.

  - What's in the package? You mentioned a demo site + audit report. What does the audit cover? I'm thinking: current Google Maps listing (missing hours, no photos, wrong category), missing from key directories, no SSL, mobile-unfriendly, slow load time, no reviews strategy.
  A: We want to track Google Maps listing, websites, social pages (facebook, yelp, etc.). We will want to have the "services" we provide to also be modular so we could add more services and filter services that we provide based on the specifics of the business.
  - Channel — email only? Or also direct mail, SMS, or a phone call? Email deliverability for cold outreach to small businesses is rough. A physical postcard with a QR code to their demo site could convert better.
  A: All these should be on the table. Outreach should also be modular and we can track conversions and what outreach has been sent to what business and if it did or didn't convert in a timeframe. We are going to want to track this and fine tune our outreach model over time. 
  - Who sends it? From a generic brand ("LocalPulse found your business") or personalized ("Hey Mike, I built this for Mike's Auto Body")? The second converts way better but needs owner name resolution.
  A: This will be modular based on the data we have about a business. We will use an LLM to custom craft these and slowly iterate on ones that convert the best.
  - Legal — CAN-SPAM compliance for cold email. Do you need prior business relationship or opt-in? B2B cold email is generally legal in the US but you need an unsubscribe mechanism.
  A: We will provide an unsubscribe in the email and just note not to reach out to that business anymore.

  4. Demo Website Builder

  This is the wow factor — the business owner gets a link to a real site with their name, photos, and info already populated.

  - Where does the content come from? Google Maps has name, address, phone, hours, photos, reviews. Can you pull enough to make a convincing demo without any input from the owner?
  A: We will have to pull as much of the data as we can. We should keep a score of how much data we have about a business so we can determine if the website we build will be high enough quality to be worth while.
  - What tech stack for the generated sites? Static HTML hosted on S3/Cloudflare? A templated CMS like WordPress? A custom builder? Static HTML is cheapest and fastest but harder for the AI to update later. Something like a headless CMS + Next.js template might balance flexibility with cost.
  A: We should choose a techstack which is easy to host, has lots of support, and AI is good with. For this reason I'd ideally like to go with Next.js hosted on Vercel if possible.
  - How many templates? One per niche (restaurant, salon, contractor, dentist) or a generic one? Niche-specific templates with relevant stock photos convert much better.
  A: We will build Niche specific templates with unique twists added for each business by AIs when we send it. The AI should read the data we have collected about the business then use the template as a base, fork it, then update it for the specific business in question and then deploy it.
  - Custom domain? Do you host on a subdomain (mikes-auto.yourbrand.com) for the demo, then move to their own domain when they pay? Or do you buy the domain for them as part of onboarding?
  A: We should use a subdomain initially for the demo but as part of the package we send the customer we should research domains if they do not have a domain already but if they do have a domain we should call out that we can work with the domain they already have. We will need a way to research domains for the outreach packet.
  - How personalized? Just name/address/phone swapped in? Or AI-generated copy about their specific business, services, and area?
  A: Super personlized, as much as possible.

  5. Online Presence Management

  Beyond the website — this is where the recurring value lives.

  - Google Business Profile — do you need the owner to grant access, or are you just auditing and recommending? Updating GBP requires owner verification. This is a friction point.
  A: Ideally we want to get access granted to us. Otherwise we can just recommend changes regularly. We should investigate this flow.
  - Directory listings — which ones matter? Google, Yelp, Bing Places, Apple Maps, Facebook, BBB, Angi, Nextdoor, industry-specific ones. Are you submitting/updating listings or just reporting what's missing?
  A: We should be submitting and updating these reports ourselves if possible. If we need something from the owner we should be able to reach out to them automatically for this via the AI. These details should all be setup when instantiating a "service" module for the business so that it can all work in a decoupled and modular fasion.
  - SEO — what does "ongoing SEO" mean in practice? Blog posts? Meta tags? Local schema markup? Google Maps optimization? This needs to be scoped or it becomes an unbounded cost center.
  A: Uncertain. Is this even valuable?
  - Review management — do you help them get more Google reviews? Send review request links to their customers? This is one of the highest-value things for a local business.
    A: If possible. How are we going to get access to their actual customers though? Is there an easy way for them to integrate with us to provide this functionality?

  6. Payment / Subscription

  - $50/mo to start — what does that include? Website hosting + basic updates? Or website + directory management + SEO + review management?
  A: Everything at 50$/mo to start. This will be fine tuned over time. 
  - Tier structure? Maybe: $50/mo (website only), $150/mo (website + directory + GBP management), $299/mo (everything + content + review management)?
  A: Lets iterate on this in the future. For now lets say just 50$/mo forever with the architecture in place to inmplement per business "tiers"
  - Free trial or freemium? The demo site IS the free trial. "Your site is live at this URL. Pay $50/mo to keep it, or it goes down in 14 days." That's a strong forcing function.
  A: No free trial. The demo site is just to have a wow factor for the foot in the door.
  - Payment processor — Stripe is the obvious choice. Do you need invoicing for businesses that want to pay by check?
  A: Stripe
  - Churn — what keeps them paying month 2, 3, 12? The site alone isn't enough. The ongoing value needs to be visible (monthly report: "you got 47 new views on Google Maps, 3 new reviews, 12 website visits").
  A: The assistant + weekly email reports will keep people thinking about us. That should be our differintiator

  7. AI Phone/Text Assistant (Twilio)

  This is the stickiest part of the product if you get it right.

  - What can they change via text? Hours, phone number, address, photos, menu items, service list, announcements? What's the scope?
  A: They should be able to basically anything via text, especially anything on the website. We want this to be as unrestrictive as possible. To suppor this we will probably need to have guardrails to notify a human if their request isn't possible or is difficult to manage.
  - Which systems does it update? Just the website? Website + Google Maps? All directories?
  A: anything
  - AI model — Claude for understanding intent, structured tool calls to update the CMS and Google APIs? Or something simpler with keyword matching?
  A: Perplexity should be the AI model we are using.
  - Inbound vs outbound — do you also proactively text them? ("Hey Mike, you got 2 new Google reviews this week. Want to reply to them?")
  A: We should include things like this in the weekly report.
  - Voice? You said phone number — do they call and talk to an AI, or is it text-only? Voice adds complexity but some small business owners don't text for business purposes.
  A: For now lets go with just text. Voice can be something we add in the future.

  Biggest Questions to Answer First

  1. Where do you get owner email addresses at scale? This is the bottleneck. You can find millions of businesses without websites, but reaching the owner is the hard part.
  A: Usually if you have a business without a website they will have a facebook page or instagram page or etsy or something like that so we will need to be able to reach out to these people directly there. 
  2. Do you build the demo site BEFORE outreach or AFTER interest? Building before is the wow factor but costs compute. Building after interest is cheaper but loses the magic.
  A: We build it BEFORE outreach as that is the driver we use for conversion.
  3. What's the MVP scope? I'd argue: discovery + demo site + email outreach + Stripe checkout + static hosting. Skip directories, SEO, and Twilio for v1.
  A: That is a good MVP.
  4. Is this a new repo or built on top of RAVEN infrastructure? The AWS stack (Fargate, DynamoDB, SES) could be reused, but this is a fundamentally different product.
  A: No this is a standalone product.