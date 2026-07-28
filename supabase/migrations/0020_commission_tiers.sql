-- MOWR — Performance-based commission + customer ratings
--
-- A mower's commission drops as they complete more jobs and earn good reviews.
-- Two new pieces feed it:
--   * reviews          — a customer rates a completed job 1–5 (+ optional note).
--   * commission_tiers — an admin-editable ladder: each tier grants a lower
--                        commission once its jobs / rating / review thresholds
--                        are all met.
--
-- The effective commission for a mower is the BEST (lowest) of:
--   * their admin override (profiles.commission_pct) or the global default, and
--   * the lowest tier they currently qualify for.
-- So a manual override can only ever help them; earning a tier can only reduce.
--
-- mower_commission() is the single source of truth — capture-payment and every
-- read RPC go through it. Run after 0019.

-- ===========================================================================
-- 1. Customer ratings.
-- ===========================================================================
create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null unique references public.bookings(id) on delete cascade,
  mower_id    uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  rating      int  not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);
create index if not exists reviews_mower_idx on public.reviews(mower_id);

alter table public.reviews enable row level security;

-- Customer sees their own reviews; a mower sees reviews about them; admin all.
drop policy if exists "reviews: participant or admin reads" on public.reviews;
create policy "reviews: participant or admin reads"
  on public.reviews for select
  using (customer_id = auth.uid() or mower_id = auth.uid() or public.is_admin());

-- Inserts go only through submit_review (SECURITY DEFINER) — it enforces that
-- the booking is the caller's, completed, assigned to a mower, and unreviewed,
-- and stamps mower_id from the booking (never trusting the client).
create or replace function public.submit_review(
  p_booking_id uuid, p_rating int, p_comment text default null)
returns uuid language plpgsql security definer set search_path = public as $func$
declare v_mower uuid; v_status text; v_id uuid;
begin
  if p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be 1 to 5';
  end if;
  select mower_id, status into v_mower, v_status from public.bookings
    where id = p_booking_id and customer_id = auth.uid();
  if v_status is null then raise exception 'No such booking'; end if;
  if v_status <> 'completed' then
    raise exception 'You can only rate a completed job';
  end if;
  if v_mower is null then raise exception 'This job has no mower to rate'; end if;
  if exists (select 1 from public.reviews where booking_id = p_booking_id) then
    raise exception 'You have already rated this job';
  end if;

  insert into public.reviews (booking_id, mower_id, customer_id, rating, comment)
    values (p_booking_id, v_mower, auth.uid(), p_rating, nullif(trim(p_comment), ''))
    returning id into v_id;
  return v_id;
end;
$func$;
grant execute on function public.submit_review(uuid, int, text) to authenticated;

-- ===========================================================================
-- 2. The commission ladder (data, not code — admin-editable like discounts).
-- ===========================================================================
-- mower_id NULL = a global default tier. When a mower has ANY tier rows of
-- their own, those REPLACE the global ladder for that mower (bespoke reductions);
-- otherwise they fall back to the global defaults.
create table if not exists public.commission_tiers (
  id             uuid primary key default gen_random_uuid(),
  mower_id       uuid references public.profiles(id) on delete cascade,
  name           text not null,
  min_jobs       int  not null default 0,
  min_rating     numeric(3,2) not null default 0,
  min_reviews    int  not null default 0,
  commission_pct numeric(6,3) not null,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);
create index if not exists commission_tiers_mower_idx
  on public.commission_tiers(mower_id);

alter table public.commission_tiers enable row level security;

-- Readable by anyone: mowers need to see the ladder + their progress.
drop policy if exists "commission_tiers: readable" on public.commission_tiers;
create policy "commission_tiers: readable"
  on public.commission_tiers for select using (true);

-- Seed a sensible ladder once (only if empty, so re-running is safe). These are
-- placeholders — tune at /admin. Base (no tier) uses default_commission_pct.
insert into public.commission_tiers (name, min_jobs, min_rating, min_reviews, commission_pct)
select * from (values
  ('Bronze', 10, 4.00,  5, 13.0),
  ('Silver', 30, 4.30, 15, 11.0),
  ('Gold',   75, 4.50, 40,  9.0)
) as v(name, min_jobs, min_rating, min_reviews, commission_pct)
where not exists (select 1 from public.commission_tiers);

-- ===========================================================================
-- 3. Stats + effective-commission helpers (the single source of truth).
-- ===========================================================================
create or replace function public.mower_stats(p_mower uuid)
returns table(jobs_completed int, rating_avg numeric, review_count int)
language sql stable security definer set search_path = public as $func$
  select
    (select count(*)::int from public.bookings b
       where b.mower_id = p_mower and b.status = 'completed'),
    (select round(avg(r.rating)::numeric, 2) from public.reviews r
       where r.mower_id = p_mower),
    (select count(*)::int from public.reviews r where r.mower_id = p_mower);
$func$;

-- The effective commission percent MOWR keeps for this mower.
create or replace function public.mower_commission(p_mower uuid)
returns numeric language plpgsql stable security definer set search_path = public as $func$
declare
  v_default numeric; v_base numeric; v_earned numeric;
  v_jobs int; v_rating numeric; v_reviews int; v_scope uuid;
