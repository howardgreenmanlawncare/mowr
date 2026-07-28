-- MOWR — Rough arrival ETA for the customer, sourced from the day's plan
--
-- Gives the customer a "arriving in ~X min" / "expected ~10:30" estimate on the
-- live status tracker, derived the same way the route/schedule planner thinks:
-- the mower's earlier stops that day (job durations from _booking_minutes) plus
-- a rough per-stop travel allowance, from either "now" (if the day is already
-- underway) or the booking's time-window start. Deliberately approximate — it's
-- a heads-up, not a promise. Reuses the 0018 helpers. Run after 0021.
--
-- Scoped so the booking's customer (or the assigned mower) can read it.

create or replace function public.booking_eta(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $func$
declare
  v_mower uuid; v_date date; v_status text; v_win text;
  v_now timestamptz := now();
  v_before int; v_start timestamptz; v_eta timestamptz; v_underway boolean;
  v_wh int;
begin
  select mower_id, scheduled_date, status, coalesce(time_window, 'any')
    into v_mower, v_date, v_status, v_win
  from public.bookings
  where id = p_booking_id
    and (customer_id = auth.uid() or mower_id = auth.uid());

  -- No route ETA before a mower is on it, or once it's finished.
  if v_mower is null or v_date is null then return null; end if;
  if v_status not in ('accepted', 'en_route', 'arrived', 'in_progress') then
    return null;
  end if;

  -- Cumulative work of the mower's earlier stops that day + ~15 min travel each.
  with day_jobs as (
    select b.id, public._booking_minutes(b.id) as mins,
           row_number() over (
             order by public._window_cap(coalesce(b.time_window, 'any')),
                      b.created_at) as ord
    from public.bookings b
    where b.mower_id = v_mower and b.scheduled_date = v_date
      and b.status in ('accepted', 'en_route', 'arrived', 'in_progress')
  ),
  me as (select ord from day_jobs where id = p_booking_id),
  bef as (
    select coalesce(sum(dj.mins), 0) as work, count(*) as stops
    from day_jobs dj, me
    where dj.ord < me.ord
  )
  select work + stops * 15 into v_before from bef;
  v_before := coalesce(v_before, 0);

  v_underway := exists (
    select 1 from public.bookings b
    where b.mower_id = v_mower and b.scheduled_date = v_date
      and b.status in ('en_route', 'arrived', 'in_progress'));

  if v_underway then
    v_start := v_now;
  else
    v_wh := case v_win when 'morning' then 8 when 'afternoon' then 12
                       when 'evening' then 17 else 8 end;
    v_start := greatest(
      v_now,
      (v_date::timestamp + (v_wh || ' hours')::interval) at time zone 'Europe/London');
  end if;

  v_eta := v_start + (v_before || ' minutes')::interval;

  return jsonb_build_object(
    'eta', v_eta,
    'minutes_away', greatest(0, floor(extract(epoch from (v_eta - v_now)) / 60))::int,
    'underway', v_underway
  );
end;
$func$;
grant execute on function public.booking_eta(uuid) to authenticated;
