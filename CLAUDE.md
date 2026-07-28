# MOWR — Claude Code guide

Source of truth: `MOWR_PROJECT_SPEC.md`. This file distils the spec into
day-to-day conventions. Update both files together when decisions change.

---

## Current state (handoff, 2026-07-23)

Work is well ahead of the "Phase 0 complete" line in the roadmap table below —
that table is the original plan; this section is where things actually stand.
`flutter analyze` is clean.

**On-device status (2026-07-22):** the guest booking flow was walked end to end
on an Android emulator (Pixel 8, API 37), welcome → review & price. Live
postcode lookup, manual lawn entry, per-lawn grass height, access, edging
toggle and the priced review screen all work and carry state correctly through
`BookingDraft`. Not yet exercised on-device: account creation, the Stripe
payment step, confirmation, and the whole mower app.

**Built so far**
- **Customer booking flow (Phase 1)** — guest property setup: postcode→address
  lookup, confirm-location satellite map, and map-boundary lawn drawing with
  live geodesic area/perimeter (+ manual fallback). Branch
  `feat/property-setup-map-flow`.
- **Mower app** — home dashboard, job lists (Available / Mine / History), job
  detail, and on-site **re-measure + reprice** with tiered payment capture
  (migrations `0006_remeasure.sql`, `0007_remeasure_override.sql`;
  `capture-payment` edge function).
- **Stripe Connect payouts** — mowers onboard an Express account; job completion
  transfers their share. Migration `0008_connect.sql`; edge functions
  `connect-onboard` / `connect-status` / `connect-dashboard` / `connect-return`
  / `connect-balance`. Per-mower commission (`profiles.commission_pct`, default
  15%).
- **Earnings + bottom nav (this session)** — mower bottom nav **Home / Jobs /
  Earnings** (`mower_home_screen.dart`), Available/Mine/History as a
  `SegmentedButton` inside Jobs. New **earnings screen**
  (`mower_earnings_screen.dart`) with Today / 7 days / 30 days / YTD / Custom
  filter chips calling the deployed `mower_earnings(p_from, p_to)` RPC, plus
  **CSV export** of the filtered rows via `share_plus`. The Stripe payout/bank UI
  moved to `mower_payouts_screen.dart` (route `/mower/payouts`). Domain model
  `mower_earnings.dart`; repo method `MowerRepository.earnings()`. New deps:
  `share_plus`, `path_provider`.

