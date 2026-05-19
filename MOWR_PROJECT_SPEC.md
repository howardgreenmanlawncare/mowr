# MOWR — Project Specification & Build Blueprint

> This is the source of truth for the MOWR app. It is written to be dropped into
> the project repo and used to seed `CLAUDE.md`. Keep it updated as decisions change.

---

## 1. What MOWR is

An on-demand lawn mowing marketplace. A customer books a local lawn mow in a few
taps; a vetted local mower is assigned and fulfils the job; operations are managed
by an admin. Designed to expand to other garden services (hedge trimming, leaf
clearance, waste removal) over time.

**Three roles, one app, one backend:**

- **Customer** — books and pays for mows, tracks status.
- **Mower** — applies to join, gets assigned/claims jobs, marks them complete.
- **Admin** — vets mowers, manages bookings and assignments, runs operations.

---

## 2. Architecture (decided — do not revisit without explicit decision)

- **One Flutter codebase, role-based.** On login the app reads the user's role
  from their profile and routes to the customer experience or the mower
  experience. Not separate apps.
- **Admin is a web surface.** Flutter builds to web; admin is the same codebase,
  web target. Early on admin may be just the Supabase dashboard; a proper admin
  UI comes later.
- **One Supabase project** for all roles, with Row Level Security enforcing role
  boundaries (customers see only their own data; mowers see assigned/available
  jobs; admin sees everything).
- **Services are data, never code.** Services, extras, and pricing live in the
  database. Adding a new service later must be a data change, not a code change.
  This is a hard architectural rule from day one.

## 3. Tech stack

| Concern            | Choice                  | Notes |
|--------------------|-------------------------|-------|
| UI framework       | Flutter (stable)        | One codebase: Android, iOS, web (admin) |
| State management   | Riverpod                | Repository pattern wrapping Supabase |
| Routing            | go_router               | Auth + role based redirects |
| Backend / DB       | Supabase (Postgres)     | Auth, DB, Realtime, Storage |
| Payments           | Stripe                  | Direct — see §7 |
| iOS builds         | Codemagic (cloud macOS) | No Mac owned; see §7 |
| Source control     | Git + GitHub            | Required for Codemagic anyway |
| Dev environment    | Windows + VS Code + Claude Code (native Windows) | |

## 4. Data model (first cut — design fully now, build incrementally)

Designed up front so the mower and admin features need no schema rework. Claude
Code implements these as Supabase migrations; column lists are indicative, not
final.

- **profiles** — extends `auth.users`. `id`, `role` (customer|mower|admin),
  `full_name`, `phone`, `created_at`.
- **service_areas** — `id`, `outward_code` (postcode prefix), `is_active`.
  Drives the "do we cover this area?" check.
- **services** — `id`, `slug`, `name`, `description`, `is_active`, `sort_order`.
- **service_extras** — `id`, `service_id` (nullable = global), `slug`, `name`,
  `price`, `is_active`. (Edge trimming, waste removal, etc.)
- **pricing_rules** — `id`, `service_id`, `factor_type`
  (base|size|grass_length|access), `factor_key`, `amount`, `is_active`.
  Stores the parameters the pricing formula reads. **Price is computed by a
  defined formula owned by the product owner (not ad-hoc).** The exact formula
  must be supplied before Phase 2 and implemented in ONE place (a `PricingEngine`
  / Supabase function), with these rows as its inputs so prices stay tunable
  without code changes.
- **ratings** — `id`, `booking_id`, `rated_by` (customer), `mower_id`,
  `stars` (1–5), `comment`, `created_at`. One rating per completed booking.
- **device_tokens** — `id`, `profile_id`, `token`, `platform`
  (ios|android), `created_at`. For push notifications.
- **addresses** — `id`, `customer_id`, `line1`, `city`, `postcode`, `lat`,
  `lng`, `access_notes`.
- **bookings** — `id`, `customer_id`, `address_id`, `service_id`, `status`
  (requested|paid|assigned|in_progress|completed|cancelled), `scheduled_date`,
  `time_window` (morning|afternoon|evening), `lawn_size`, `grass_length`,
  `access_type`, `areas` (front/back), `total_amount`, `currency`, `created_at`.
- **booking_extras** — `booking_id`, `service_extra_id`, `price_at_booking`
  (snapshot price so historical bookings stay correct if prices change).
- **booking_photos** — `id`, `booking_id`, `storage_path`, `label`.
  Files in Supabase Storage.
- **mower_applications** — `id`, `email`, `full_name`, `phone`, `status`
  (pending|approved|rejected), `notes`, `created_at`. Recruitment intake; can
  exist before the applicant has an account.
- **mower_profiles** — `id` (FK profiles), `service_areas_covered`,
  `vetting_status`, `is_active`. For approved mowers.
- **assignments** — `id`, `booking_id`, `mower_id`, `status`
  (offered|accepted|declined|completed), `assigned_by`, `accepted_at`,
  `completed_at`.
- **payments** — `id`, `booking_id`, `stripe_payment_intent_id`, `amount`,
  `currency`, `status` (pending|succeeded|refunded), `created_at`.

Booking status lifecycle: `requested → paid → assigned → in_progress →
completed` (with `cancelled` reachable from early states). Customer sees status
changes live via Supabase Realtime.

## 5. Phased roadmap

Same destination (all three roles) — sequenced so something real works early.

- **Phase 0 — Foundation.** Real project created, Android emulator, Claude Code
  pointed at it, Git/GitHub, project structure, Riverpod, design system
  extracted from the demo. Full schema (§4) drafted as migrations.
- **Phase 1 — Customer booking flow, no backend.** Real navigation (go_router),
  form state (Riverpod), Booking model, mock data. Visual target = the demo.
