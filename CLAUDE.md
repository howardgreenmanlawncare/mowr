# MOWR — Claude Code guide

Source of truth: `MOWR_PROJECT_SPEC.md`. This file distils the spec into
day-to-day conventions. Update both files together when decisions change.

---

## Current state (handoff, 2026-07-22)

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

`mower_earnings(p_from date, p_to date)` returns
`{from, to, totals:{jobs, gross, fees, net}, jobs:[{booking_id, completed_date,
line1, city, postcode, job_total, commission_amount, mower_amount}]}`, scoped to
the signed-in mower.

**Setup Howard still has to do (once)**
- Enable **Stripe Connect** in the Stripe dashboard (test mode) before payout
  onboarding will work.
- Ensure migrations `0006` → `0007` → `0008` are applied (in order).
- Deploy edge functions: `capture-payment`, `connect-onboard`, `connect-status`,
  `connect-dashboard`, `connect-balance`, and `connect-return`
  (`connect-return` with `--no-verify-jwt`).
- `flutter pub get` (picks up `share_plus` + `path_provider`).

**Open TODOs**
- **Pricing numbers** — the engine is built and verified live
  (`lib/features/booking/domain/pricing.dart`); what's outstanding is the
  owner's real rates. `PricingRules` currently ships placeholder defaults:
  mow £12 turn-up / £0.15 per m² / £20 minimum; edging £6 turn-up / £0.40 per
  metre / £10 minimum; height multipliers 1.0 / 1.6 / 2.0. Verified on-device:
  120 m² medium + 45 m edge = £40.80 + £24.00 = £64.80. Swapping these for real
  figures is a `PricingRules` change only — and in Phase 2 they move to
  `pricing_rules` rows. All pricing must keep going through the single
  `PricingEngine`.
- Customer-facing **revision-approval UI** (backend `respond_to_revision` is
  ready; no customer post-booking surface yet).
- **Admin UI** for approving mowers and editing commission / revise threshold
  (currently SQL only). `admin_repository.dart` is still an empty stub.

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
      app_colors.dart       ← Color constants (seed 0xFF2E7D32, bg 0xFFF7F8F5)
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
      presentation/         ← admin screens (Phase 4)
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
  `PricingEngine` (Phase 2+). The formula's inputs are rows in `pricing_rules`.
  Do not duplicate pricing logic.

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

## Design system tokens

| Token | Value |
|-------|-------|
| Seed colour | `0xFF2E7D32` (Material Green 800) |
| Background | `0xFFF7F8F5` (warm off-white) |
| Border radius | 20 px (cards, buttons, inputs, bottom sheets) |
| Material version | Material 3 (`useMaterial3: true`) |

All tokens live in `AppColors` and `AppTheme`. Never hard-code colours or radii
in widget files.

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
- **Live UK postcode → address lookup is now IN Phase 1.** postcodes.io (free,
  no key) for the postcode centroid that seeds the map; Ideal Postcodes (needs
  `IDEAL_POSTCODES_API_KEY`) for the house-level address list, with a
  sample-address fallback when no key is set. See
  `lib/features/booking/data/address_repository.dart`.

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

- In-app mower ↔ customer chat.
- Recurring / subscription bookings ("Regular" in design — logic deferred).
- Mower payouts / payroll automation (manual early on).
