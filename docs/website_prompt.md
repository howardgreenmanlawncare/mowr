# Build prompt — MOWR marketing website

> Paste everything below the line into a fresh Claude Code session (in an empty
> repo/folder). It is self-contained: all design tokens, content, and structure
> are inline, so the agent does not need access to the MOWR app codebase.

---

You are building the **public marketing website** for **MOWR**, an on-demand
lawn-mowing marketplace operating in the UK (initially around Colchester,
Essex). This is a brochure/marketing site — **not** the app itself. It explains
what MOWR is, converts customers into bookings, and recruits mowers.

The site must look like it belongs to the same product family as the MOWR app,
which uses a **Swiss / International Typographic Style** design system (below).
Match it exactly.

## 1. Objective & audiences

Three audiences, in priority order:

1. **Customers** who want their lawn mowed — get them to "Book a MOWR" (or join
   the waitlist / download the app).
2. **Prospective mowers** — recruit them via a "Become a MOWR" path.
3. **Investors / press** — a credible, honest overview of the business and where
   it's heading.

Primary conversion is the customer booking CTA; secondary is mower recruitment.

## 2. Tech constraints

- Build a **static, fast, self-contained site**. Default stack: **semantic HTML
  + one hand-written CSS file** using CSS custom properties for the design
  tokens (this mirrors how the app centralises tokens). Minimal vanilla JS only
  where needed (mobile nav, FAQ accordions, theme toggle). No heavy frameworks
  unless you have a strong reason; if you prefer, Astro is acceptable, but keep
  the output static and dependency-light.
- **Arimo** (Helvetica-compatible) as the typeface, via Google Fonts or
  self-hosted. This is deliberate — the app uses Arimo.
- Fully **responsive** (mobile-first) and **theme-aware** (light + dark, see
  tokens). Respect `prefers-color-scheme`, plus a manual toggle.
- **Accessible**: semantic landmarks, keyboard-navigable, visible focus rings,
  WCAG AA contrast, `alt` text, reduced-motion support.
- No external tracking/analytics unless asked. No cookie-wall; if any banner,
  default to privacy-preserving.
- All assets self-contained. Use tasteful inline SVG for icons and simple
  illustrations (line icons, not filled/decorative). Placeholder imagery is
  fine but must be captioned as such.

## 3. Design system (match exactly)

**Direction:** ink on paper, one signal green, flush-left grid, **hairline rules
instead of boxes/shadows**, crisp **5px** radius, generous whitespace. Green is
**rationed** — it appears only on the primary action, a selected/active state,
and "live / available / success" signals. Everything else is neutral. Never use
green decoratively.

### Color tokens

Light (default):

```
--paper:        #F5F5F2;  /* page background */
--surface:      #FFFFFF;  /* cards / raised areas */
--ink:          #121211;  /* primary text */
--graphite:     #6E6E69;  /* secondary text */
--hairline:     #E3E3DE;  /* 1px rules & borders (in place of shadows) */
--neutral-fill: #EDEDE8;  /* inert chips / quiet fills */
--green:        #2E6A43;  /* brand signal: primary action, active, available */
--green-dark:   #1F4C30;  /* hover/pressed, text-on-pale */
--green-pale:   #E9F0EA;  /* success/live wash */
--warning:      #C98A2B;
--warning-pale: #F7EDD9;
--error:        #C0473E;
--error-pale:   #F6E2E0;
```

Dark theme — invert the paper/ink relationship while keeping green as the single
signal. Suggested (tune for AA contrast):

```
--paper:        #121211;
--surface:      #1B1B19;
--ink:          #F3F3EF;
--graphite:     #A3A39C;
--hairline:     #2E2E2B;
--neutral-fill: #24241F;
--green:        #4E9A6B;  /* lift green for contrast on dark */
--green-dark:   #6FB98A;
--green-pale:   #17251B;
```

### Typography

- Family: **Arimo**, system-sans fallback (`Arimo, "Helvetica Neue", Arial,
  sans-serif`).
- Flush-left, tight but readable. Use a clear type scale, e.g.:
  - Display / hero: ~48–64px, weight 700, tight line-height (~1.05).
  - Page heading: ~28px / 700.
  - Section heading: ~18–20px / 600.
  - Body: ~16px / 400, line-height ~1.55.
  - Support / caption: ~13px / 500, often `--graphite`.
  - Big stat figures: 32–56px / 800 (for any metric/stat blocks).
