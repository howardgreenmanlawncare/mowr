-- MOWR — Night-before fleet allocation
--
-- Assigns the day's unassigned jobs across mowers who opted into
-- auto-allocation, most-efficiently. Server-side mirror of the Dart
-- FleetAllocator (fleet.dart): greedy, hardest-to-place first, each job to the
-- opted-in mower whose day it disturbs least (least added travel; ties → the
-- emptier day so work spreads), honouring window + working-day capacity.
--
-- Per-mower route *sequencing* still happens in-app via schedule.dart; this just
-- decides WHO gets each job. Swap this for an OR-Tools/OSRM worker when greedy
-- isn't enough — the opt-in, availability and nightly hook stay. Run after 0017.

-- 1. Mower opt-in + availability.
alter table public.profiles
  add column if not exists auto_allocate boolean not null default false,
  add column if not exists work_start int not null default 8,
  add column if not exists work_end   int not null default 18;

-- 2. Pure helpers (mirror schedule.dart's constants).
create or replace function public._window_cap(w text)
returns int language sql immutable as $func$
  select case w when 'morning' then 240 when 'afternoon' then 300
                when 'evening' then 180 else 9999 end;
$func$;

create or replace function public._booking_minutes(p_booking uuid)
returns int language sql stable security definer set search_path = public as $func$
  select ceil(coalesce(sum(la.area_sqm),0) / 3.0)::int
       + 10 * greatest(1, count(la.*))::int
  from public.booking_lawns bl
  join public.lawn_areas la on la.id = bl.lawn_area_id
  where bl.booking_id = p_booking;
$func$;

-- Params are double precision to match properties.lat/lng.
create or replace function public._travel_min(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision)
returns int language sql immutable as $func$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then 0
    else round(
      6371 * 2 * asin(sqrt(
        power(sin(radians(lat2-lat1)/2), 2) +
        cos(radians(lat1)) * cos(radians(lat2)) *
        power(sin(radians(lng2-lng1)/2), 2)))
      * 1.3 / 30.0 * 60)::int
  end;
$func$;

-- 3. The allocator. Assigns unassigned confirmed jobs on p_date to opted-in
--    mowers. Returns how many it placed. Idempotent; safe to re-run.
--    Assignments are held in a temp table until the end so a placed job is
--    never double-counted against capacity.
create or replace function public.allocate_jobs_for(p_date date)
returns int language plpgsql security definer set search_path = public as $func$
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
    v_job_min := j.mins; v_win := j.win; v_win_cap := public._window_cap(v_win);
    v_best_mower := null; v_best_travel := null; v_best_load := null;

    for m in
      select pr.id as mower_id, (pr.work_end - pr.work_start) * 60 as day_cap
      from public.profiles pr
      where pr.role = 'mower' and coalesce(pr.auto_allocate,false)
        and coalesce(pr.mower_approved,false)
        and coalesce(pr.connect_onboarded,false)
    loop
      v_day_cap := m.day_cap;

      select coalesce(sum(mins),0) into v_committed_day from (
        select public._booking_minutes(b2.id) as mins from public.bookings b2
          where b2.mower_id = m.mower_id and b2.scheduled_date = p_date
            and b2.status not in ('cancelled','expired')
        union all
        select minutes from _alloc where mower_id = m.mower_id
      ) d;

      select coalesce(sum(mins),0) into v_committed_win from (
        select public._booking_minutes(b2.id) as mins from public.bookings b2
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
        if v_best_mower is null or v_travel < v_best_travel
           or (v_travel = v_best_travel and v_committed_day < v_best_load) then
          v_best_mower := m.mower_id; v_best_travel := v_travel;
          v_best_load := v_committed_day;
        end if;
      end if;
    end loop;

    if v_best_mower is not null then
      insert into _alloc values (j.id, v_best_mower, v_job_min, v_win, j.lat, j.lng);
      v_count := v_count + 1;
    end if;
  end loop;

  update public.bookings b set mower_id = a.mower_id, status = 'accepted'
    from _alloc a where b.id = a.job_id;

  return v_count;
end;
$func$;

-- 4. Mower opt-in / hours from the app.
create or replace function public.set_auto_allocate(
  p_on boolean, p_start int default null, p_end int default null)
returns boolean language plpgsql security definer set search_path = public as $func$
begin
  update public.profiles set
    auto_allocate = p_on,
    work_start = coalesce(p_start, work_start),
    work_end   = coalesce(p_end, work_end)
  where id = auth.uid() and role = 'mower';
  return p_on;
end;
$func$;
grant execute on function public.set_auto_allocate(boolean, int, int) to authenticated;

-- Scheduled (applied 2026-07-24, not re-runnable so kept out of the DDL above):
--   select cron.schedule('allocate-tomorrow','10 6 * * *',
--     $$ select public.allocate_jobs_for((now() at time zone 'Europe/London')::date + 1) $$);
-- Runs 10 min after generate-recurring-occurrences (06:00).