begin
  select coalesce(default_commission_pct, 15) into v_default
    from public.pricing_rules where id = 1;
  v_default := coalesce(v_default, 15);
  -- base = manual flat override if the admin set one, else the global default.
  select coalesce(commission_pct, v_default) into v_base
    from public.profiles where id = p_mower;
  v_base := coalesce(v_base, v_default);

  select jobs_completed, rating_avg, review_count
    into v_jobs, v_rating, v_reviews
    from public.mower_stats(p_mower);

  -- Use the mower's own ladder if they have one, else the global (NULL) ladder.
  v_scope := case
    when exists (select 1 from public.commission_tiers where mower_id = p_mower)
    then p_mower else null end;

  select min(commission_pct) into v_earned from public.commission_tiers t
    where t.mower_id is not distinct from v_scope
      and t.active
      and coalesce(v_jobs, 0)    >= t.min_jobs
      and coalesce(v_rating, 0)  >= t.min_rating
      and coalesce(v_reviews, 0) >= t.min_reviews;

  -- Best (lowest) of the override/default base and the earned tier.
  return least(v_base, coalesce(v_earned, v_base));
end;
$func$;

-- The signed-in mower's commission standing + progress to the next reduction.
create or replace function public.mower_commission_status()
returns jsonb language plpgsql stable security definer set search_path = public as $func$
declare
  v_me uuid := auth.uid();
  v_jobs int; v_rating numeric; v_reviews int;
  v_effective numeric; v_current_name text; v_scope uuid;
  v_next jsonb;
  n record;
begin
  if v_me is null then raise exception 'Not signed in'; end if;

  select jobs_completed, rating_avg, review_count
    into v_jobs, v_rating, v_reviews from public.mower_stats(v_me);
  v_effective := public.mower_commission(v_me);

  -- Same ladder scope as mower_commission: own tiers if any, else global.
  v_scope := case
    when exists (select 1 from public.commission_tiers where mower_id = v_me)
    then v_me else null end;

  -- Name the best tier the mower currently qualifies for (if any).
  select name into v_current_name from public.commission_tiers t
    where t.mower_id is not distinct from v_scope
      and t.active
      and coalesce(v_jobs, 0)    >= t.min_jobs
      and coalesce(v_rating, 0)  >= t.min_rating
      and coalesce(v_reviews, 0) >= t.min_reviews
    order by commission_pct asc limit 1;

  -- Next reduction = the closest active tier below the current effective rate.
  select * into n from public.commission_tiers t
    where t.mower_id is not distinct from v_scope
      and t.active and t.commission_pct < v_effective
    order by t.commission_pct desc limit 1;

  if found then
    v_next := jsonb_build_object(
      'name',           n.name,
      'commission_pct', n.commission_pct,
      'min_jobs',       n.min_jobs,
      'min_rating',     n.min_rating,
      'min_reviews',    n.min_reviews,
      'jobs_needed',    greatest(0, n.min_jobs    - coalesce(v_jobs, 0)),
      'rating_needed',  greatest(0, n.min_rating  - coalesce(v_rating, 0)),
      'reviews_needed', greatest(0, n.min_reviews - coalesce(v_reviews, 0))
    );
  else
    v_next := null;
  end if;

  return jsonb_build_object(
    'commission_pct', v_effective,
    'jobs_completed', coalesce(v_jobs, 0),
    'rating_avg',     v_rating,
    'review_count',   coalesce(v_reviews, 0),
    'current_tier',   v_current_name,
    'next_tier',      v_next
  );
end;
$func$;
grant execute on function public.mower_commission_status() to authenticated;

-- ===========================================================================
-- 4. Route existing reads through the earned commission.
-- ===========================================================================
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
    'auto_allocate',           coalesce(p.auto_allocate, false),
    'commission_pct',          public.mower_commission(p.id),
    'default_commission_pct',  coalesce(r.default_commission_pct, 15)
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.pricing_rules r on r.id = 1
  where p.id = auth.uid();
$func$;
grant execute on function public.mower_account() to authenticated;

-- ===========================================================================
-- 5. Admin CRUD for the ladder (mirrors admin_*_discount).
-- ===========================================================================
-- p_mower_id NULL → the global default ladder; a mower id → that mower's own.
create or replace function public.admin_list_commission_tiers(p_mower_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $func$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'mower_id', mower_id, 'name', name, 'min_jobs', min_jobs,
    'min_rating', min_rating, 'min_reviews', min_reviews,
    'commission_pct', commission_pct, 'active', active)
    order by commission_pct desc), '[]'::jsonb)
    into v from public.commission_tiers
    where mower_id is not distinct from p_mower_id;
  return v;
end;
$func$;
grant execute on function public.admin_list_commission_tiers(uuid) to authenticated;

create or replace function public.admin_save_commission_tier(
  p_name text, p_min_jobs int, p_min_rating numeric, p_min_reviews int,
  p_commission_pct numeric, p_active boolean default true,
  p_mower_id uuid default null, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $func$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_commission_pct < 0 or p_commission_pct > 100 then
    raise exception 'Commission must be between 0 and 100';
  end if;
  if p_id is null then
    -- New tier: scoped global (p_mower_id null) or to one mower.
    insert into public.commission_tiers
      (mower_id, name, min_jobs, min_rating, min_reviews, commission_pct, active)
      values (p_mower_id, p_name, greatest(0, p_min_jobs), greatest(0, p_min_rating),
              greatest(0, p_min_reviews), p_commission_pct, coalesce(p_active, true))
      returning id into v_id;
  else
    -- Edit: scope (mower_id) is fixed by the row; only the values change.
    update public.commission_tiers set
      name = p_name, min_jobs = greatest(0, p_min_jobs),
      min_rating = greatest(0, p_min_rating), min_reviews = greatest(0, p_min_reviews),
      commission_pct = p_commission_pct, active = coalesce(p_active, true)
      where id = p_id returning id into v_id;
  end if;
  return v_id;
end;
$func$;
grant execute on function public.admin_save_commission_tier(text, int, numeric, int, numeric, boolean, uuid, uuid)
  to authenticated;

create or replace function public.admin_delete_commission_tier(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  delete from public.commission_tiers where id = p_id;
  return true;
end;
$func$;
grant execute on function public.admin_delete_commission_tier(uuid) to authenticated;
