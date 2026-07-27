-- MOWR — Preferred mowrs: keep the mowr you liked, and get prioritised to them.
--
-- After a completed job the customer can add that mowr to their preferred list.
-- New bookings (one-off or recurring) are then steered to preferred mowrs first
-- by the night-before allocator. When none are free on the wanted date, the app
-- shows each preferred mowr's next available date so the customer can reschedule.
--
-- Run after 0025. (MCP was read-only when written — apply pending.)

-- ---------------------------------------------------------------------------
-- 1. The list.
-- ---------------------------------------------------------------------------
create table if not exists public.preferred_mowrs (
  customer_id uuid not null references public.profiles(id) on delete cascade,
  mowr_id     uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (customer_id, mowr_id)
);
create index if not exists preferred_mowrs_mowr_idx on public.preferred_mowrs(mowr_id);

alter table public.preferred_mowrs enable row level security;
drop policy if exists "prefs: owner" on public.preferred_mowrs;
create policy "prefs: owner" on public.preferred_mowrs for all
  using (customer_id = auth.uid()) with check (customer_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Add / remove / list (customer-scoped).
-- ---------------------------------------------------------------------------
-- Add is anchored to a completed job, so a customer can only prefer a mowr who
-- actually did work for them.
create or replace function public.add_preferred_mowr(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $func$
declare v_mowr uuid; v_name text;
begin
  select b.mower_id into v_mowr
    from public.bookings b
   where b.id = p_booking_id and b.customer_id = auth.uid()
     and b.status = 'completed' and b.mower_id is not null;
  if v_mowr is null then
    raise exception 'Only a completed job with an assigned mowr can be preferred';
  end if;

  insert into public.preferred_mowrs (customer_id, mowr_id)
    values (auth.uid(), v_mowr) on conflict do nothing;

  select coalesce(full_name, 'Your mowr') into v_name
    from public.profiles where id = v_mowr;
  return jsonb_build_object('mowr_id', v_mowr, 'full_name', v_name);
end;
$func$;
grant execute on function public.add_preferred_mowr(uuid) to authenticated;

create or replace function public.remove_preferred_mowr(p_mowr_id uuid)
returns void language sql security definer set search_path = public as $func$
  delete from public.preferred_mowrs
   where customer_id = auth.uid() and mowr_id = p_mowr_id;
$func$;
grant execute on function public.remove_preferred_mowr(uuid) to authenticated;

create or replace function public.list_preferred_mowrs()
returns jsonb language plpgsql stable security definer set search_path = public as $func$
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
        'mowr_id', pm.mowr_id,
        'full_name', coalesce(pr.full_name, 'Your mowr'),
        'jobs', (select count(*) from public.bookings b
                  where b.customer_id = auth.uid() and b.mower_id = pm.mowr_id
                    and b.status = 'completed')
      ) order by pr.full_name), '[]'::jsonb)
    from public.preferred_mowrs pm
    join public.profiles pr on pr.id = pm.mowr_id
    where pm.customer_id = auth.uid()
  );
end;
$func$;
grant execute on function public.list_preferred_mowrs() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Next available date for each preferred mowr (capacity-based).
--    A mowr is "available" on a date while their committed minutes are under
--    their working-day capacity. Returns the first free date in the window.
-- ---------------------------------------------------------------------------
create or replace function public.preferred_mowr_availability(
  p_from date default current_date, p_days int default 21)
returns jsonb language plpgsql stable security definer set search_path = public as $func$
declare v_from date := greatest(coalesce(p_from, current_date), current_date);
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
        'mowr_id', pm.mowr_id,
        'full_name', coalesce(pr.full_name, 'Your mowr'),
        'next_available', (
          select d::date
          from generate_series(v_from, v_from + (greatest(1, p_days) || ' days')::interval, interval '1 day') d
          where coalesce((
                  select sum(public._booking_minutes(b.id))
                  from public.bookings b
                  where b.mower_id = pm.mowr_id and b.scheduled_date = d::date
                    and b.status not in ('cancelled','expired')
                ), 0)
                < ((coalesce(pr.work_end, 17) - coalesce(pr.work_start, 8)) * 60)
          order by d limit 1
        )
      ) order by pr.full_name), '[]'::jsonb)
    from public.preferred_mowrs pm
    join public.profiles pr on pr.id = pm.mowr_id
    where pm.customer_id = auth.uid()
      and coalesce(pr.mower_approved, false)
      and coalesce(pr.connect_onboarded, false)
  );
end;
$func$;
grant execute on function public.preferred_mowr_availability(date, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Allocator prefers the customer's preferred mowrs.
--    Same greedy engine as 0023, but for each job it keeps a best-fitting
--    PREFERRED candidate as well; if one fits it wins over the overall best.
-- ---------------------------------------------------------------------------
create or replace function public.allocate_jobs_for(p_date date)
returns integer language plpgsql security definer set search_path = public
as $function$
declare
  j record; m record;
  v_job_min int; v_win text; v_win_cap int; v_day_cap int;
  v_committed_day int; v_committed_win int; v_travel int;
  v_best_mower uuid; v_best_travel int; v_best_load int;
  v_pref_mower uuid; v_pref_travel int; v_pref_load int;
  v_is_pref boolean;
  v_count int := 0;
begin
  create temp table if not exists _alloc(
    job_id uuid, mower_id uuid, minutes int, win text, lat numeric, lng numeric
  ) on commit drop;
  delete from _alloc;

  for j in
    select b.id, b.customer_id, coalesce(b.time_window,'any') as win, p.lat, p.lng,
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
    v_pref_mower := null; v_pref_travel := null; v_pref_load := null;

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
        -- best overall
        if v_best_mower is null
           or v_travel < v_best_travel
           or (v_travel = v_best_travel and v_committed_day < v_best_load) then
          v_best_mower := m.mower_id;
          v_best_travel := v_travel;
          v_best_load := v_committed_day;
        end if;
        -- best among this customer's preferred mowrs
        v_is_pref := exists (
          select 1 from public.preferred_mowrs pm
          where pm.customer_id = j.customer_id and pm.mowr_id = m.mower_id);
        if v_is_pref and (v_pref_mower is null
           or v_travel < v_pref_travel
           or (v_travel = v_pref_travel and v_committed_day < v_pref_load)) then
          v_pref_mower := m.mower_id;
          v_pref_travel := v_travel;
          v_pref_load := v_committed_day;
        end if;
      end if;
    end loop;

    -- Prefer a preferred mowr when one fits; otherwise the least-disruptive mowr.
    if v_pref_mower is not null then
      insert into _alloc values (j.id, v_pref_mower, v_job_min, v_win, j.lat, j.lng);
      v_count := v_count + 1;
    elsif v_best_mower is not null then
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