- **Eyebrow** label pattern: ~12px, uppercase, letter-spacing ~0.08em,
  `--graphite`, sits above a heading.

### Layout & components

- Max content width ~1080–1200px, comfortable gutters, lots of air.
- **Hairline dividers** (`1px solid var(--hairline)`) to separate sections and
  rows — prefer these over card shadows/boxes.
- **Cards**: white `--surface`, `1px solid var(--hairline)`, `border-radius:
  5px`, no drop shadow (or an almost-imperceptible one at most).
- **Buttons**:
  - Primary: solid `--green` fill, white text, 5px radius, ~52px tall, generous
    horizontal padding; hover → `--green-dark`.
  - Secondary: transparent with `1px solid var(--hairline)`, `--ink` text.
  - Tertiary: text/underline link in `--green-dark`.
  - One clear primary action per section.
- **Pills/badges**: used for **status only** (e.g. "Available", "Live",
  "Coming soon"). Green pill = available/live; neutral pill = informational.
- **Stat block** pattern ("hero figure + supporting row"): one large figure with
  a label, then a hairline-separated row of 2–3 smaller supporting stats.
- Line icons only (inline SVG, ~1.5px stroke), never filled/cartoonish.
- Motion: subtle, fast, purposeful (fades/slide-ins ≤300ms); honor
  `prefers-reduced-motion`.

Reference the app's own splash animation as the brand's motion signature: an
icon settling in from the top and a wordmark rising from the bottom to meet it —
you may echo that gentle, precise feel on the hero.

## 4. Brand & naming

- Product name is **MOWR** (all caps wordmark). Tagline: **"Lawn mowing, on
  demand."** Supporting line: **"Vetted local mowers. Book in minutes, pay when
  it's done."**
