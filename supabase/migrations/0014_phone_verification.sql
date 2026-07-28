-- MOWR — Mower phone verification + dedup
--
-- A more robust sign-up: a mower must confirm a mobile number by SMS one-time
-- code before taking jobs. This is the account dedup anchor — Supabase enforces
-- one confirmed phone per auth user, so the same number can't spin up a second
-- mower.
--
-- Verification state lives in auth.users.phone_confirmed_at, which is managed
-- by Supabase Auth and NOT client-writable — so we gate on it directly rather
-- than on a profiles flag a mower could set themselves. The functions here are
-- SECURITY DEFINER and so may read the auth schema.
--
-- NOTE: apply this only once an SMS provider is configured in the Supabase
-- dashboard (Auth → Providers → Phone). Applying it before that would gate
-- every mower behind a step they can't complete.

-- ---------------------------------------------------------------------------
-- 1. Phone verification is a third gate on working, alongside admin approval
--    and payout onboarding.
-- ---------------------------------------------------------------------------
create or replace function public.is_approved_mower()
returns boolean language sql stable security definer set search_path = public
as $func$
  select exists (
    select 1
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.id = auth.uid()
      and p.role = 'mower'
      and p.mower_approved
      and p.connect_onboarded
      and u.phone_confirmed_at is not null
  );
$func$;

-- ---------------------------------------------------------------------------
-- 2. Surface phone-verified state to the mower's own account snapshot.
-- ---------------------------------------------------------------------------
create or replace function public.mower_account()
returns jsonb language sql stable security definer set search_path = public
as $func$
  select jsonb_build_object(
    'role',                    p.role,
    'approved',                coalesce(p.mower_approved, false),
    'connect_id',              p.stripe_connect_id,
    'connect_onboarded',       coalesce(p.connect_onboarded, false),
    'connect_action_required', coalesce(p.connect_action_required, false),
    'connect_requirement',     p.connect_requirement,
    'phone_verified',          (u.phone_confirmed_at is not null),
    'commission_pct',          coalesce(p.commission_pct, r.default_commission_pct, 15),
    'default_commission_pct',  coalesce(r.default_commission_pct, 15)
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.pricing_rules r on r.id = 1
  where p.id = auth.uid();
$func$;
grant execute on function public.mower_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admins see who's phone-verified in the vetting queue.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_mowers()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  select coalesce(jsonb_agg(m order by m->>'created_at' desc), '[]'::jsonb)
    into v_rows
  from (
    select jsonb_build_object(
      'id',                 p.id,
      'full_name',          p.full_name,
      'email',              coalesce(p.email, u.email),
      'phone',              coalesce(u.phone, p.phone),
      'phone_verified',     (u.phone_confirmed_at is not null),
      'approved',           coalesce(p.mower_approved, false),
      'connect_onboarded',  coalesce(p.connect_onboarded, false),
      'commission_pct',     p.commission_pct,
      'created_at',         p.created_at,
      'jobs_completed',     (
        select count(*) from public.bookings b
        where b.mower_id = p.id and b.status = 'completed'
      )
    ) as m
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.role = 'mower'
  ) s;

  return v_rows;
end;
$func$;

grant execute on function public.admin_list_mowers() to authenticated;
