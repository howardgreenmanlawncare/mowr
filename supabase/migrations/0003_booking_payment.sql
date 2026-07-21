-- MOWR — Stripe (Phase 3, step 2)
-- Track the payment authorisation (hold) against each booking. Run in the
-- Supabase SQL editor.

alter table public.bookings
  add column if not exists payment_intent_id text,
  add column if not exists payment_status text
    check (payment_status in ('authorized', 'captured', 'cancelled', 'failed'));