- **Phase 2 — Supabase.** Auth with roles, schema live, persist bookings, photo
  storage, basic mower-application intake form (so recruiting can start).
- **Phase 3 — Payments.** Stripe; charge on booking request.
- **Phase 4 — Mower app + admin + ratings + notifications.** Mower role
  experience (see/accept/complete assigned jobs), admin web view (vet mowers,
  manage and assign bookings), realtime status to customer, **customer rates
  the mower after completion (in v1)**, **push notifications for status
  changes (in v1)**.
- **Phase 5 — Scale.** New services as pure data, polish, store submission.

First milestone to aim at: end of Phase 3 — a real, signed-in, paying customer
app, with mower recruitment intake already live.

## Build sequencing (decided)
- Phase 1 continues mock-first, no backend, as planned. Properties and lawn 
  areas are mocked in Phase 1.
- Phase 2 leads with the backend. Real Supabase property and lawn_area 
  tables; selection screens query per-property from the database rather 
  than passing lists between screens in memory.
- Developer preference from Phase 2 onward is schema-first. Mock-first is 
  Phase 1 only, chosen because the booking flow was still being designed.

## Marketplace Model — MOWR

### §1 — What kind of marketplace this is
MOWR is a two-sided marketplace. The three parties are:
- **Customer** — posts a job by completing the booking flow and paying.
- **Independent mower** — a vetted sole trader or individual who accepts 
  and completes jobs.
- **Platform (MOWR)** — sets prices, vets mowers, processes payments, 
  takes a commission.

### §2 — Decided mechanics

**Pricing**
Platform-set, not mower-set. Customers never haggle; a price is shown at 
step 11 (Review & Pay) before payment. The pricing formula is undecided 
(see OPEN QUESTIONS below), but the principle is locked.

**Job broadcast & acceptance**
New jobs are broadcast to all eligible nearby mowers simultaneously. The 
first mower to tap "Accept" claims the job. This is the decided mechanic; 
no bidding, no manual admin assignment.

**Mower vetting**
Mowers apply and are vetted by admin before their first job. A mower 
account in `pending` or `rejected` status cannot receive or accept jobs.

**No-acceptance handling**
If no mower accepts within a broadcast window, the job is re-broadcast or 
admin is alerted. The broadcast window duration is undecided (see OPEN 
QUESTIONS).

**Availability**
Mowers declare availability. Jobs are only broadcast to available mowers. 
Availability granularity is undecided (see OPEN QUESTIONS).

### §3 — Job lifecycle (state machine)

```
draft → confirmed → broadcast → accepted → in_progress → completed
                  ↓                ↓
               expired          cancelled
```

| State | Triggered by |
|-------|-------------|
| `draft` | Customer starts booking flow |
| `confirmed` | Payment captured / authorised |
| `broadcast` | System sends job to eligible mowers |
| `accepted` | First mower taps Accept (atomic claim) |
| `in_progress` | Mower taps Start on arrival |
| `completed` | Mower taps Complete |
| `expired` | No acceptance within broadcast window |
| `cancelled` | Customer cancels (pre-acceptance), or admin |

### §3a — Cancellation model

> Extension of §3 (job lifecycle). Covers all four cancellation
> transitions. DECIDED items are stable in principle. Money mechanisms are
> deferred to §5 (Stripe-gated). Named dependencies are recorded
> explicitly, not hand-waved.

**Case A — Mower accepts, then cancels before doing the work — DECIDED**

Job side: the job auto-re-broadcasts to other eligible available 
mowers. The customer IS notified that it happened (honest, low-drama: 
"your mower became unavailable, we're finding another"). It does NOT 
silently re-broadcast, and it does NOT drop all the way back to the 
no-acceptance retry/wait flow.

Mower side: the first such cancel is a tracked warning, no immediate 
penalty. Consequences escalate on a pattern (one cancel = bad luck; 
repeated = behaviour). A genuine one-off emergency self-absorbs because it 
creates no pattern — no adjudication process required.

Named dependency (open, not hand-waved): "tracked warning, escalate on 
pattern" requires a **mower standing/reputation mechanism** that does not 
yet exist — persisting per-mower cancel history, defining what constitutes 
a "pattern" (count? rate? window?), and the escalation ladder (warning → 
… → removal?). This is its own future design pass. Decided in principle 
here; mechanism OPEN.

**Case B — Customer cancels after a mower accepted, before work starts — DECIDED (principle)**

Mirror of Case A's fairness structure.

- There is a **free grace window** immediately after acceptance during 
  which customer cancellation is fully consequence-free (mis-tap, instant 
  change of mind, before the mower has materially acted).
- After the grace window, the mower is **owed compensation in principle** 
  for a good-faith commitment broken by the customer.

Named dependencies (open, not hand-waved):
- Compensation **mechanism** (how much, funded from where — customer 
  cancellation fee? MOWR absorbs? from held funds? — and when) is a money 
  flow GATED on the §5 Stripe-investigation payment model. Principle 
  decided; mechanism DO-NOT-BUILD until §5 resolved.
- Grace-window **duration** is an undefined parameter. Its end condition 
  is also undefined: a fixed duration (e.g. 60s / 5 min) OR an event such 
  as "mower marks en route" — but "en route" is a mower-side state that 
  does not exist in the spec yet. OPEN; do not assume silently.

**Case C — Customer cancels while job still broadcasting (no mower yet) — DECIDED**

Fully clean: instant withdrawal, no friction, no penalty, **no tracking**. 
No mower has committed, so there is no harm to anyone.

Conscious trade recorded: there is deliberately **NO customer 
standing/tracking mechanism** implied here. The minor abuse vector 
(repeat book-then-bail pre-acceptance, e.g. price probing) is knowingly 
accepted as low-risk in exchange for not building customer-side tracking 
surface. This is a deliberate choice, not an oversight.

