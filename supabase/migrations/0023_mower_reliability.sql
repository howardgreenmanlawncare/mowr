-- MOWR — Auto-accept reliability: track & flag refused auto-allocated jobs
--
-- A mower who opts into auto-allocation is telling us "fill my day, I'll do
-- what you assign". If they then bin those auto-assigned jobs, that's a
-- customer-reliability problem. So: mark auto-allocated jobs, let a mower
-- release one before they start it, record each release as a refusal, and if
-- they refuse too many in a rolling window, auto-pause their auto-accept and
-- flag it for admin. Manually-accepted jobs can still be released, but that
-- doesn't count as a refusal — the concern is specifically auto-accept. Run
-- after 0022.

-- 1. Mark which bookings were auto-allocated (vs manually accepted).
alter table public.bookings
  add column if not exists auto_allocated boolean not null default false;

-- 2. Refusal log.
create table if not exists public.mower_job_refusals (
  id         uuid primary key default gen_random_uuid(),
  mower_id   uuid not null references public.profiles(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,
  reason     text,
  created_at timestamptz not null default now()
);
create index if not exists mower_job_refusals_mower_idx
  on public.mower_job_refusals(mower_id, created_at desc);

alter table public.mower_job_refusals enable row level security;
drop policy if exists "refusals: own or admin" on public.mower_job_refusals;
create policy "refusals: own or admin"
  on public.mower_job_refusals for select
  using (mower_id = auth.uid() or public.is_admin());

-- 3. Rolling refusal count for a mower.
create or replace function public.mower_refusal_count(p_mower uuid, p_days int default 30)
returns int language sql stable security definer set search_path = public as $func$
  select count(*)::int from public.mower_job_refusals
   where mower_id = p_mower
     and created_at >= now() - make_interval(days => greatest(1, p_days));
$func$;

-- 4. The allocator now stamps auto_allocated = true on the jobs it assigns.
create or replace function public.allocate_jobs_for(p_date date)
returns integer language plpgsql security definer set search_path = public
as $function$
declare
  j record; m record;
  v_job_min int; v_win text; v_win_cap int; v_day_cap int;
  v_committed_day int; v_committed_win int; v_travel int;
  v_best_mower uuid; v_best_travel int; v_best_load int;
  v_count int := 0;
begin
  create temp table if not exists _alloc(
    job_id uuid, mower_id uuid, minutes int, win text, lat numeric, lng numeric
  ) on commit drop;
  delete from _alloc;

  for j in
    select b.id, coalesce(b.time_window,'any') as win, p.lat, p.lng,
           public._booking_minutes(b.id) as mins
    from public.bookings b
    join public.properties p on p.id = b.property_id
    where b.status = 'confirmed' and b.mower_id is null
      and b.scheduled_date = p_date
    order by public._window_cap(coalesce(b.time_window,'any')) asc,
             public._booking_minutes(b.id) desc
  loop
    v_job_min := j.mins;
    v_win := j.win;
    v_win_cap := public._window_cap(v_win);
    v_best_mower := null; v_best_travel := null; v_best_load := null;

    for m in
      select pr.id as mower_id,
             (pr.work_end - pr.work_start) * 60 as day_cap
      from public.profiles pr
      where pr.role = 'mower' and coalesce(pr.auto_allocate,false)
        and coalesce(pr.mower_approved,false)
        and coalesce(pr.connect_onboarded,false)
    loop
      v_day_cap := m.day_cap;

      select coalesce(sum(mins),0) into v_committed_day from (
        select public._booking_minutes(b2.id) as mins
          from public.bookings b2
          where b2.mower_id = m.mower_id and b2.scheduled_date = p_date
            and b2.status not in ('cancelled','expired')
        union all
        select minutes from _alloc where mower_id = m.mower_id
      ) d;

      select coalesce(sum(mins),0) into v_committed_win from (
        select public._booking_minutes(b2.id) as mins
          from public.bookings b2
          where b2.mower_id = m.mower_id and b2.scheduled_date = p_date
            and b2.status not in ('cancelled','expired')
            and coalesce(b2.time_window,'any') = v_win
        union all
        select minutes from _alloc where mower_id = m.mower_id and win = v_win
      ) w;

      select coalesce(min(public._travel_min(j.lat, j.lng, s.lat, s.lng)), 0)
        into v_travel from (
          select p2.lat, p2.lng from public.bookings b2
            join public.properties p2 on p2.id = b2.property_id
            where b2.mower_id = m.mower_id and b2.scheduled_date = p_date
              and b2.status not in ('cancelled','expired')
          union all
          select lat, lng from _alloc where mower_id = m.mower_id
        ) s;

      if v_committed_win + v_job_min + v_travel <= v_win_cap
         and v_committed_day + v_job_min + v_travel <= v_day_cap then
        if v_best_mower is null
           or v_travel < v_best_travel
           or (v_travel = v_best_travel and v_committed_day < v_best_load) then
          v_best_mower := m.mower_id;
          v_best_travel := v_travel;
          v_best_load := v_committed_day;
        end if;
      end if;
    end loop;

    if v_best_mower is not null then
      insert into _alloc values (j.id, v_best_mower, v_job_min, v_win, j.lat, j.lng);
      v_count := v_count + 1;
    end if;
  end loop;

  update public.bookings b
    set mower_id = a.mower_id, status = 'accepted', auto_allocated = true
    from _alloc a where b.id = a.job_id;

  return v_count;
end;
$function$;

-- 5. A mower releases a not-yet-started job. Only auto-allocated releases count
--    as refusals; too many in 30 days auto-pauses their auto-accept.
create or replace function public.release_auto_job(
  p_booking_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $func$
declare
  v_status text; v_auto boolean; v_count int := 0; v_paused boolean := false;
  v_threshold int := 3;
begin
  select status, coalesce(auto_allocated, false) into v_status, v_auto
    from public.bookings where id = p_booking_id and mower_id = auth.uid();
  if v_status is null then raise exception 'Not your job'; end if;
  if v_status <> 'accepted' then
    raise exception 'You can only release a job you haven''t started';
  end if;

  -- Back to the pool for the next allocation / another mower to pick up.
  update public.bookings
     set mower_id = null, status = 'confirmed', auto_allocated = false
   where id = p_booking_id;

  if v_auto then
    insert into public.mower_job_refusals (mower_id, booking_id, reason)
      values (auth.uid(), p_booking_id, nullif(trim(p_reason), ''));
    v_count := public.mower_refusal_count(auth.uid(), 30);
    if v_count >= v_threshold then
      update public.profiles set auto_allocate = false where id = auth.uid();
      v_paused := true;
    end if;
  end if;

  return jsonb_build_object(
    'released', true,
    'was_auto', v_auto,
    'refusals_30d', v_count,
    'auto_paused', v_paused,
    'threshold', v_threshold
  );
end;
$func$;
grant execute on function public.release_auto_job(uuid, text) to authenticated;

-- 6. Admin mower list — restore phone_verified + surface auto-accept reliability.
create or replace function public.admin_list_mowers()
returns jsonb language plpgsql stable security definer set search_path = public
as $function$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;

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
      'auto_allocate',      coalesce(p.auto_allocate, false),
      'commission_pct',     p.commission_pct,
      'created_at',         p.created_at,
      'jobs_completed',     (
        select count(*) from public.bookings b
        where b.mower_id = p.id and b.status = 'completed'
      ),
      'refusals_30d',       public.mower_refusal_count(p.id, 30)
    ) as m
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.role = 'mower'
  ) s;

  return v_rows;
end;
$function$;
grant execute on function public.admin_list_mowers() to authenticated;
