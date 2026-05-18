# MOWR — Claude Code guide

Source of truth: `MOWR_PROJECT_SPEC.md`. This file distils the spec into
day-to-day conventions. Update both files together when decisions change.

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