Money tendril: if the resolved §5 model secures funds before broadcast, 
even this clean cancel implies a funds-unwind. Behaviour decided; any 
money unwind deferred to §5.

**Case D — Admin force-cancel — BOUNDED, largely DEFERRED**

Exists as a defined override, distinct from the party-driven cancels.

- Can fire from ANY job state (broadcasting, accepted, in-progress).
- Always carries a recorded reason/category: safety / fraud / error / 
  legal-dispute.
- Consequences inherit from the nearest normal cancel case, EXCEPT where 
  the override reason changes who is at fault.

OPEN — fault-asymmetry (deliberately undecided, recorded explicitly): 
whether an admin force-cancel caused by one party's fault must avoid 
penalising the other party (e.g. cancel for customer fraud must not strike 
the mower's standing/payment) is DELIBERATELY left open, to be decided 
together with the mower standing system. Risk acknowledged: an unpinned 
principle can be built wrong in detail before it is revisited. Therefore: 
the mower standing system MUST NOT be designed/built in a way that 
forecloses adopting a fault-asymmetry rule later. Do-not-foreclose marker, 
not silence.

Deferred (with reasons): money unwind → §5 (Stripe-gated); 
fault-asymmetry / standing exceptions → mower standing design pass; admin 
tooling (who can trigger, audit log, notify behaviour) → Phase-2 backend. 
Bounded here; not fully designed, by intent.

**Summary of named open dependencies (so none are hand-waved)**

1. Mower standing/reputation mechanism — OPEN, own design pass (Cases A, D).
2. Cancellation compensation money mechanism — OPEN, gated on §5 (Case B).
3. Grace-window duration + end-condition (possible "en route" mower 
   state) — OPEN (Case B).
4. Admin-cancel fault-asymmetry principle — DELIBERATELY OPEN, decide with 
   standing system, do-not-foreclose (Case D).
5. Deliberate NON-existence of a customer standing mechanism — recorded 
   conscious trade (Case C).

### §3b — Broadcast window & daylight feasibility

> Part of Marketplace model §3 (job lifecycle). Records one DECIDED
> principle, two precisely-bounded OPEN items, and preserved hard facts
> so nothing from the design discussion is lost. Honest state: most of
> this is deliberately open — recorded as open, not vaguely deferred.

**Broadcast window — PRINCIPLE decided, length OPEN**

DECIDED (principle, stable):

- A broadcast job stays open for an EXTENDED period for **access-provided** 
  jobs — deliberately not a tight few-minute window. The model favours 
  eventually filling the job over failing it fast.
- **Refined by §5a**: this "extended window" principle applies to 
  access-provided jobs only. Customer-present jobs require a tighter, 
  more predictable commitment; their window behaviour is OPEN. See §5a 
  (Access fork & payment window) for the full branch definition.
- The customer is told this UPFRONT, with expectation-setting language 
  (e.g. "this may take a while — we appreciate your patience"). The wait 
  is communicated, never a silent unexplained delay.

OPEN (precisely bounded — do NOT assume values):

- The actual broadcast-window LENGTH for access-provided jobs is undecided.
- The broadcast-window behaviour for customer-present jobs is separately 
  OPEN — see §5a.
- The auth-window coupling candidate (broadcast window bounded by 
  card-auth hold duration) has been SUPERSEDED: extended-auth is ruled 
  out (§5a). Window length for the access-provided branch is now an 
  independent open decision, constrained to the standard auth window 
  (~7 days). Customer-present window is a separate open.

**Daylight feasibility — OPEN (needs design), with preserved hard facts**

This is NOT yet designed and is recorded as open. Two concrete inputs are 
preserved so they are not lost when it IS designed:

- HARD FACT — earliest start: a mower cannot start before **08:00** due 
  to noise regulations. This is a regulatory constraint, not a tunable. 
  Any daylight/scheduling design MUST honour an 08:00 earliest start.
- Intended late bound: completion bounded by **sunset** (sunrise/sunset 
  are computable from date + location — astronomy, not data that requires 
  launch). Recorded as the intended approach, design pending.

OPEN / needs design (do NOT implement):

- The full feasibility rule: "job must fit within remaining daylight 
  given its estimated duration, between 08:00 and sunset."
- Job-duration estimate (e.g. "medium-height 100 sqm ≈ 20 min") is a 
  HEURISTIC, not a validated formula. Recorded as an intended approach to 
  be CALIBRATED against real job data — not a solved constant. Real mow 
  times vary by mower, equipment, terrain, obstacles.
- Dependency link: the job-duration estimate likely also feeds the pricing 
  formula (price partly a function of estimated time). The pricing formula 
  is itself OPEN. These two are linked and must be resolved consistently — 
  do not solve job-duration in isolation in a way that contradicts the 
  eventual pricing model.

**Distinctions deliberately preserved (so the spec does not conflate them)**

Three different things, kept separate by intent:

1. Broadcast-window length = how long we wait for a mower to ACCEPT. 
   About mower response latency. (Principle decided, length open.)
2. Daylight feasibility = whether a job CAN be done given 08:00 / sunset 
   / estimated duration. About physical/regulatory possibility. (Open, 
   needs design.)
3. Job-duration estimate = how long the mowing WORK takes. A calibratable 
   heuristic, linked to pricing. (Open.)

Conflating these (e.g. using job size to set the broadcast window) is a 
known error and is explicitly disallowed.

**Status**

§3's job state machine is now specified IN PRINCIPLE. Remaining open 
items here are deliberately open, not vaguely deferred. The Stripe 
investigation is complete (§5a): extended-auth is ruled out, standard 
window decided, access-provided branch open. Broadcast-window length 
for the access-provided branch is an independent open; customer-present 
window is a separate open.

### §4 — Concurrent acceptance (technical constraint)
Multiple mowers may tap Accept simultaneously. The assignment MUST be 
server-authoritative: a single atomic DB operation (e.g. conditional 
UPDATE with `WHERE status = 'broadcast'`) ensures exactly one mower is 
assigned. First write wins; all others receive a rejection response and 
the job disappears from their queue. Client-side "first tap" is 
insufficient — there will be races.

### §5 — Stripe Connect (decided principles; mechanism partially resolved)

**Decided**
- Payments go through Stripe Connect so platform commission is split 
  server-side at charge time, not via manual bank transfers.
- Mowers are Stripe Express accounts (lighter onboarding than Custom).
- The platform takes a commission percentage (exact % undecided — see 
  OPEN QUESTIONS).
- No manual payroll; Stripe handles mower payouts.
- Payment operates within the **standard auth window** (~7 days; ~5 for 
  Visa MIT). Extended authorizations deliberately ruled out — see §5a.

**RETIRED — extended-auth as a mechanism candidate**
The four-candidate list previously held here is superseded. Extended-auth 
(~30 days via MCC eligibility / IC+ pricing) is deliberately abandoned. 
Authorise-then-capture within the standard window is the decided approach 
for customer-present jobs. See §5a for the full Stripe research findings 
and the access-provided branch open item.

**OPEN — access-provided branch only (do NOT implement until resolved)**
The access-provided/long-window branch payment resolution is open — three 
candidate options (product constraint / capture-early-then-refund / not 
offered at launch). See §5a. MUST be resolved before step 12 and the 
Connect integration are built for that branch.

**Hard invariant (non-conditional)**
Capture MUST occur before the auth `capture_before` expiry. Stripe's 
auto-capture ~6h-before-expiry backstop MUST be used. A defined fallback 
for jobs that cannot complete within the window is a requirement — its 
specifics are OPEN (interacts with no-acceptance / cancellation models).

### §5a — Access fork & payment window

> Consolidates decisions relating to the booking flow (step 8 access,
> step 10 timing), §3b (broadcast window), and §5 (payment mechanism).
> DECIDED items are stable. OPEN items carry do-not-build markers.
> Records an honest consequence, not just a decision.

**Access fork — DECIDED (keystone)**

A MOWR job is one of two kinds, indicated by the customer per booking:

- **Access-provided**: gate left open / open frontage. The customer need 
  NOT be present. Tolerates a longer fill/acceptance window.
- **Customer-present**: the customer must be there to allow access. 
  Inherently short-horizon — the customer will not hold themselves 
  available across a multi-day acceptance window.

Consistent with the existing (built, verified) booking flow: step 8 
(access) and step 10 ("can they leave access if not home") already 
implied this fork. This decision makes it explicit; it does not 
contradict Phase 1 work.

**Branch consequences — job-type-dependent (record as branched, not uniform)**

The fork splits three things that were previously treated as uniform:

1. Scheduling / acceptance window branches by type. The extended-period 
   broadcast window applies to **access-provided** jobs. 
   **Customer-present** jobs need a tighter, more predictable commitment 
   — they cannot tolerate a multi-day acceptance window. The §3b 
   "extended window" principle is hereby refined to "extended for 
   access-provided; tighter for customer-present." Customer-present 
   window behaviour is OPEN.
2. Payment horizon branches by type (see next section).
3. Arrival-window expectation branches by type: customer-present jobs 
   likely require an arrival-window commitment; access-provided do not. 
   Arrival windows remain a Phase-2 fulfilment-dependent capability 
   (depends on mower side + routing, both unbuilt). Recorded as desirable 
   future capability, NOT designed now.

**Stripe auth research findings (recorded)**

- Standard online card authorization hold: ~7 days typical; Visa 
  merchant-initiated is ~5 days. Per-transaction, confirmed via Stripe's 
  `capture_before` field.
- Extended authorizations exist (up to ~30 days) BUT depend on merchant 
  category code eligibility and typically IC+ pricing — an account 
  qualification path.
- If an auth expires before capture: funds released, PaymentIntent 
  cancelled, customer never charged. No protection for a job "in motion."
- No "refresh the clock" on an existing auth: a new PaymentIntent / 
  fresh authorization is required, meaning re-contacting the customer 
  with decline risk.
- Backstop available: Stripe can auto-capture ~6h before expiry.

**Payment mechanism — DECIDED to keep simple (extended-auth ruled OUT)**

MOWR will NOT depend on extended authorizations. The MCC-eligibility / 
IC+-pricing qualification path is deliberately avoided as unwanted 
complexity. Payment operates within the **standard auth window** (~7 
days; ~5 for Visa MIT).

Honest consequence (recorded, not hidden): simplicity on the Stripe side 
relocates complexity into the model. The standard window comfortably 
covers **customer-present** jobs (short-horizon by nature — 
authorise-at-booking, capture near completion fits in ~7 days). It does 
NOT automatically cover **access-provided, days-out** jobs.

**OPEN — access-provided branch only (do NOT build until decided)**

The access-provided/long-window branch must be resolved by one of:
- (a) a product constraint — such jobs must be filled & completed within 
  the standard window or the booking lapses;
- (b) capture-early-then-refund-on-failure for that branch (reintroduces 
  refund operations — previously steered away from);
- (c) that branch not offered at launch.

This is now contained to the access-provided branch, not the whole 
product — the fork narrowed it. DO-NOT-BUILD until one option chosen.

**Hard architectural invariant — NON-conditional**

Regardless of branch or mechanism: capture MUST occur before the auth 
`capture_before` expiry. Use Stripe's auto-capture ~6h-before-expiry 
backstop. A defined fallback MUST exist for any job that cannot complete 
within the window (its specifics are OPEN and interact with the 
no-acceptance/cancellation models — but that the fallback must exist and 
be defined is a requirement now, not optional).

**Status**

Remaining payment unknowns are factual, narrowed to one branch:
- Standard-window adequacy is confirmed for customer-present jobs.
- Only the access-provided/long-window branch needs a chosen resolution 
  — a design decision, not a Stripe-eligibility one.
- Extended-auth path deliberately abandoned; no Stripe MCC/IC+ 
  negotiation required.

### §6 — Mower side (largely unspecified)
The mower app surface is Phase 4. What is decided:
- Mowers see broadcast jobs within a configurable radius.
- Accept button triggers the atomic DB claim.
- Job detail includes: address, lawn areas, grass height, access notes, 
  condition photos.
- Mower status machine: applied → pending → approved → active | suspended.

What is NOT yet decided: scheduling UI, job history, earnings dashboard, 
comms model.

### §7 — Scope & sequencing note
The marketplace mechanics (broadcast, atomic accept, Stripe Connect) are 
Phase 3–4. Phase 1 (current) is UI-only mock data. Phase 2 is 
schema + auth. Nothing in this section should be built before its phase.

OPEN items in this section MUST NOT be implemented until resolved — 
several are load-bearing, not edge cases. In particular: the payment 
mechanism (§5/§5a) and the Connect integration MUST NOT be built until 
the access-provided branch resolution and clawback collision (§8) are 
both resolved. Customer-present jobs are payment-mechanically unblocked 
in principle (standard-window decided); access-provided branch is not.

### §8 — Completion & payment model

**Completion model — DECIDED**

A job cannot move to `completed` unless the mower has uploaded BOTH a 
before photo and an after photo. Photos are a hard gate on the 
`in_progress → completed` transition, not optional.
These before/after photos become part of the job record and are the 
evidence of record for whether the job was done.
Concrete mower-side requirement: the mower app MUST capture before and 
after photos; completion is impossible without them.

**Payment release — DECIDED**

On photo upload (completion), the mower's payment releases 
automatically. There is NO per-job review gate before release.
Photos are evidence-on-file: reviewed only IF the customer complains, 
not on every job. Deliberate — a universal review gate does not scale 
and would strand mower payouts.
Mower is paid out on completion (consistent with the payout-on-
completion principle in the marketplace section §5).
The customer has NO time-limited pressure window forcing them to act to 
release payment. Release does not depend on customer action.

**RETIRED decision (superseded — must not resurface)**
An earlier design answer ("mower marks done, auto-confirms if customer 
doesn't dispute in X time") is SUPERSEDED by the photo-evidenced model 
above and is retired. There is no customer dispute countdown. Completion 
is proven by before/after photos, not by customer responsiveness or a 
timer. Do not reintroduce a dispute-window mechanic.

**OPEN — clawback collision (deferred by project owner; do NOT build)**
These three, together, form an unbounded mower-trust hole and are NOT YET 
resolved:

1. Payment releases automatically on photo upload.
2. The customer has no time limit to raise a complaint.
3. (Earlier stated intent) money is released then reversible — "clawed 
   back if later shown not done".

Items 1 and 2 are decided. Item 3, combined with 1 and 2, means a mower 
could be paid, spend the money, and face an open-ended reversal of earned 
income — the fastest known way to destroy marketplace supply-side trust.
Definition of done (must be resolved before the payout/clawback system 
is built): choose the mechanism that breaks the collision — e.g. (a) 
bound the clawback window while letting complaints remain untimed, with 
MOWR absorbing late complaints; (b) a short hold before final release, no 
clawback; (c) clawback only against future earnings, never already-paid.
Until chosen, the payout reversal/clawback path MUST NOT be built.

**OPEN — payment mechanism (gated on Stripe investigation)**
The actual money mechanism (hold/auth/capture/Connect specifics) remains 
open pending the project owner's Stripe investigation, per marketplace 
section §5. The principles above are stable; the mechanism is not.

**Unscoped Phase-2 idea (recorded, NOT decided, does NOT change anything)**
AI before/after photo comparison. Recorded as a candidate only.

NOT a decision. Does NOT alter the DECIDED ungated automatic-release 
model above. Specifically, this is NOT to be implemented as an 
AI-gates-payment mechanism (that would reverse a decided item).
If ever pursued, the safe framing is assistive-only: AI flags suspect 
jobs for human review, never automatically withholds a mower's payment. 
(Note: "flag for human review" implies a staffed review role at scale — 
to be accounted for if pursued, not hand-waved.)
Deep Phase-2: depends on the mower app, photo upload, the payout system, 
and an AI integration — none of which exist. Sits on top of two 
unresolved load-bearing items (clawback collision, Stripe mechanism). 
Status: parked. No design or build until the above opens are resolved 
and it is explicitly scoped as its own decision.

### OPEN QUESTIONS — marketplace model (do NOT implement until decided)
- **Pricing formula**: inputs to the formula (area? perimeter? grass 
  height? distance? time-of-day?) and the formula itself are undecided. 
  Step 11 (pricing display) cannot be built until resolved. Constraint: 
  Phase-1 perimeter is manually entered and low-reliability (customer 
  intuition for linear edge metres is poor); any formula using perimeter 
  must treat Phase-1 values cautiously. Map-derived perimeter (Method 2, 
  deferred) would be reliable — formula design must account for both.
- **Availability granularity**: time slots? Day-level on/off? Shift-based? 
  Undecided.
- **Mower eligibility for broadcast**: radius only, or also specialisms / 
  equipment / ratings threshold? Undecided.
- **Payment mechanism, clawback & cancellation money flows**: standard-window 
  decided, extended-auth abandoned (see §5/§5a). Customer-present branch 
  unblocked in principle. Access-provided branch OPEN — three candidates, 
  DO-NOT-BUILD (see §5a). Clawback collision OPEN (see §8). Cancellation 
  money flows OPEN, gated on §5a resolution (see §3a). MUST NOT build 
  payout/clawback/cancellation-compensation paths until §8 clawback 
  collision and §5a access-provided branch are both resolved.
- **Commission %**: undecided.
- **Broadcast window**: principle decided for access-provided jobs 
  (extended window, customer informed upfront) — see §3b, refined by 
  §5a. Access-provided window length OPEN (independent, not auth-gated — 
  extended-auth ruled out). Customer-present window separately OPEN.
- **Cancellation model**: principles decided for all four cases — see §3a. 
  Open items: mower standing mechanism (Cases A, D); grace-window duration 
  + end-condition (Case B); compensation mechanism gated on §5 (Case B); 
  admin fault-asymmetry rule, do-not-foreclose (Case D).

## Booking Flow (Customer)

### Auth model — deferred (guest-to-account)
- A guest can complete the entire booking without an account.
- The account is created at the payment step: tapping the payment button 
  takes the user to a create-card page; the payment method is saved on the 
  newly created account.
- A logged-in returning customer instead starts at a saved-properties list.
- Auth is a gate around the booking flow, not a step inside BookingShell. 
  The booking draft must survive account creation at the payment step.

### Properties are first-class
- A customer can have multiple properties. property_id must exist in the 
  data model and on the booking draft from day one.
- Every lawn area is permanent to its property and carries a photo.
- A booking references a SUBSET of a property's saved lawn areas (the draft 
  holds selected lawn ids, not flat lawn fields).
- Selecting a saved property with existing lawns lets a returning customer 
  skip lawn creation and go straight to lawn selection.

### Two entry paths, converging
Returning customer (logged in): saved-properties list -> pick a property 
(or "Add a new property") -> lawn selection screen -> joins main flow at 
grass height.
Guest / "Add a new property": address entry -> confirm on map -> 
lawn-creation loop (name + enter measurements -> "another?") -> joins 
main flow at grass height. (Phase 1: manual measurement. Phase 2: 
map-boundary draw replaces manual entry — see Lawn-area creation & 
measurement subsection.)
Both paths converge at grass height; from there the flow is linear.

### Full step list (real flow)
1. (Returning only) Saved-properties list
2. Address of property to be serviced
3. Confirm address on a map
4. Create lawn area — name it + enter area (sqm) + perimeter manually 
   (Phase 1: manual entry; map-boundary draw deferred to Phase 2 — see 
   Lawn-area creation & measurement subsection)
5. (Merged into step 4 in Phase 1; retained as a distinct step for Phase 2 
   map-draw flow)
6. "Another lawn area?" — if yes, loop to step 4
7. Current grass height — low / medium / overgrown (with example images)
8. Access to the lawn + optional free-text access notes
9. Photos of each lawn area (optional) — SEE OPEN QUESTIONS
10. When they want it done (e.g. ASAP) + can they leave access if not home
11. Review and price
12. Payment (account created here for guests; card saved)
13. All set — awaiting a mower to accept
Steps 4–6 are a repeating sub-flow, not three linear screens.

### Saved-properties screen (returning-customer entry)
First screen on the returning-customer path. Precedes lawn selection.
- Shown only when a logged-in customer has one or more saved properties.
- Lists saved properties as cards. Each card shows: the property address; 
  a lawn count as text (e.g. "3 lawns"). No thumbnail for now.
- Tapping a property writes its property_id into BookingDraft and advances 
  to the lawn selection screen (which then shows that property's lawns).
- "Add a new property" routes into the address-entry flow (same flow a 
  guest uses).
- Select-or-add only. No edit/delete of properties here; property 
  management is a separate later surface, out of scope for the booking flow.
- If the customer has zero saved properties, this screen is not shown; they 
  go straight to add-property (address entry). See OPEN QUESTION.

### OPEN QUESTION — do NOT implement until decided
- Guest first booking auto-save as property? When a guest completes a 
  booking and an account is created at the payment step, it is undecided 
  whether that booking's address + lawn areas are auto-saved as the 
  customer's first property. The "skip to add-property when zero 
  properties" behaviour is correct as specified but its real-world impact 
  depends on this. Resolve before the payment step (step 12) is built.

### Lawn selection screen (returning-property path only)
- Shown only when a returning customer picks a saved property.
- Property's saved lawn areas shown as cards: photo, name, area, 
  selected/unselected state. Tapping toggles inclusion. Default: all selected.
- "Add another lawn area" routes into lawn-creation (steps 4–5) and returns 
  with the new lawn added, saved permanently to the property.
- Persistent bottom bar: "X of Y selected"; Continue disabled at zero.
- Selection state lives in BookingDraft (Riverpod), not local widget state.

### Lawn-area creation & measurement (steps 4–6)

> Booking-flow addition (per lawn area, sits with the lawn-area steps).
> Resolves a gap: how a lawn's size/perimeter is captured. Phase 1 scope
> is deliberately narrow; advanced methods recorded as future with their
> payment ripple explicitly walled off from Phase 1.

**Phase 1 — Manual entry (DECIDED, build now)**

Per lawn area, the customer manually enters:

- **Area** in sqm, with an optional, unobtrusive "help me estimate" 
  hint (e.g. common-size reference / paces ready-reckoner). Optional — 
  does not burden customers who already know. A sqm/sq ft unit toggle is 
  acceptable.
- **Perimeter**, manually entered.

Single values, known at booking. No on-site revision in Phase 1. This 
composes cleanly with the existing booking flow and the §5/§5a payment 
model (amount known at booking — the premise that model depends on).

Recorded limitation (not a blocker): manually-entered perimeter is 
low-reliability data — customers have poor intuition for linear edge 
metres. Capture it, but flag it: the eventual (OPEN) pricing formula must 
treat a manual perimeter cautiously, and as less trustworthy than a 
map-derived perimeter. Same shape as the grass-height-default constraint.

**Recorded as FUTURE (do NOT build in Phase 1)**

Method 2 — Map-boundary draw
Customer draws a polygon; area + perimeter derived (accurate, unlike 
manual). Known-cost: substantially built before in this project 
(Mapbox / Turf.js lawn-area work). Deferred, not researched-anew. 
Perimeter becomes meaningful here (derived, not guessed).

Method 3 — Auto-estimate from property data
System derives approximate green space from property data; mower 
establishes the true boundary on site. Phase-2 research-grade 
sub-project, NOT Phase-1 buildable. Hard problem: property/plot data 
gives the plot, not the mowable lawn (excludes house, drive, patio, 
beds). Prior exploration exists in project history (HM Land Registry 
INSPIRE polygons, OSM Overpass) — reference, not a solved approach.

Walled-off payment ripple (attached to Method 3, NOT Phase 1)
Method 3 implies a TWO-STAGE boundary: approximate at booking → mower 
sets true boundary on site → price may change post-booking. This 
REOPENS the §5/§5a payment model (which depends on amount-known-at-
booking). If/when Method 3 is built, the on-site price-revision 
mechanism MUST be decided then — candidates already identified:
(1) down-only / within pre-authorised buffer (keeps payment model 
intact); (2) up-revision + re-charge + customer re-consent (reintroduces 
re-auth fragility the project ruled out); (3) authorise-with-headroom-
buffer (customer sees larger hold than quote — trust cost);
(4) leave open. DO-NOT-BUILD Method 3 until this is chosen. Phase 1 is 
unaffected because manual entry has no on-site revision.

**Status**

Phase 1 measurement = manual area + perimeter + optional estimate hint. 
Decided, buildable, composes with payment model. Methods 2 and 3 and the 
entire price-revision problem are deferred and explicitly cannot leak 
into Phase 1. Perimeter reliability flagged as a constraint on the still-
OPEN pricing formula.

### Grass-height screen (step 7 — convergence point)
Reached by both entry paths: returning-customer (via property -> lawn 
selection) and guest (via lawn creation). From here the flow is linear.
- Grass height is captured per selected lawn area, not once per booking. 
  Consistent with all other lawn attributes being per-lawn.
- One adaptive screen: a vertical list of the booking's selected lawn 
  areas. Each row shows the lawn name and a three-option control: 
  Low / Medium / High, preset to Medium.
- The customer adjusts only exceptions; untouched lawns stay Medium.
- Example images (low/medium/high reference) shown ONCE as a shared 
  reference the customer can open — NOT repeated per lawn row. Placeholders 
  until real images supplied.
- Every lawn defaults to Medium, so there is no mandatory-selection gate: 
  Continue is always enabled.
- Per-lawn grass height written into BookingDraft keyed by lawn id; must 
  persist across back-navigation (same idempotent pattern as lawn 
  selection).

### CONSTRAINT on the pricing/review step (step 11) — must honour
The Medium default means a customer can reach pricing with a lawn still set 
to Medium that they never actively confirmed but which is in reality a much 
bigger, overgrown job (now labelled "High" in the UI). If pricing is keyed 
off grass height, this causes the customer to underpay and the mower to 
face a larger job than was sold. The pricing/review step MUST surface 
per-lawn grass height prominently for explicit confirmation before payment; 
a never-adjusted default must not be treated as silently confirmed.

### Lawn access screen (step 8)
Single screen. Access is captured per property, not per lawn area and not 
loosely on the booking — one access answer covers the whole visit.
- Multi-select preset options, any combination: Front (open access); Side 
  gate; Locked gate / needs code; Through garage; Other.
- A free-text notes field for specifics presets cannot capture (gate 
  codes, dog, parking).
- Notes are conditionally required: normally optional; REQUIRED if "Locked 
  gate / needs code" OR "Other" is among the selected presets.
- Continue is gated on that rule and must re-evaluate dynamically as 
  presets are toggled:
  - Only non-gating presets selected -> notes optional -> Continue enabled.
  - Gating preset (Locked/Other) added -> notes required -> Continue 
    DISABLES until notes non-empty -> re-enables once notes filled.
  - Gating preset later deselected -> notes optional again -> Continue 
    re-enables even if notes cleared.
  - Must work in BOTH directions; enabling on required-and-filled but 
    failing to re-enable when the requirement is removed is disallowed.
- Access data attaches to the property (to enable later prefill for 
  returning customers), not to the booking. Persists across 
  back-navigation (idempotent pattern).
- Reuse established card/control styling and theme tokens.

### Condition-photos screen (step 9)
Optional. The customer may add current-condition photos showing what each 
lawn looks like right now, on top of (NOT replacing) the permanent 
reference photo each lawn area already carries.
- Per selected lawn area: a card with the lawn name, current-condition 
  photo thumbnails, and an "add photo" affordance.
- Multiple condition photos per lawn allowed. Each thumbnail has an 
  individual remove control. Small gallery-management UI (add/view/remove 
  individual), not single add-or-replace.
- Adding a photo offers both camera and gallery (customer picks either).
- Entirely optional: Continue always enabled; customer can skip the whole 
  screen. No gate.
- Stored in BookingDraft keyed by lawn id (list of photo references per 
  lawn). Persists across back-navigation; default empty.
- Reuse established card/control styling and theme tokens.

Phase-1 storage reality: no backend in Phase 1. A condition photo is held 
only as a local device file reference in BookingDraft — not uploaded, not 
persisted server-side, will not survive reinstall. Acceptable for Phase 1; 
must not be mistaken for real persistence.

Phase-2 deferred (do NOT implement now): real upload to Supabase storage; 
image compression/resizing; tying photos to the persisted job for the 
mower app.

Dependency & native config: first screen needing a third-party 
camera/gallery package plus Android manifest + iOS Info.plist permission 
entries. Missing permission config compiles clean but crashes at runtime 
on first invocation; runtime emulator testing of camera AND gallery is 
required, static analysis is not sufficient.

### OPEN QUESTIONS — do NOT implement until decided
- Lawn measurement Methods 2 & 3 deferred (do NOT build in Phase 1): 
  Method 2 (map-boundary draw, Mapbox/Turf.js) and Method 3 
  (auto-estimate from property data) are explicitly not Phase 1. Method 3 
  additionally REOPENS §5/§5a — on-site price-revision implies 
  amount-not-known-at-booking. DO-NOT-BUILD Method 3 until its 
  price-revision mechanism is chosen. See Lawn-area creation & 
  measurement subsection for the four candidates.
- Pricing model (step 11): formula undecided. Step 11 cannot be built yet.
- Payment: payout model decided (see §8); standard-window decided, 
  extended-auth ruled out (see §5/§5a); access-provided branch OPEN 
  (see §5a); clawback collision OPEN (see §8). Steps 12/13 MUST NOT be 
  built until §5a access-provided branch and §8 clawback collision are 
  both resolved.
- Mower assignment: decided — see Marketplace model (broadcast, first-to-accept). Sub-questions (availability, eligibility, broadcast window) tracked there.
- Orphaned condition photos at confirmation: because photos are retained 
  when a lawn is deselected, the booking may carry condition photos for 
  lawns not in the final booking. At confirmation/submission (step 12/13) 
  and Phase-2 upload, these must be reconciled — undecided whether to 
  discard them, retain-but-flag, or simply exclude them from what the 
  mower sees. MUST be resolved before step 12/13 / Phase-2 photo upload 
  is built.

### Resolved decisions (booking flow)
- Lawn measurement (Phase 1, steps 4–6): manual area (sqm) + perimeter + 
  optional estimate hint. Single values known at booking; no on-site 
  revision. Composes with §5/§5a payment model. Manual perimeter is 
  low-reliability — pricing formula must treat it cautiously (same shape 
  as grass-height-default constraint). Method 2 (map-boundary draw) and 
  Method 3 (auto-estimate) deferred; see booking-flow OPEN QUESTIONS.
- Access fork (step 8 / step 10): jobs are access-provided (customer 
  not required; tolerates longer acceptance window) or customer-present 
  (customer must be there; short-horizon). Step 10 "can they leave 
  access if not home" captures this. Decision made explicit in 
  Marketplace model §5a; consistent with built Phase 1 flow.
- Step 9 condition photos: optional, multiple current-condition photos per 
  selected lawn area, on top of (not replacing) the permanent per-lawn 
  reference photo. Stored in BookingDraft keyed by lawn id.
- Condition-photo retention: condition photos persist on a lawn even if 
  that lawn is later deselected from the booking. They are intentionally 
  NOT cleared on deselection, to avoid losing customer-entered work.
- Lawn access granularity (step 8): per property, not per lawn area and 
  not per booking — one access answer covers the whole visit. Enables 
  prefill for returning customers in Phase 2.
- Grass-height granularity (step 7): per selected lawn area, not per 
  booking. Three options: Low / Medium / High; defaults to Medium.

## 6. Conventions for Claude Code

- Feature-first folder structure (`lib/features/booking/`, `lib/features/auth/`,
  etc.), shared `lib/core/` for theme, routing, supabase client, models.
- Repository pattern: UI → Riverpod providers → repositories → Supabase. No
  Supabase calls directly in widgets.
- The attached demo file is a **design reference only** — match its look (the
  Material 3 theme, seed colour `0xFF2E7D32`, background `0xFFF7F8F5`, ~18–24px
  radii, the component styles). Do **not** keep its structure: it is a single
  stateful widget with hardcoded text and no real navigation/state/data.
- Models are immutable with JSON (de)serialization.
- Every Supabase table has RLS policies; never ship a table without them.

## 7. Key constraints captured (do not lose these)

- **iOS without a Mac.** No Mac owned; user has a personal iPhone. iOS binaries
  are built in the cloud via Codemagic, then installed on the iPhone for real
  testing. Day-to-day development/testing is on the Android emulator. iOS is
  validated regularly via Codemagic, not only at the end.
- **Apple Developer Program ($99/yr)** is required before the app can be
  installed on the physical iPhone or submitted. Not needed yet; needed by
  Phase 3–4.
- **Payments use Stripe directly, not in-app purchase.** Lawn mowing is a
  real-world physical service, which is exempt from Apple/Google IAP rules.
  This keeps ~97% per booking vs ~70%.
- **Dev environment is native Windows** (Claude Code, Flutter, VS Code all on
  Windows — no WSL/Ubuntu in the loop).

## 8. Out of scope for v1 (explicitly deferred)

- In-app mower↔customer chat/messaging.
- Recurring/subscription bookings (demo shows "Regular" — defer the logic).
- Mower payouts/payroll automation (handle manually early).

(Ratings and push notifications were moved INTO v1 — see Phase 4.)

## OPEN QUESTION — mower offline access (deferred to Phase 2 design)
- Mowers work in the field with poor/no signal and need access to accepted 
  jobs (address, lawn details, access notes, photos) while offline. Flagged 
  as a genuine requirement, NOT a decided feature.
- Scope undecided: (a) read-only cached job data for the mower role 
  (lighter, likely sufficient); (b) full offline writes with sync 
  (significant: conflict handling, sync queue, deferred uploads).
- Customers and admin assumed online-only unless decided otherwise.
- Shapes the Phase 2 schema and client data layer; resolve during Phase 2 
  backend design, not after.
