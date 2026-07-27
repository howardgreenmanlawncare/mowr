-- MOWR — Weather-aware scheduling.
--
-- Traditional gardeners lose a whole week when their fixed day rains off. MOWR
-- doesn't: a nightly sweep (edge function `weather-sweep`, keyless Open-Meteo)
-- reads the forecast for each upcoming job's property and:
--   * flags each job dry / rain-risk (mowrs can then pick up dry work nearby
--     when their own area is wet);
--   * moves a rained-off job to the next dry day rather than skipping a week
--     (recurring jobs auto-move; one-offs are flagged + the customer nudged).
--
-- This migration adds the columns + the RPCs the edge function calls. The edge
-- function uses the service-role key, so these SECURITY DEFINER RPCs are NOT
-- granted to `authenticated` (except the read the mowr app needs).
--
-- Run after 0026. (MCP was read-only when written — apply pending.)

alter table public.bookings
  add column if not exists rain_risk          boolean,
  add column if not exists weather_status      text,   -- null | 'clear' | 'rain_risk' | 'moved'
  add column if not exists weather_note         text,
  add column if not exists weather_moved_from   date,
  add column if not exists weather_checked_at   timestamptz;

-- Edge writes the forecast result for a job.
create or replace function public.set_job_weather(
  p_booking_id uuid, p_rain_risk boolean,
  p_status text default null, p_note text default null)
returns void language sql security definer set search_path = public as $func$
  update public.bookings
     set rain_risk = p_rain_risk,
         weather_status = coalesce(p_status, case when p_rain_risk then 'rain_risk' else 'clear' end),
         weather_note = p_note,
         weather_checked_at = now()
   where id = p_booking_id
     and status not in ('completed','cancelled','expired');
$func$;

-- Move a rained-off job to the next dry day. Records where it moved from,
-- returns it to the pool so the preference-aware allocator re-picks for the new
-- day, and emails the customer.
create or replace function public.weather_reschedule(
  p_booking_id uuid, p_new_date date, p_note text default null)
returns void language plpgsql security definer set search_path = public as $func$
declare v_old date; v_status text;
begin
  select scheduled_date, status into v_old, v_status
    from public.bookings where id = p_booking_id;
  if v_status is null or v_status in ('completed','cancelled','expired') then return; end if;

  update public.bookings
     set scheduled_date     = p_new_date,
         asap               = false,
         weather_status     = 'moved',
         weather_moved_from = coalesce(weather_moved_from, v_old),
         weather_note       = p_note,
         rain_risk          = false,
         weather_checked_at = now(),
         -- if it was already assigned/accepted, release it so the new day is
         -- re-allocated cleanly (auto-accept flag cleared)
         mower_id      = case when status in ('accepted') then null else mower_id end,
         auto_allocated = case when status in ('accepted') then false else auto_allocated end,
         status        = case when status in ('accepted') then 'confirmed' else status end
   where id = p_booking_id;

  perform public._enqueue(p_booking_id, 'weather_moved',
    'Your mow moved to beat the weather',
    coalesce(p_note,
      'Rain was forecast for your mow, so we''ve moved it to the next dry day '
      || 'rather than making you wait a week. Check the app for the new date.'));
end;
$func$;

-- Mowr-facing read: weather per job they can see (no address / PII), so the
-- app can badge dry vs rain-risk work — handy for picking up dry jobs nearby
-- when a mowr's own area is wet.
create or replace function public.mowr_jobs_weather()
returns jsonb language plpgsql stable security definer set search_path = public as $func$
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
        'booking_id', b.id,
        'rain_risk',  b.rain_risk,
        'note',       b.weather_note
      )), '[]'::jsonb)
    from public.bookings b
    where b.scheduled_date between current_date and current_date + 3
      and b.rain_risk is not null
      and ( b.mower_id = auth.uid()
            or (b.mower_id is null and b.status in ('confirmed','broadcast')) )
  );
end;
$func$;
grant execute on function public.mowr_jobs_weather() to authenticated;

-- Scheduling note: run `weather-sweep` nightly (e.g. 20:00) before the
-- generate/allocate crons, via pg_cron + pg_net (fill in service-role key):
--   select cron.schedule('weather-sweep', '0 20 * * *', $w$
--     select net.http_post(
--       url := 'https://ypbizskokuxpfdyvdgmg.supabase.co/functions/v1/weather-sweep',
--       headers := jsonb_build_object('Authorization','Bearer <SERVICE_ROLE_KEY>',
--                                     'Content-Type','application/json'),
--       body := '{}'::jsonb); $w$);
