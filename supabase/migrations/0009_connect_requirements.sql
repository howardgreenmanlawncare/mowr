-- MOWR — Surface Stripe Connect "action required" to the mower
-- Stripe can ask a connected account for more info (e.g. a photo ID) after
-- onboarding. We store the outstanding requirement on the profile so the app
-- can prompt the mower to finish verification. Run in the Supabase SQL editor.

alter table public.profiles
  add column if not exists connect_action_required boolean not null default false,
  add column if not exists connect_requirement      text;

-- mower_account now also reports the outstanding requirement.
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
    'commission_pct',          coalesce(p.commission_pct, r.default_commission_pct, 15),
    'default_commission_pct',  coalesce(r.default_commission_pct, 15)
  )
  from public.profiles p
  left join public.pricing_rules r on r.id = 1
  where p.id = auth.uid();
$func$;
grant execute on function public.mower_account() to authenticated;
