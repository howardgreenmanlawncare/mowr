-- MOWR — Admin surface (Phase 4)
--
-- 0001 and 0008 both defer admin permissions to "the admin migration" — this is
-- it. Until now an admin could only read their OWN profile row, so there was no
-- way to list mower applications, approve one, or edit pricing except by
-- editing rows by hand in the Supabase dashboard.
--
-- Design: everything goes through SECURITY DEFINER functions that check
-- is_admin() themselves, rather than widening the RLS policies on profiles and
-- pricing_rules. That keeps the blast radius small — an admin gets exactly the
-- operations below and nothing else, and a bug in a policy predicate can't
-- quietly expose every customer's profile.
--
-- Run in the Supabase SQL editor, after 0012.

-- ---------------------------------------------------------------------------
-- 1. Who is an admin.
--    SECURITY DEFINER matters: this reads profiles, and profiles has RLS. A
--    plain function called from a profiles policy would recurse.
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $func$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$func$;

grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Mower vetting queue.
--    Everyone with role 'mower', newest first, with the two facts that decide
--    whether they can actually take work: admin approval and Stripe onboarding.
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
      'phone',              p.phone,
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

-- ---------------------------------------------------------------------------
-- 3. Approve / un-approve a mower.
--    Scoped to role='mower' so this can never be used to flip an admin or a
--    customer.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_mower_approved(
  p_mower_id uuid,
  p_approved boolean
)
returns boolean language plpgsql security definer set search_path = public
as $func$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  update public.profiles
     set mower_approved = p_approved
   where id = p_mower_id and role = 'mower';

  if not found then
    raise exception 'No such mower';
  end if;

  return p_approved;
end;
$func$;

grant execute on function public.admin_set_mower_approved(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Per-mower commission override. NULL = fall back to the global default.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_commission(
  p_mower_id uuid,
  p_pct      numeric
)
returns numeric language plpgsql security definer set search_path = public
as $func$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  if p_pct is not null and (p_pct < 0 or p_pct > 100) then
    raise exception 'Commission must be between 0 and 100';
  end if;

  update public.profiles
     set commission_pct = p_pct
   where id = p_mower_id and role = 'mower';

  if not found then
    raise exception 'No such mower';
  end if;

  return p_pct;
end;
$func$;

grant execute on function public.admin_set_commission(uuid, numeric)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Global settings: pricing rates, re-measure auto-approve threshold and the
--    default commission. All live on the single pricing_rules row.
--    Readable by anyone (the app prices with it); writable by admins only.
-- ---------------------------------------------------------------------------
create or replace function public.admin_settings()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  select to_jsonb(r) into v from public.pricing_rules r where r.id = 1;
  return coalesce(v, '{}'::jsonb);
end;
$func$;

grant execute on function public.admin_settings() to authenticated;

create or replace function public.admin_update_settings(p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $func$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  -- Only these keys are writable. Anything else in the patch is ignored rather
  -- than erroring, so adding a field to the client can't break the call.
  update public.pricing_rules r
     set mow_turn_up         = coalesce((p_patch->>'mow_turn_up')::numeric,         r.mow_turn_up),
         mow_rate_per_sqm    = coalesce((p_patch->>'mow_rate_per_sqm')::numeric,    r.mow_rate_per_sqm),
         mow_minimum         = coalesce((p_patch->>'mow_minimum')::numeric,         r.mow_minimum),
         edge_turn_up        = coalesce((p_patch->>'edge_turn_up')::numeric,        r.edge_turn_up),
         edge_rate_per_metre = coalesce((p_patch->>'edge_rate_per_metre')::numeric, r.edge_rate_per_metre),
         edge_minimum        = coalesce((p_patch->>'edge_minimum')::numeric,        r.edge_minimum),
         height_mult_low     = coalesce((p_patch->>'height_mult_low')::numeric,     r.height_mult_low),
         height_mult_medium  = coalesce((p_patch->>'height_mult_medium')::numeric,  r.height_mult_medium),
         height_mult_high    = coalesce((p_patch->>'height_mult_high')::numeric,    r.height_mult_high),
         revise_auto_threshold_pct =
           coalesce((p_patch->>'revise_auto_threshold_pct')::numeric, r.revise_auto_threshold_pct),
         default_commission_pct =
           coalesce((p_patch->>'default_commission_pct')::numeric, r.default_commission_pct),
         updated_at = now()
   where r.id = 1;

  select to_jsonb(r) into v from public.pricing_rules r where r.id = 1;
  return coalesce(v, '{}'::jsonb);
end;
$func$;

grant execute on function public.admin_update_settings(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Promote yourself to admin (run once, by hand — there is deliberately no
--    in-app way to create an admin):
--
--   update public.profiles set role = 'admin'
--    where id = (select id from auth.users where email = 'you@example.com');
-- ---------------------------------------------------------------------------
