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

### OPEN QUESTIONS — do NOT implement until decided
- Pricing model (step 11): formula undecided. Step 11 cannot be built yet.
- Step 9 photo: whether a separate booking-time "current condition" photo 
  exists, distinct from the permanent per-lawn photo — undecided.
- Stripe capture timing: payment (step 12) precedes mower acceptance 
  (step 13); authorise-then-capture vs capture-upfront undecided.
- Per-lawn vs per-booking: whether access (8) is per booking or per lawn 
  area is undecided. (Grass height (7) is decided: per lawn area.)
- Mower assignment & scheduling: not decided.

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
