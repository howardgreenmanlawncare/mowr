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

### §4 — Concurrent acceptance (technical constraint)
Multiple mowers may tap Accept simultaneously. The assignment MUST be 
server-authoritative: a single atomic DB operation (e.g. conditional 
UPDATE with `WHERE status = 'broadcast'`) ensures exactly one mower is 
assigned. First write wins; all others receive a rejection response and 
the job disappears from their queue. Client-side "first tap" is 
insufficient — there will be races.

### §5 — Stripe Connect (decided principles; mechanism open)

**Decided**
- Payments go through Stripe Connect so platform commission is split 
  server-side at charge time, not via manual bank transfers.
- Mowers are Stripe Express accounts (lighter onboarding than Custom).
- The platform takes a commission percentage (exact % undecided — see 
  OPEN QUESTIONS).
- No manual payroll; Stripe handles mower payouts.

**OPEN — payment mechanism (do NOT implement until resolved)**
The auth-hold problem: payment is taken at booking (step 12), but the 
mower hasn't accepted yet (step 13). Four candidate directions:

1. **Capture-upfront** — charge immediately at booking; refund if no 
   mower accepts. Simple but refunds have latency / card issuer friction.
2. **Authorise-then-capture** — auth hold at booking; capture when mower 
   accepts. Auth holds expire (~7 days); risky if acceptance is slow.
3. **Charge + escrow** — charge immediately; hold funds in Stripe balance 
   until acceptance/completion. Avoids refunds but adds Stripe Treasury 
   complexity.
4. **Charge at acceptance** — save card at booking; charge only when a 
   mower accepts. Customer could dispute "silent" charge after delay.

This is a load-bearing architectural decision. MUST be resolved before 
step 12 and the Connect integration are built.

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
mechanism (§5) and the Connect integration MUST NOT be built until the 
auth-hold trade-off is resolved.

### OPEN QUESTIONS — marketplace model (do NOT implement until decided)
- **Pricing formula**: inputs to the formula (area? perimeter? grass 
  height? distance? time-of-day?) and the formula itself are undecided. 
  Step 11 (pricing display) cannot be built until resolved.
- **Availability granularity**: time slots? Day-level on/off? Shift-based? 
  Undecided.
- **Mower eligibility for broadcast**: radius only, or also specialisms / 
  equipment / ratings threshold? Undecided.
- **Payment mechanism**: see §5 — four candidates, none chosen yet.
- **Payout timing**: immediate on job completion, batched daily/weekly, or 
  after customer review period? Undecided.
- **Commission %**: undecided.
- **Broadcast window**: how long before a job is re-broadcast or escalated 
  to admin? Undecided.
- **Cancellation policy**: customer cancels after mower accepts — partial 
  refund? Full refund? Mower compensation? Undecided.

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
lawn-creation loop (draw boundary -> name -> "another?") -> joins main 
flow at grass height.
Both paths converge at grass height; from there the flow is linear.

### Full step list (real flow)
1. (Returning only) Saved-properties list
2. Address of property to be serviced
3. Confirm address on a map
4. Create lawn area by drawing a boundary on a map (captures area + perimeter)
5. Name the lawn
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
- Pricing model (step 11): formula undecided. Step 11 cannot be built yet.
- Payment: principles decided, mechanism open pending Stripe investigation — see Marketplace model §5.
- Mower assignment: decided — see Marketplace model (broadcast, first-to-accept). Sub-questions (availability, eligibility, broadcast window) tracked there.
- Orphaned condition photos at confirmation: because photos are retained 
  when a lawn is deselected, the booking may carry condition photos for 
  lawns not in the final booking. At confirmation/submission (step 12/13) 
  and Phase-2 upload, these must be reconciled — undecided whether to 
  discard them, retain-but-flag, or simply exclude them from what the 
  mower sees. MUST be resolved before step 12/13 / Phase-2 photo upload 
  is built.

### Resolved decisions (booking flow)
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
