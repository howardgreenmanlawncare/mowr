-- MOWR — Mower dashboard stats
-- Adds a completion timestamp and a single stats RPC for the mower's home
-- dashboard (today's earnings/jobs, this week, available count, active job).
-- Run in the Supabase SQL editor.

alter table public.bookings
  add column if not exists completed_at timestamptz;

-- Backfill so existing completed jobs still count in "this week" / lifetime
-- (best-effort: use revised_at or created_at as an approximate completion time).
update public.bookings
   set completed_at = coalesce(revised_at, created_at)
 where status = 'completed' and completed_at is null;

create or replace function public.mower_dashboard()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare
  v_uid            uuid := auth.uid();
  v_tz             text := 'Europe/London';
  v_today          date := (now() at time zone v_tz)::date;
  v_available      int := 0;
  v_today_earnings numeric := 0;
  v_today_jobs     int := 0;
  v_week_earnings  numeric := 0;
  v_active         jsonb;
begin
  if public.is_approved_mower() then
    select count(*) into v_available
      from public.bookings
     where status = 'confirmed' and mower_id is null;
  end if;

  select coalesce(sum(mower_amount), 0), count(*)
    into v_today_earnings, v_today_jobs
    from public.bookings
   where mower_id = v_uid and status = 'completed'
     and completed_at is not null
     and (completed_at at time zone v_tz)::date = v_today;

  select coalesce(sum(mower_amount), 0)
    into v_week_earnings
    from public.bookings
   where mower_id = v_uid and status = 'completed'
     and completed_at is not null
     and completed_at >= now() - interval '7 days';

  select to_jsonb(a) into v_active from (
    select b.id as booking_id, b.status, p.line1, p.city, p.postcode
      from public.bookings b
      join public.properties p on p.id = b.property_id
     where b.mower_id = v_uid
       and b.status in ('accepted', 'en_route', 'arrived', 'in_progress')
     order by b.created_at desc
     limit 1
  ) a;

  return jsonb_build_object(
    'available_count', v_available,
    'today_earnings',  round(v_today_earnings, 2),
    'today_jobs',      v_today_jobs,
    'week_earnings',   round(v_week_earnings, 2),
    'active',          v_active
  );
end;
$func$;
grant execute on function public.mower_dashboard() to authenticated;