- **The real brand assets are provided in this project at `assets/brand/` — use
  them, do not fabricate a logo:**
  - `assets/brand/mowr_wordmark.png` — the MOWR wordmark (dark ink on
    transparent). Higher-res variants live in `assets/brand/2.0x/` and
    `assets/brand/3.0x/`; use `srcset` (1x/2x/3x) or just the largest for
    crispness. This is the header/nav/hero logotype.
  - `assets/brand/mowr_icon.png` — the square "swoosh" app icon (1254×1254).
    Use it for the **favicon**, the **apple-touch-icon**, and the social/OG
    share image (generate the required sizes from it — e.g. 32, 180, 512, and a
    1200×630 OG card with the icon on a paper `--paper` background).
  - **Dark theme:** the wordmark is dark ink, so on dark backgrounds either use a
    white/inverted copy (create `mowr_wordmark_light.png`, or apply
    `filter: invert(1) brightness(1.6)` if it's cleanly monochrome), or fall
    back to setting "MOWR" as Arimo text. Pick whichever looks cleanest and note
    it in the README. The icon reads fine on both themes.
  - Give the nav wordmark an accessible name (`alt="MOWR"`), and set a sensible
    `max-height` (~24–28px in the nav, larger on the hero).
- Voice: confident, plain-English, premium-but-friendly service marketplace —
  think a modern delivery/《on-demand》 brand, not a twee gardening company.

## 5. Information architecture (pages/sections)

Single-page marketing site with anchored sections is fine, plus a couple of
sub-pages. Structure:

1. **Home (long-form landing)**
   - Sticky, minimal top nav: MOWR wordmark left; links (How it works, Pricing,
     For mowers, FAQ) center/right; **"Book a MOWR"** primary button; light/dark
     toggle.
   - **Hero**: tagline, supporting line, primary CTA ("Book a MOWR") + secondary
     ("Become a MOWR"). Eyebrow "Vetted local mowers". Clean, lots of paper.
   - **How it works (customer)** — 5 numbered steps on a hairline grid:
     1. Enter your postcode — we find your address.
     2. Mark your lawn on the satellite map (or we measure it) — instant size.
     3. Choose grass height, edging, and how often (one-off or recurring).
     4. See your price up front and book — no quotes, no waiting.
     5. Track your mower live and pay only when the job's done.
   - **Trust & safety** — the differentiators:
     - Every mower is **vetted and phone-verified**, and paid through **Stripe**
       (identity-checked via Stripe's KYC).
     - **Pay only when it's done** — money is held and taken on completion.
     - **Live tracking + ETA**, like home deliveries.
     - **In-app messaging** with your mower once they're on the way.
     - **Ratings** keep quality high.
   - **Recurring & loyalty** — set it and forget it: weekly / fortnightly /
     every few weeks, with loyalty discounts (e.g. an example "your 3rd mow is
     20% off"). Mark example figures as illustrative.
   - **Pricing** — transparent, per-square-metre pricing with a turn-up fee and
     a minimum; edging as an add-on. Present as "from" figures and **clearly
     label placeholder/illustrative rates** (real rates are set by the operator
     — see Honesty rules). Show a simple worked example.
   - **For mowers (recruitment band)** — short pitch + link to the mower page:
     good local work, keep more as you build your rating, fast payouts, plan
     your day automatically.
   - **FAQ** — accordion (see content below).
   - **Footer** — nav, contact, small print, "illustrative figures" disclaimer,
     social placeholders.

2. **/mowers — "Become a MOWR"** (recruitment landing)
   - How earnings work; **fair, performance-based commission that drops as you
     complete jobs and earn good ratings** (tiered — e.g. Bronze → Silver →
     Gold); **fast payouts via Stripe Connect**; **auto-planned days** (jobs
     allocated efficiently the night before, routed to minimise driving);
     requirements (vetting, phone verification, payout onboarding). Primary CTA
     "Apply to mow".

3. **/investors — investor brief** (its own page; content in §6.5). Linked
   discreetly from the footer (not the primary nav) with a small "Investors"
   link. Same design system, but a denser, more data-forward layout.

4. **/pricing** (optional dedicated page, or the home section is enough).

Keep an obvious, repeated **"Book a MOWR"** CTA throughout the customer-facing
pages (not on the investor page).

## 6. What MOWR actually is (background so copy is accurate)

Use this to write truthful copy. Do not overstate.

- On-demand lawn-mowing marketplace. Three roles: **customer**, **mower**,
  **admin** (admin is internal, not part of this site).
- **Customer flow**: postcode → address lookup → confirm location on a satellite
  map → **draw the lawn boundary on satellite imagery** (area/perimeter derived
  automatically) or enter size manually → choose per-lawn grass height, access,
  and edging → choose schedule (ASAP or a date + time window) and recurrence
  (one-off / weekly / every 2 wks / every 3 wks / custom every-N-days, with a
  preferred day) → see a transparent price → create account → pay (card via
  Stripe; **payment is authorised and only captured when the job completes**) →
  track status live with a delivery-style tracker and rough ETA → rate the mow.
- **On-site fairness**: a mower can re-measure on arrival; if the price changes
  beyond a threshold the customer must approve before any extra is charged.
- **Recurring + loyalty**: recurring bookings auto-generate; loyalty discounts
  (e.g. Nth mow discounted). Recurring jobs are **auto-allocated to opted-in
  mowers the night before**, routed efficiently.
- **Mower experience**: see available jobs, accept, get turn-by-turn directions;
  the **exact street address is hidden until they're en route** (only the
  postcode shows before then — anti-circumvention); earnings dashboard with CSV
  export; payouts via **Stripe Connect**; **commission drops with tenure +
  ratings** (admin-tunable tiers); an in-app route map of the day's stops.
- **Trust/anti-fraud**: vetted + phone-verified mowers; en-route customer↔mower
  chat; reliability tracking (repeatedly dropping jobs is flagged); everything
  is designed to keep the job **on-app**.
- **Scaling vision** (roadmap, be honest): recurring jobs auto-allocated across a
  fleet, customer ETAs, "like home deliveries"; future accounting integrations
  (Xero/QuickBooks) and DBS background checks.

## 6.5 Investor page content (`/investors`)

A single long-form investor brief, same Swiss design system but denser and more
data-forward (numbered sections, hairline-separated stat blocks, small labelled
tables). Every aspirational item is tagged **Built** / **Roadmap** exactly as
below. Every figure is labelled **illustrative** where noted. Do not add claims
beyond these.

**Header:** eyebrow "Investor brief · pre-launch". Headline: *"Lawn care, on
demand — becoming the logistics network for recurring home services."* Sub:
*"Draw your lawn, get an instant price, book a vetted local mower — pay only when
it's done. Then it repeats on its own: recurring jobs allocated to the nearest
available mower the night before, with a live ETA. Like food delivery, for the
outside of the home."* Three quiet facts under it: **Product built** · Single
Flutter app, 3 roles — **In-house routing engine** — **United Kingdom**.

**01 The problem — "Booking a mow is still stuck in the classifieds era."**
Every other everyday service is instant with a price and an ETA; lawn care isn't
— homeowners chase quotes, wait for callbacks, get no-shows, pay cash; mowers
waste half the day on inefficient routes and chase invoices. Three cards: *For
homeowners* (opaque pricing, slow quotes, unvetted strangers, no tracking,
cash-in-hand); *For mowers* (feast-or-famine, dead miles, chased payment); *The
gap* (lawns need doing every 1–4 weeks forever — recurring revenue nobody has
productised).

**02 The solution — "A price in seconds, a vetted mower, paid when it's done."**
A three-sided marketplace (customer, mower, admin) in one app on one backend.
Four **Built** points: *Draw your lawn, see your price* (trace on satellite,
geodesic area/perimeter, instant price for mowing/edging/grass length, real UK
rooftop-level address lookup); *Book a vetted local mower* (admin-approved,
phone-verified, KYC'd via payouts; **background checks = Roadmap**; pay only
after completion); *On-site honesty, not disputes* (mower re-measures on site;
server recomputes; over a threshold the customer approves before any charge);
*Mowers get paid automatically* (Stripe Connect payouts + KYC; per-mower
commission; live earnings, route, one-tap nav).

**03 Traction on the product, not vanity metrics — "Pre-launch, but the hard
parts are already built."** Three stat blocks: **3-in-1** (customer, mower &
admin in one Flutter codebase on one Supabase backend); **£0** per-job routing
cost (in-house scheduling & route optimiser — no per-trip SaaS); **15%** default
take rate per job (tunable per mower, one pricing engine).

**04 Where this goes — "The recurring engine: subscriptions, auto-allocated the
night before, with an ETA."** A one-off mow is a transaction; a lawn mowed every
fortnight forever is a subscription, and fulfilling thousands efficiently is the
real business. Four steps: **STEP 1** customer sets a rhythm ("every 2 weeks",
booked once, recurs — *Built*); **STEP 2** the night before, an optimiser
gathers due jobs + opted-in mowers and allocates each to the most efficient
mower (*Roadmap — engine built*); **STEP 3** each mower gets an optimised day,
least driving, honouring windows (*Built, tested*); **STEP 4** customer gets an
ETA ("arrives ~10:40am") (*Roadmap*). Note the route optimiser (step 3) is
written and unit-tested today; the fleet allocator (step 2) is the same engine
applied across every mower; routing is kept deliberately in-house.

**05 Why this team, why now — "A logistics company wearing a lawn-care coat."**
Six cards: *Owns the hard part* (in-house scheduling & routing — OR-Tools /
self-hosted OSRM at scale — not rented SaaS; economics improve with growth);
*Recurring by nature* (lawns regrow; demand is built-in and predictable);
*Expandable surface* (adding a service is a data row — hedges, gutters,
pressure-washing, snow — same network, more revenue per address); *Measured, not
guessed* (geodesic satellite measurement → fair, instant, dispute-free pricing +
clean allocation data); *Trust built in* (vetting, phone-dedup, on-site
re-measure approval, pay-on-completion, Connect KYC); *Density flywheel* (more
customers per postcode → tighter routes → more jobs per mower-hour → better pay →
more mowers → faster service).

**06 Market · illustrative — "Millions of UK lawns, cut on a schedule, paid in
cash today."** ~23m UK households, a large share with a garden and lawn; routine
recurring spend served by a long tail of sole-traders and cash jobs. Three
figures, all **illustrative**: **~15m** UK households with a private garden;
**£20–40** typical spend per mow, every 1–4 weeks in season; **Fragmented**
(served almost entirely by sole traders with no software/brand/network).
Footnote: *directional market context for framing, not company performance.*

**07 Business model · illustrative unit economics — "A clean take rate on a
repeating basket."** MOWR keeps a commission on every job (15% default, tunable),
and the magic is recurrence. Show an **illustrative** small table — one recurring
customer, a 200 m² lawn + edging on a fortnightly plan (≈22 mows/yr): *Customer
pays* £54.00 / £1,188; *Mower payout (85%)* £45.90 / £1,010; *MOWR gross (15%
take)* £8.10 / £178. Then three cards: *Recurring > one-off* (one acquisition,
years of margin; a loyalty engine "3rd mow 20% off" drives the switch); *Density
lifts it* (tighter routes → more jobs per mower-hour → more absolute margin
without raising prices); *More per address* (each new service stacks revenue on
customers already acquired). Footnote: *example only, using MOWR's real pricing
structure and commission — not a forecast or current result.*

**Investor-page honesty (hard rules):** keep every **Built** / **Roadmap** tag
exactly as above — never upgrade a Roadmap item to Built. Keep every
**illustrative** label on market and unit-economics figures. No fundraising ask,
valuation, or financials beyond the illustrative table unless the operator adds
them. A short footer line: *"'Built' = working in the product today. 'Roadmap' =
designed, some components built, not yet the shipped end-to-end experience.
Figures marked illustrative are directional, not results."*

## 7. FAQ content (write full answers in MOWR's voice)

- How does MOWR work? (the 5 steps)
- How is the price calculated? (per m² + turn-up + minimum; edging add-on; shown
  up front; illustrative rates)
- When am I charged? (only after the mow is completed; card authorised at
  booking, captured on completion)
- What if my lawn is bigger/smaller than measured? (mower can re-measure on
  site; big changes need your approval before any extra is charged)
- Are the mowers vetted? (yes — vetting + phone verification + Stripe identity
  checks; ratings)
- Can I book regular mows? (yes — weekly/fortnightly/etc., with loyalty
  discounts)
- What areas do you cover? (currently around Colchester/Essex, expanding — frame
  honestly; offer a waitlist for other areas)
- Can I message my mower? (yes, once they're on the way)
- How do I become a mower? (link to /mowers)
- How do mowers get paid? (Stripe Connect payouts; commission drops with good
  work)

## 8. Honesty rules (mandatory — from the project's investor brief)

- Only describe as available what genuinely exists in the product. Anything
  aspirational must be visibly labelled **"Roadmap" / "Coming soon"**.
- Any numbers (prices, discounts, earnings, coverage, ratings) that are examples
  must be labelled **"illustrative"** and must not be presented as guarantees.
- Don't invent testimonials, customer counts, logos of partners, awards, or
  press. Use clearly-marked placeholders where such content would go.
- Pricing shown is **placeholder** unless the operator supplies real rates —
  make that unmistakable (e.g. a footnote), and centralise the numbers so they
  can be swapped in one place.

## 9. Deliverables

- A complete, runnable static site (open `index.html` directly, or a trivial
  `npm run dev` if you choose Astro).
- Design tokens centralised as CSS custom properties in `:root` (+ dark theme),
  so colors/rates aren't hard-coded across files.
- Content for Home + /mowers + **/investors** (+ /pricing if separate), all
  sections above.
- The real brand assets from `assets/brand/` wired in (nav/hero wordmark,
  favicon + apple-touch + OG image from the icon), with a working dark-theme
  wordmark treatment.
- A short `README.md`: how to run it, where the tokens live, where the brand
  assets are, where to plug in real pricing, and which items are placeholders /
  illustrative.

## 10. Acceptance criteria

- Looks unmistakably like the MOWR app: paper/ink, rationed green, hairline
  rules, 5px radius, Arimo, flush-left grid, generous whitespace.
- One clear primary CTA per section; "Book a MOWR" reachable from anywhere.
- Passes a basic a11y check (landmarks, contrast AA, keyboard, focus, alt text,
  reduced motion) and looks right in **both light and dark**, mobile → desktop.
- No unlabelled aspirational claims and no unlabelled example figures. On
  `/investors`, every **Built**/**Roadmap** tag and every **illustrative** label
  is present exactly as specified.
- The real MOWR wordmark and icon are used (nav, hero, favicon, OG image), and
  the wordmark is legible in both light and dark themes.
- Fast: minimal JS, no layout shift, self-contained assets.

Start by scaffolding the token/CSS foundation and the top nav + hero, show me
that, then build the remaining sections.
