-- MOWR — Stripe Connect + payouts + job history (mower marketplace expansion)
-- Mowers onboard a Stripe Connect **Express** account as part of verification;
-- once onboarded AND admin-approved they can accept jobs. On completion the
-- platform captures payment then transfers the mower's share (total minus
-- commission) to their connected account. Commission is per-mower with an
-- admin default. Run in the Supabase SQL editor.

-- ---------------------------------------------------------------------------
-- 1. Connect + commission on the mower's profile.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists stripe_connect_id text,
  add column if not exists connect_onboarded boolean not null default false,
  add column if not exists commission_pct    numeric(6,3);   -- null => use default

-- Admin-editable default commission (percent MOWR keeps).
alter table public.pricing_rules
  add column if not exists default_commission_pct numeric(6,3) not null default 15;

-- ---------------------------------------------------------------------------
-- 2. Payout tracking on the booking.
-- ---------------------------------------------------------------------------
alter table public.bookings
  add column if not exists transfer_id       text,
  add column if not exists mower_amount      numeric(10,2),
  add column if not exists commission_amount numeric(10,2);

-- ---------------------------------------------------------------------------
-- 3. A mower can only take jobs once approved AND payout-onboarded.
-- ---------------------------------------------------------------------------
create or replace function public.is_approved_mower()
returns boolean language sql stable security definer set search_path = public
as $func$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'mower'
      and mower_approved
      and connect_onboarded
  );
$func$;

-- ---------------------------------------------------------------------------
-- 4. My jobs = active only (completed/cancelled move to history).
-- ---------------------------------------------------------------------------
create or replace function public.my_jobs()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
begin
  return public._job_json(format(
    $w$b.mower_id = %L and b.status not in ('completed','cancelled')$w$,
    auth.uid()));
end;
$func$;

create or replace function public.my_job_history()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
begin
  return public._job_json(format(
    $w$b.mower_id = %L and b.status = 'completed'$w$, auth.uid()));
end;
$func$;
grant execute on function public.my_job_history() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Mower's own account snapshot (drives onboarding UI + gating banners).
-- ---------------------------------------------------------------------------
create or replace function public.mower_account()
returns jsonb language sql stable security definer set search_path = public
as $func$
  select jsonb_build_object(
    'role',                   p.role,
    'approved',               coalesce(p.mower_approved, false),
    'connect_id',             p.stripe_connect_id,
    'connect_onboarded',      coalesce(p.connect_onboarded, false),
    'commission_pct',         coalesce(p.commission_pct, r.default_commission_pct, 15),
    'default_commission_pct', coalesce(r.default_commission_pct, 15)
  )
  from public.profiles p
  left join public.pricing_rules r on r.id = 1
  where p.id = auth.uid();
$func$;
grant execute on function public.mower_account() to authenticated;
