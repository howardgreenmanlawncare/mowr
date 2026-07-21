-- MOWR — Stripe (Phase 3, step 1)
-- Stores each customer's Stripe customer id so saved cards persist across
-- sessions. Run this in the Supabase SQL editor.

alter table public.profiles
  add column if not exists stripe_customer_id text;