- **Customer post-booking surface (2026-07-23)** — `/bookings` list
  (`my_bookings_screen.dart`) and `/bookings/:id` detail
  (`booking_status_screen.dart`), reached from the welcome screen ("Track an
  existing booking") and the confirmation step. The detail screen carries the
  **customer revision-approval UI**: when a mower's on-site re-measure exceeds
  the auto-approve threshold the booking parks on `approval_status='pending'`,
  `capture-payment` refuses to take money, and the customer approves or declines
  here via `respond_to_revision`. Domain model `customer_booking.dart`; read
  methods on `BookingRepository`.
- **Standalone customer sign-in (2026-07-23)** — `AccountStepScreen` now takes a
  `?next=` query param. With it set the screen drops the booking-flow chrome,
  opens in sign-in mode and returns to `next` instead of pushing the payment
  step. Without it, behaviour is unchanged. Before this, the only customer
  sign-in was step 9 of the booking flow and it always continued to payment —
  so a returning customer signing in to track a booking landed on a payment
  screen for a booking they were not making.
- **Recurring bookings + loyalty discounts (2026-07-23)** — full stack:
  - Engine: `discount.dart` (`DiscountRule`, `bestDiscount`, `recurringIncentive`)
    + `PricingEngine` applies the best matching discount for a `DiscountContext`
    (isRecurring, occurrence). Models "recur and your 3rd mow is 20% off". Money
    still flows through the single engine. **9 unit tests** in `test/discount_test.dart`.
  - Booking flow: `RecurrenceInterval` on `BookingDraft`; a "How often?" chooser
    on the schedule step (One-off / Weekly / Every 2 wks / Every 4 wks); the
    review step shows the recurrence, any applied discount, and a loyalty
    incentive ("your 3rd mow is 20% off"). `booking_repository.submit` persists
    `recurrence_interval_days`.
  - Discounts load at startup via `loadDiscountRules` → `discountRulesProvider`
    (best-effort, like pricing).
  - Admin: `admin_discounts_screen.dart` (reached from `/admin` Settings →
    Manage discounts) — create/edit/delete rules.
  - Backend: `0016_recurring_discounts.sql` (**APPLIED 2026-07-24**) adds
    bookings recurrence columns (`series_id`, `occurrence_number`,
    `recurrence_interval_days`, `next_occurrence_date`), the `discount_rules`
    table (anon-readable for pricing) + admin RPCs (`admin_list_discounts` /
    `admin_save_discount` / `admin_delete_discount`), seeded with the "3rd mow
    20% off" example.
  - Occurrence-generator cron `0017_recurrence_generator.sql` (**APPLIED +
    SCHEDULED 2026-07-24**): `generate_recurring_occurrences(p_lead_days)` spawns
    the next occurrence of each active series a couple of days before it's due,
    re-applying the loyalty discount for that occurrence number (base price in
    `bookings.base_amount` so discounts don't compound). Runs daily via pg_cron
    (`cron.job` name `generate-recurring-occurrences`, 06:00). Stops a series
    when its latest occurrence is cancelled. **Verified live 2026-07-24**: a
    weekly series generated occ 2 (full price) then occ 3 at £54.40 = £68 × 0.80
    (20% off), test rows cleaned up. `booking_repository.submit` now also
    persists `base_amount` (needs an app rebuild to ship; degrades to
    total_amount if absent).
- **Notifications — email foundation (2026-07-23)** — the app told nobody
  anything happened; this is the fix. `0018_notifications.sql` (**apply
  pending**) adds a `notifications` queue + a `bookings` trigger that enqueues
  on the events that matter (confirmed, mower assigned, re-measure needs
  approval, completed), and edge function `process-notifications` drains the
  queue via Resend. Decoupled (a slow email can't block a booking). THREE setup
  steps to make it send: set `RESEND_API_KEY` + `NOTIFY_FROM`, deploy the
  function, and schedule the drain (pg_cron + pg_net snippet in the migration).
  Push notifications still not built (needs FCM + Apple Developer acct for iOS).
- **Admin operations dashboard (2026-07-23)** — `admin_shell.dart` gives admin a
  bottom nav (Dashboard / Mowers / Settings); `/admin` now lands here.
  `admin_dashboard_screen.dart` shows revenue, jobs-by-status, mower roster,
  attention items and a next-7-days strip with Today / 7d / 30d filters
  (mirroring mower earnings). Backed by `admin_dashboard(p_from,p_to)` RPC in
  `0015_admin_dashboard.sql` (**not yet applied** — MCP was read-only). Repo:
  `AdminRepository.dashboard`.
- **Demo seed (2026-07-23)** — `supabase/seed_demo.sql` populates properties +
  bookings across statuses clustered near Colchester (available work, a live
  multi-stop day for the route map, completed history for earnings/dashboard),
  and flips the mower `howardmowr@` to approved+onboarded (connect_onboarded is
  faked — demo only). **Not yet run** (MCP read-only). Re-runnable (tags rows
  `access_notes='demo-seed'` and clears prior demo rows first).
- **Auth degrades without Supabase (2026-07-23)** — `AuthRepository` auth-state
  reads (`isSignedIn`, `authStateChanges`) return signed-out instead of throwing
  when `Supabase.instance` isn't initialised, so the customer nav bar renders in
  a widget test (and if init ever fails). Full suite now **22 tests green**.
- **Mower scheduling / route optimiser (2026-07-23)** — in-house, no third-party
  services. `lib/features/mower/domain/schedule.dart` is a pure engine: estimates
  job duration (area/lawns), optimises a mower's day into the least-driving order
  that honours each customer's time window (exact permutation search ≤8 stops,
  nearest-neighbour + 2-opt above that), and `assessInsertion` re-optimises the
  day with a candidate job and reports the impact — new sequence position, new
  finish time, extra driving, or why it won't fit. Wired into the mower's Accept
  flow via `mower_day_fit_sheet.dart` (a confirmation sheet, advisory not a gate).
  **12 unit tests in `test/schedule_test.dart`** (first real coverage in the repo).
  Travel is haversine × road-factor ÷ avg speed — swap `travelMinutes` for
  self-hosted OSRM / a matrix API for real road times; nothing else changes.
  This engine is deliberately the reusable primitive a future **fleet allocator**
  calls per (mower, job) — the "recurring jobs auto-allocated to opted-in mowers,
  most-efficiently" vision is: run `assessInsertion` across mowers, assign best.
  Decision (owner, 2026-07-23): keep routing **in-house** — OR-Tools/OSRM
  self-hosted at the fleet stage, not a route-optimisation SaaS. Built + tested;
  the Accept sheet is unverified on device (needs a mower sign-in).
- **Fleet allocator — engine (2026-07-23)** — `lib/features/mower/domain/fleet.dart`
  is the "night-before auto-allocation" engine: `FleetAllocator.allocate(jobs,
  mowers, day)` assigns a day's jobs across opted-in mowers by running the
  single-mower `SchedulingEngine.assessInsertion` across every mower and giving
  each job to the one it disturbs least (least added driving; ties → earlier
  finish, then emptier day). Greedy, hardest-to-place first, pure/in-house.
  **5 unit tests** in `test/fleet_test.dart` (27 tests total now). Swap the loop
  for OR-Tools when a globally-optimal plan is worth it — nothing above changes.
- **Fleet allocation — OPERATIONAL (2026-07-24)** — `0018_fleet_allocation.sql`
  (**applied + verified live**) wires the allocator up server-side. Adds
  `profiles.auto_allocate` / `work_start` / `work_end`; `allocate_jobs_for(date)`
  is the SQL mirror of `FleetAllocator` (greedy, hardest-first, least-added-
  travel via `_travel_min` haversine, window+day capacity via `_window_cap` /
  `_booking_minutes`); `set_auto_allocate(on)` lets a mower opt in.
  **Nightly pipeline live via pg_cron**: `generate-recurring-occurrences` 06:00
  (spawn tomorrow's occurrences, unassigned) → `allocate-tomorrow` 06:10 (assign
  the unassigned pool to opted-in mowers). Verified live 2026-07-24: 3 clustered
  morning jobs all assigned to the opted-in mower; 2 more that overflowed the
  240-min morning window correctly left unassigned; test rows cleaned up.
  **Bug found + fixed during verification**: the allocator was double-counting
  placed jobs (updated the booking AND held it in the temp table) — now defers
  all DB updates to the end of the run. Per-mower route *sequencing* still
  happens in-app (`schedule.dart`); this only decides WHO gets each job.
  Mower opt-in surfaced via `mower_account.auto_allocate` + an "Auto-plan my
  day" toggle on the mower home (`set_auto_allocate` RPC). `howardmowr@` was
  reset to auto_allocate=false after testing so the demo's Available pool stays.
  STILL TO BUILD: customer ETA surface; swap haversine→OSRM / greedy→OR-Tools at
  scale.
- **Performance-based commission + customer ratings (2026-07-24)** — a mower's
  commission drops as they complete jobs and earn good reviews.
  `0020_commission_tiers.sql` (**apply pending — MCP read-only this session**)
  adds: a **`reviews`** table (customer rates a completed job 1–5 + optional
  note; insert only via `submit_review` SECURITY DEFINER, which enforces
  own+completed+unrated and stamps the mower; owner/mower/admin-read RLS); an
  admin-editable **`commission_tiers`** ladder (name, min_jobs, min_rating,
  min_reviews, commission_pct, active — seeded Bronze/Silver/Gold, anon-readable
  so mowers see progress); and the single source of truth **`mower_commission(id)`**
  = **best (lowest)** of the admin override/default and the lowest qualifying
  tier (owner decision: an override can only ever *help* a mower). Everything
  routes through it — `capture-payment` now calls `mower_commission` (removed the
  static `profiles.commission_pct` read), and `mower_account` returns the earned
  effective rate. **`mower_commission_status()`** returns the mower's stats +
  current tier + the next reduction with per-requirement gaps ("18 jobs to go,
  +0.1★, 9 more reviews"). Admin CRUD RPCs `admin_list/save/delete_commission_tier`.
  Flutter: `CommissionStatus`/`NextTier` domain + `MowerRepository.commissionStatus`;
  a **tier-progress card** on the payouts screen (stats row + "Next: Silver 11%"
  with checklist of what's left); customer **star-rating card** on the booking-
  status screen (`BookingRepository.submitReview`, `CustomerBooking.myRating`
  from an embedded `reviews(rating)`); admin **`AdminCommissionTiersScreen`**
  reached from `/admin/settings`. `flutter analyze` clean. Unverified on device
  (needs the migration applied + a completed job to rate).
- **Address privacy — street hidden until en route (2026-07-26)** — anti-
  circumvention: a mower who accepts a job for tomorrow must NOT get the exact
  address (or they could turn up and do it off-app). `0021_address_privacy.sql`
  (**apply pending**) gates the street line, exact lat/lng, and access notes
  **server-side** in `_job_json` (all job lists) and `job_detail`: withheld
  until `status in ('en_route','arrived','in_progress','completed')` — only the
  **postcode** shows before that. The customer always sees their own property.
  `job_detail` now returns `address_unlocked`; the mower job-detail screen shows
  a "unlocks when you're on your way" lock note + hides "Take me there" until
  unlocked. Enforced in the DB (not just the UI) so the API can't be read around.
- **Branding — real logo + app icon (2026-07-26)** — the MOWR wordmark
  (`assets/brand/mowr_wordmark.png` + 2x/3x) replaces the placeholder mark on the
  welcome header; the square swoosh icon (`assets/brand/mowr_icon.png`, 1254²)
  is set as the Android launcher icon at every mipmap density (generated via
  headless Chrome — no pub-based tooling needed). iOS AppIcon set still TODO
  (Codemagic build). Verified on the emulator.
- **Welcome + sign-in restructure (2026-07-26)** — welcome CTAs are now **Book a
  MOWR** (→ booking flow), **Sign in** (→ new neutral `SignInScreen`), and
  **Become a MOWR** (→ mower sign-up). `SignInScreen` (`/sign-in`) reads the
  account role via `AuthRepository.currentRole()` and routes on success: admin →
  `/admin`, mower → mower home, else → `/bookings` — so a mower signs in normally
  and lands on the mower side. The old welcome links (booked-before / track /
  assistant / are-you-a-mower) were consolidated into these.
- **Auto-accept reliability + cancel tracking (2026-07-26)** — anti-flake /
  anti-off-app. `0023_mower_reliability.sql` + `0024_chat_and_flagging.sql`
  (**both applied + verified**): `bookings.auto_allocated` marks allocator-
  assigned jobs; `mower_job_refusals` logs each dropped job with an `event_type`
  (`refusal` = released before start, `cancel` = bailed after accepting).
  `release_auto_job(booking, reason)` (pre-start "Can't do this one") and
  `mower_cancel_job(booking, reason)` (after accept/en route "Cancel this job")
  return the job to the pool and record the event; ≥3 in 30 days **auto-pauses**
  the mower's auto-accept. A cancel **after going en route** (address was
  unlocked → they may have attended) is the off-app-cash signal: it raises an
  admin alert + support ticket immediately. Surfaced on the mower job-detail
  overflow menu, and on the admin mower card ("Dropped N jobs … reliability
  flag"). `MowerRepository.releaseJob` / `cancelJob`; `AdminMower.refusals30d` /
  `autoAllocate`.
- **En-route customer↔mower chat + off-app flagging (2026-07-26)** —
  `0024_chat_and_flagging.sql` (**applied + flag logic verified**). A `messages`
  table (RLS: the booking's customer, its mower, and admins; realtime-published)
  with **no insert policy** — every message goes through `send_message(booking,
  body)` (SECURITY DEFINER) which enforces participation + that the job is
  `en_route/arrived/in_progress` (chat opens the moment the address unlocks and
  closes when the job ends), then **flag-scans the text server-side** against the
  admin-tunable `chat_flag_terms` table (cash / bank transfer / "cancel the
  booking" / phone numbers / "off the app" …). A flagged message is stored
  `flagged=true`, raises an **admin email (queued) + a support ticket
  immediately**, and — deliberately — gives the sender **no hint** they were
  flagged. Shared `ChatScreen` (`/chat/:id`) reached from the mower job detail
  and the customer booking-status screen; `ChatRepository` streams the thread.
  Admin CRUD RPCs `admin_list/save/delete_flag_term` (no UI yet). Supersedes the
  "in-app chat out of scope" line below.
- **Notifications live + admin alerts inbox (2026-07-26)** —
  `0018_notifications.sql` **now applied** (customer emails enqueue as `pending`;
  still needs RESEND_API_KEY + `process-notifications` deployed + the drain cron
  to actually send). `_enqueue_admins` fans an alert to every admin.
  `0025_admin_support.sql` (**applied**) extends `admin_list_support_tickets`
  with the transcript + open-first sort, adds `admin_resolve_support_ticket` and
  `admin_open_ticket_count`. New **Alerts** tab in `admin_shell.dart` (badge =
  open count) → `admin_alerts_screen.dart`: the in-app "notified straight away"
  surface for chat/reliability flags. `AdminRepository.supportTickets` /
  `resolveTicket` / `openTicketCount`.
- **Preferred mowrs — keep the mowr you liked (2026-07-27)** —
  `0026_preferred_mowrs.sql` (**applied + verified 2026-07-28**).
  A `preferred_mowrs` table (customer_id, mowr_id; owner-RLS) + RPCs:
  `add_preferred_mowr(booking)` (anchored to a *completed* job the caller owns),
  `remove_preferred_mowr`, `list_preferred_mowrs`, and
  `preferred_mowr_availability(from, days)` = each preferred mowr's next free
  date (capacity vs work_start/work_end). **`allocate_jobs_for` is now
  preference-aware**: for each job it also tracks the best-fitting mowr among
  the customer's preferred list and, if one fits, assigns them over the overall
  least-disruption pick. Flutter: `PreferredMowr`/`MowrAvailability` domain;
  `BookingRepository.addPreferredMowr` / `removePreferredMowr` /
  `listPreferredMowrs` / `preferredMowrAvailability` / `rescheduleBooking`. On
  `booking_status_screen`: a completed booking shows **"Add to preferred
  mowrs"**; an upcoming (confirmed/broadcast/accepted) booking shows a
  **preferred-mowr availability card** (each mowr's next free date + one-tap
  "Move here" reschedule via `reschedule_booking`). `flutter analyze` clean;
  unverified on device (needs the migration applied + a completed job). Also
  portrayed on the marketing site ("Your mowr, on repeat" section + FAQ).
- **Weather-aware scheduling (2026-07-28)** — `0027_weather.sql` (**applied**) +
  edge fn **`weather-sweep`** (**deployed + scheduled**). Keyless **Open-Meteo**
  (no API key): a nightly sweep (pg_cron `weather-sweep` 20:00) reads the
  forecast per property for upcoming jobs, flags each `rain_risk` true/false
  (`set_job_weather`), and **moves rained-off recurring jobs to the next dry
  day** (`weather_reschedule` → back to the pool, customer emailed) instead of
  skipping a week. One-offs are just flagged. `mowr_jobs_weather()` feeds a
  **Dry / Rain-likely badge** on the mower job list so a mowr can pick up dry
  work nearby when their own area's wet. Cron order: weather-sweep 20:00 →
  generate-recurring 06:00 → allocate-tomorrow 06:10. Verified live 2026-07-28
  (function returns ok; no upcoming jobs to flag yet). Marketing site portrays
  it ("Never lose a week to the weather" + a weather-reschedule screen mockup).
- **Merged AI chat assistant (2026-07-24)** — one conversational surface for
  customers: support Q&A + record actions + new-booking hand-off + human
  escalation. `supabase/functions/assistant/index.ts` runs a Claude
  (`claude-opus-4-8`) tool-calling loop **server-side** via the Messages API
  (raw fetch; `ANTHROPIC_API_KEY` is an edge secret, never in code). Tools:
  `get_my_bookings` + the record RPCs `reschedule_booking` / `cancel_booking` /
  `respond_to_revision` / `escalate_support` (all run through a **user-scoped**
  Supabase client, so RLS + SECURITY DEFINER confine everything to the signed-in
  customer), plus `start_booking` — a **client action**: the function returns
  `{action:'start_booking'}` and the app opens the existing booking flow
  (map-draw + payment stay in the UI, money human-in-the-loop). Booking itself is
  deliberately NOT done by the assistant. Flutter: `AssistantScreen`
  (`/assistant`, sign-in-gated), `AssistantRepository`, `ChatMessage` /
  `AssistantReply` domain; entry point on the welcome screen ("Chat with the
  MOWR assistant"). Migration `0019_assistant.sql` adds the reschedule/cancel
  RPCs, a `support_tickets` table (owner-read RLS) + `escalate_support` /
  `admin_list_support_tickets`. `flutter analyze` clean.
  **Setup before it works (all pending — MCP was read-only this session):**
  (1) apply `0019_assistant.sql`; (2) set the `ANTHROPIC_API_KEY` edge secret
  (**rotate** the key pasted in chat — it's in the transcript in plaintext);
  (3) deploy the `assistant` edge function. Unverified on device (needs a
  signed-in customer). Admin has no support-ticket UI yet (`admin_list_support_
  tickets` exists but isn't surfaced).
- **Investor brief (2026-07-23)** — `docs/investor_brief.html`, published
  artifact (see memory). Tells the scaling story: recurring jobs auto-allocated
  the night before + customer ETAs, "like home deliveries". Honesty rules baked
  in: "Built" = real, vision = "Roadmap", figures = "illustrative".
- **Mower "Take me there" (2026-07-23)** — job detail opens turn-by-turn
  directions in the device's own maps app (Google/Apple) via `openDirections()`
  in `mower_job_detail_screen.dart`. Nav is deliberately NOT built in-house — the
  phone's maps app is best-in-class, free, no API key.
- **Mower in-app route map (2026-07-23)** — `mower_route_screen.dart` (route
  `/mower/route`, reached from the Jobs-tab app-bar route icon) shows the day's
  accepted jobs as an **optimised route**: numbered stops in sequence on a
  satellite map + connecting polyline, a summary (stops / driving / finish), and
  a timed stop list with per-stop "Take me there". Date chips switch between days
  that have jobs. Uses the `schedule.dart` engine (`optimiseJobs`) + the existing
  `flutter_map`/satellite-tile setup — no Mapbox Navigation SDK. Decision (owner,
  2026-07-23): keep the mower **in-app for the route overview** (the valuable,
  cheap, in-house part) but hand off the **actual driving** to Google/Apple Maps
  — the Mapbox Navigation SDK is a paid per-trip service with immature Flutter
  support, not worth it while someone's driving. Unverified on device (mower
  sign-in).
- **Mower phone verification + dedup (2026-07-23)** — a robuster sign-up: a
  mower confirms a mobile number by SMS one-time code before taking jobs.
  Doubles as the account **dedup anchor** — Supabase enforces one confirmed
  phone per auth user, so a number can't spin up a second mower.
  `AuthRepository.sendPhoneOtp` / `verifyPhone` (Supabase `updateUser(phone)` +
  `verifyOTP(phoneChange)`); screen `mower_verify_phone_screen.dart` (route
  `/mower/verify-phone`), gating banner on the mower home, admin column.
  Verification state is read from `auth.users.phone_confirmed_at` (managed by
  Supabase, NOT client-writable) — so `is_approved_mower()` gates on it directly
  rather than a spoofable profiles flag. Migration `0014_phone_verification.sql`
  adds this as a THIRD work gate (approved + payout-onboarded + phone-verified).
  **Two setup steps before it works:** configure an SMS provider in the Supabase
  dashboard (Auth → Providers → Phone), THEN apply 0014 — applying it first
  would lock every mower behind a step they can't complete. Built + compiles;
  not yet exercised on device (needs a mower sign-in + the SMS provider).
- **Identity verification — considered and dropped (2026-07-23).** Evaluated
  Stripe Identity (doc + selfie) for mower sign-up, then dropped it: every mower
  is paid via Stripe Connect, whose mandatory KYC already identifies them, so
  Identity mostly duplicated it at +£1.50/check and extra friction. The robust
  sign-up need is better met by phone dedup (above) + Connect's existing KYC.
- **DBS background check — staged, not built.** The real home-access trust layer,
  but blocked on owner decisions (provider, who pays, relevant-offences policy)
  and legally limited to a **Basic** DBS for lawn mowing (unspent convictions
  only; Standard/Enhanced need regulated-activity eligibility MOWR lacks). When
  built: a fourth `is_approved_mower()` gate, onboarding step + admin review of
  flagged results (human decision, never auto-reject).
- **Customer bottom nav (2026-07-23)** — Home / Bookings / Payment bar
  (`customer_nav_bar.dart`) on the three customer top-level screens (welcome,
  `/bookings`, `/payment-methods`), mirroring the mower bar. **Shown only when
  signed in** — it watches `isSignedInProvider` and collapses to nothing for a
  guest. Fixes a real trap: `/bookings` is reached with `context.go` (from
  confirmation and sign-in), which replaces the stack, so a customer landing
  there had no back button and no other way out. Tabs use `go`, so switching
  between them stays flat. AppBars use the default `automaticallyImplyLeading`:
  a back arrow shows when the screen was `push`ed and there's something to pop,
  and is absent (nav bar is the exit) when `go`-reached.
- **Admin UI (2026-07-23)** — `/admin` mower vetting queue
  (`admin_mowers_screen.dart`: approve/unapprove, per-mower commission, shows
  Stripe onboarding state and why a mower can't work) and `/admin/settings`
  (`admin_settings_screen.dart`: pricing rates, re-measure auto-approve
  threshold, default commission). Backed by `admin_repository.dart` +
  `admin_models.dart` and migration `0013_admin.sql`. There is deliberately no
  in-app way to create an admin — set `profiles.role='admin'` by hand.
- **Pricing now loads from the database (2026-07-23)** — `pricingRulesProvider`
  is a `StateProvider` seeded with the in-code defaults and overwritten at
  startup by `loadPricingRules()` reading the `pricing_rules` row; the admin
  settings screen writes back to both. Rates are therefore data, editable
  without a release. It stays synchronous on purpose: several booking steps
  price during `build`.
- **Map loading overlay (2026-07-23)** — every map (`address_step`,
  `lawn_draw_screen`, `mower_lawn_draw_screen`) now covers its grey tile grid
  until imagery arrives. `core/map/map_load_state.dart` holds `MapLoadState` +
  `MapLoadingOverlay`; `satelliteTileLayer(loadState:)` reports finished tiles
  via `tileBuilder`. Ready = tiles have *stopped* arriving (400 ms settle), not
  first tile, with a 10 s timeout so a dead network still shows the map. The
  overlay is the last `Stack` child (topmost) and `IgnorePointer`s once hidden,
  so it never swallows drawing taps.

`mower_earnings(p_from date, p_to date)` returns
`{from, to, totals:{jobs, gross, fees, net}, jobs:[{booking_id, completed_date,
line1, city, postcode, job_total, commission_amount, mower_amount}]}`, scoped to
the signed-in mower.

**Setup Howard still has to do (once)**
- Enable **Stripe Connect** in the Stripe dashboard (test mode) before payout
  onboarding will work.
- Migrations `0006`→`0007`→`0008` and **`0013_admin.sql`** are applied to the
  MOWR project (`ypbizskokuxpfdyvdgmg`) as of 2026-07-23. `0013` adds
  `is_admin()` + the `admin_*` RPCs the admin surface calls.
- **`howardmowr2@mowr.co.uk` is the admin** (role set 2026-07-23). To add
  another, by hand (no in-app path): `update public.profiles set role='admin'
  where id = (select id from auth.users where email='…');`
- Admins sign in via the mower **"Are you a mower? Sign in"** link — the auth
  screen role-checks and routes admins to `/admin`, mowers to the dashboard.
- Pass **`IDEAL_POSTCODES_API_KEY`** on every run, or postcode lookup falls back
  to sample addresses. Verified working 2026-07-23 against CO6 3RR (real
  Rectory Road addresses, pin landing on the individual property).
- Deploy edge functions: `capture-payment`, `connect-onboard`, `connect-status`,
  `connect-dashboard`, `connect-balance`, and `connect-return`
  (`connect-return` with `--no-verify-jwt`).
- `flutter pub get` (picks up `share_plus` + `path_provider`).

**Open TODOs**
- **Pricing numbers** — still the owner's real rates. The plumbing is now done:
  rates live in the `pricing_rules` row and are editable at `/admin/settings`,
  no code change needed. What ships today are placeholders — mow £12 turn-up /
  £0.15 per m² / £20 minimum; edging £6 turn-up / £0.40 per metre / £10
  minimum; height multipliers 1.0 / 1.6 / 2.0. All pricing must keep going
  through the single `PricingEngine`.
- **Approve/decline card is unverified on device.** The screen, the RPC and the
  seeded data are all in place, but exercising it needs a signed-in customer
  holding a booking with `approval_status='pending'` — nobody has driven it
  end to end yet.
- **Admin UI is unverified on device.** Backend (0013) is applied and the admin
  account exists, but nobody has signed in as admin and confirmed `/admin`
  renders the mower list — needs a password.
- **Admin has no bookings view.** `/admin` covers mower vetting and settings
  only; assigning or intervening in a specific booking is still SQL.
- **No password reset** anywhere, customer or mower.
- **Phone verification unproven on device** — SMS provider not configured in
  Supabase, and migration `0014_phone_verification.sql` not yet applied (both
  deliberately pending, see above). Dedup relies on Supabase's unique-confirmed-
  phone enforcement, which only bites once SMS is live.
- **DBS background check** — not built (staged, owner decisions pending).
- **Accounting integration (Xero / QuickBooks) — requested 2026-07-24, NOT
  started.** Owner wants mowers' earnings pushed to Xero/QuickBooks as invoices.
  A separate epic (OAuth2 to each provider, encrypted token storage + refresh,
  earnings→invoice mapping, edge functions, likely a nightly/at-completion push).
  Open decisions before building: (1) whose books — one central MOWR org, or
  per-mower connections? (2) invoice or bill/expense (a payout to a mower is
  MOWR's cost, so likely a **bill/expense**, not a sales invoice — confirm the
  accounting direction); (3) trigger — per completed job vs a periodic summary;
  (4) which provider first. Claude will build the integration code but will NOT
  authorise connections or send live invoices — the OAuth consent + provider app
  credentials stay with the owner.

**No longer true (was listed as outstanding, now built)** — service/edging,
schedule, review/price and confirmation steps all exist and are wired.

**Fixed 2026-07-22 — booking step counter.** `booking_shell.dart` numbered the
steps wrongly: `kStepLawn`/`kStepGrassHeight` were both `3`, and `kStepReview`
(8) was reused by `review_step`, `account_step` and `payment_step`. A guest
never saw "3 of 10", saw "4 of 10" twice and "9 of 10" three times, and the
progress bar stalled. Each screen now has a distinct index and
`kBookingStepCount` is **11** (both paths have 11 `BookingShell` screens; the
two entry screens differ per path, then they converge). Verified on-device:
1 → 2 → 3 → 8 → 9 of 11 with the bar advancing each time. Note the rule in the
file's doc comment — two constants may share an index only when they are
*alternative* screens at the same position on different paths, never sequential
screens on the same path.

---

## What MOWR is

On-demand lawn mowing marketplace. Three roles, one Flutter app, one Supabase
backend.

- **Customer** — books and pays for mows, tracks status in real time.
- **Mower** — applies to join, accepts/completes assigned jobs.
- **Admin** — vets mowers, manages bookings/assignments. Surface = Flutter web.

---

## Architecture (locked — do not revisit without explicit decision)

| Decision | Choice |
|----------|--------|
| App structure | Single Flutter codebase, role-based routing on login |
| Admin surface | Flutter web target (same codebase) |
| Backend | One Supabase project; RLS enforces role boundaries |
| Services/pricing | Data, not code. Adding a service = DB row, never a code change |
| State management | Riverpod — repository pattern wrapping Supabase |
| Routing | go_router with auth + role-based redirects |
| Payments | Stripe (direct, not IAP — lawn mowing is a real-world service) |

---

## Tech stack

| Concern | Choice |
|---------|--------|
| UI | Flutter stable |
| State | flutter_riverpod 2.x |
| Routing | go_router |
| Backend | Supabase (Auth, DB, Realtime, Storage) |
| Payments | Stripe (Phase 3) |
| iOS builds | Codemagic cloud macOS (no Mac owned) |
| Dev env | Windows + VS Code + Claude Code (native Windows, no WSL) |

---

## Folder structure

```
lib/
  core/
    theme/
      app_colors.dart       ← Palette (green #34734B, bg #F7F7F4 — see tokens)
      app_theme.dart        ← AppTheme.light — single source for ThemeData
    routing/
      router.dart           ← GoRouter; auth + role redirect logic lives here
    supabase/
      supabase_client.dart  ← SupabaseInit.init(); credentials via build config
  features/
    auth/
      data/auth_repository.dart
      presentation/         ← login, register, mower-apply screens
    booking/
      data/booking_repository.dart
      domain/booking_model.dart
      presentation/         ← booking flow screens (Phase 1+)
    mower/
      data/mower_repository.dart
      presentation/         ← mower home, job detail (Phase 4)
    admin/
      data/admin_repository.dart
      domain/admin_models.dart
      presentation/         ← mower vetting (/admin), settings (/admin/settings)
  main.dart                 ← ProviderScope → MowrApp (MaterialApp.router)
```

---

## Coding conventions

- **Feature-first** — all code for a feature lives under `lib/features/<feature>/`.
- **Repository pattern** — UI → Riverpod providers → repositories → Supabase.
  Never call Supabase directly from a widget.
- **Immutable models** — `freezed` or manual `const` constructors with `copyWith`
  and JSON (de)serialisation. No mutable model classes.
- **No inline Supabase credentials** — URL and anon key come from build config /
  environment; `SupabaseInit.init()` is called in `main()` (Phase 2).
- **RLS always** — every Supabase table ships with Row Level Security policies.
  Never open a table without them.
- **Pricing is central** — all price calculation goes through a single
  `PricingEngine`. The formula's inputs are the `pricing_rules` row, loaded at
  startup by `loadPricingRules()` and editable at `/admin/settings`. Do not
  duplicate pricing logic, and do not reintroduce hard-coded rates: the in-code
  `kDefaultPricingRules` is a fallback for when the row can't be read, not the
  source of truth.

---

## Screen wiring (mandatory)

When building a screen that consumes data another screen produces, or
produces data another screen consumes:

- Wire the real shared-state contract (the BookingDraft / Riverpod
  provider) between the screens. Read inputs from the draft; write outputs
  to the draft.
- Do NOT create a standalone mock data list inside a screen that shadows or
  duplicates data the draft already carries (e.g. a local _mockLawns in a
  screen that should read the selected property's lawns from the draft).
- Mock only true leaf data that no other screen produces — never mock the
  seam between two screens.
- When a new screen connects to an existing screen, explicitly inspect that
  existing screen and rewire it if it still uses standalone mock data that
  the new screen's contract supersedes. State this in the summary.
- Provide a verification checkable by eye: mock data on either side of a
  seam must be visibly distinct (different names/counts) so a wrong or
  missing wiring is obvious when navigating, not hidden behind
  identical-looking data.

Rationale: screens built in isolation with mocked inputs are individually
correct, but the seam between a screen and the one that feeds it is where
data-wiring bugs hide. This makes wiring the seam a build-time requirement,
not a review-time catch.

---

## Design system tokens (v3 — Swiss monochrome, 2026-07-25)

**v3 revamp (owner-approved 2026-07-25, in progress).** Direction: International
Typographic Style — ink on paper, one signal green, flush-left grid, **hairline
rules instead of nested boxes**, crisp **5px** radius (was 12), **Arimo**
(Helvetica-compatible, via google_fonts) replacing Inter. Green is rationed to
the primary action + live/available/success only. Tokens live in `AppColors`
(paper `#F5F5F2`, surface `#FFF`, ink `#121211`, graphite `#6E6E69`, hairline
`#E3E3DE`, green `#2E6A43`/dark `#1F4C30`/pale `#E9F0EA`) and `AppTheme`; shared
primitives in `core/theme/ui.dart` (`Eyebrow`, `Hairline`, `SectionHeader`,
`StatTile`/`StatRow`, `StatusPill`, `DataRow2`, and `StatHero`/`MiniStat`/
`MiniStatRow` for the dashboard "hero figure + supporting row" = concept B).
Approved mockup: `docs/design_preview.html` (published artifact, 16 screens).
Dashboard stat concept = **B (hero + secondary)**, owner-chosen 2026-07-26.
**Swept to the new system:** theme foundation + primitives, splash (animated:
icon drops from top, wordmark bounces from bottom), welcome (centered wordmark,
Book a MOWR / Sign in / Become a MOWR), booking review, mower home + dashboard,
mower payouts + tier, mower earnings, admin dashboard, bookings (segmented),
billing & payments. Real logo/app icon in place. **Sweep still pending** (inline
greys/weights the theme mostly normalises; hairline polish): mower job-detail
internals, mower jobs list detail, admin CRUD screens (mowers/settings/discounts/
tiers), assistant, remaining booking steps (schedule/service/grass-height/
confirmation), booking-status internals. PDF of the mockups: `docs/mowr_screens.pdf`.
The v2 notes below are superseded where they conflict.

## Design system tokens (v2 — monochrome utility, 2026-07-24) — superseded by v3

Direction: a premium, fast **service marketplace** — not a gardening app. ~75%
warm neutral, ~15% dark, ~10% green + status. **Green is a signal, not
decoration** — reserve it for the primary action, a selected option, live job
progress, successful completion, and available services. Thin 1px borders
instead of shadows; left-aligned headings; one obvious primary action per screen;
pills for status only.

| Token | Value |
|-------|-------|
| Green (brand / signal) | `#34734B` · pale `#E7F0E9` · dark `#255239` |
| Background | `#F7F7F4` (warm off-white) |
| Card surface | `#FFFFFF` |
| Primary text | `#121212` · secondary `#696966` |
| Borders | `#E4E4DF` (1px, in place of shadows) |
| Warning / Error | `#E7A83B` / `#CB5148` |
| Corner radius | 12 px (cards, buttons, inputs); 16 px sheets; pills = status only |
| Type | **Inter** (`google_fonts`); page 28/700, section 18/600, body 15, support 13, figure 24–32/800 |
| Buttons | primary full-width 54px green; secondary 1px-border; small actions = text/icon |
| Bottom nav | 4 items, line icons, green when active |
| Material version | Material 3 (`useMaterial3: true`) |

All tokens live in `AppColors` and `AppTheme`. Never hard-code colours or radii
in widget files. **Sweep done 2026-07-24 (build-only, unverified on device):**
all hard-coded `circular(18/20/24)` → `12` app-wide; all `Colors.grey.shade*`
→ warm palette hex; every decorative icon-in-green-circle `CircleAvatar` → a
neutral rounded-square tile (numbered route-map pins kept); welcome + booking
shell + confirmation + bookings + schedule hand-polished (left-aligned, no
centred green hero). `primaryContainer` is now the subtle pale green `#E7F0E9`,
so old "mint" blocks read correctly without change. Remaining polish (best done
against the emulator): verify each screen visually, tidy inline `TextStyle`
weights onto the type scale, and note the grey→hex swaps are interim — they
should become theme refs. Target look = the `docs/rendered_screens.html`
artifact (UI direction v2).

---

## Phased roadmap (current: Phase 0 complete)

| Phase | Scope |
|-------|-------|
| 0 ✅ | Foundation: project structure, dependencies, design system |
| 1 | Customer booking flow — no backend. Real navigation, form state, mock data |
| 2 | Supabase: auth with roles, schema live, persist bookings, photo storage, mower-application intake |
| 3 | Payments: Stripe integration, charge on booking |
| 4 | Mower app + admin UI + ratings + push notifications |
| 5 | New services as pure data, polish, store submission |

### Phase 1 scope change (2026-07 — owner decision)

Two things were pulled forward into Phase 1 by explicit owner decision (they
were previously deferred; the spec's "manual entry only" Phase-1 note is now
superseded):

- **Map-boundary lawn drawing (Method 2) is now IN Phase 1**, alongside manual
  entry as a fallback. Draw a polygon on satellite imagery; area + perimeter
  are derived geodesically (`lib/features/booking/domain/lawn_geometry.dart`,
  validated numerically). Maps via `flutter_map`; Mapbox satellite when
  `MAPBOX_TOKEN` is set, free Esri World Imagery otherwise.
- **Live UK postcode → address lookup is now IN Phase 1.** **Ideal Postcodes is
  the sole source for both addresses and coordinates** (owner decision,
  2026-07-23): with `IDEAL_POSTCODES_API_KEY` set it validates the postcode,
  returns the house-level address list, and supplies the lat/lng — per address
  plus the centroid that seeds the map. postcodes.io is used *only* on the
  keyless demo path and is not called when a key is present. getukaddress.com
  was evaluated and rejected: it returns no coordinates, and per-address lat/lng
  is load-bearing for the confirm-location and lawn-drawing maps. A provider or
  key failure raises `AddressLookupException`, kept distinct from
  `PostcodeNotFoundException` so a billing problem doesn't read as a bad
  postcode. See `lib/features/booking/data/address_repository.dart`.

Secrets are injected via `--dart-define` (`MAPBOX_TOKEN`,
`IDEAL_POSTCODES_API_KEY`)
and read only through `lib/core/config/app_config.dart` — never hard-coded.

Guest-path lawns live in `BookingDraft.draftLawns`; both entry paths resolve the
booking's lawns through `resolveBookingLawns(draft)` (the single seam — see
Screen wiring above). Still pending from the owner before the price/review step:
the **pricing formula**.

---

## Key constraints

- **No Mac.** iOS binaries built via Codemagic. Dev/test on Android emulator.
  Validate iOS on Codemagic regularly — not only at the end.
- **Apple Developer Program** needed before Phase 3–4 (real-device install /
  store submission). Not needed yet.
- **Stripe, not IAP.** Physical real-world service is exempt from Apple/Google
  30 % cut. Never add IAP.
- **Native Windows dev env.** No WSL. All tooling runs natively on Windows.

---

## Out of scope for v1

- ~~In-app mower ↔ customer chat.~~ **Built 2026-07-26** (en-route only, with
  off-app/cash flagging) — see the handoff section above.
- Recurring / subscription bookings ("Regular" in design — logic deferred).
- Mower payouts / payroll automation (manual early on).
