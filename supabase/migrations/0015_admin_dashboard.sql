-- MOWR — Admin operations dashboard
--
-- One RPC the admin dashboard calls with a date range (Today / 7 days / 30 days
-- / custom, mirroring the mower earnings filters). Returns everything the admin
-- needs at a glance: job counts by status, revenue, the mower roster, things
-- needing attention, and an upcoming-days breakdown.
--
-- Admin-gated. Run after 0014.

create or replace function public.admin_dashboard(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare
  v_tz  text := 'Europe/London';
  v_jobs jsonb;
  v_revenue jsonb;
  v_mowers jsonb;
  v_attention jsonb;
  v_upcoming jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  -- Jobs scheduled within the range, by status (the operational view).
  select jsonb_build_object(
    'total',           count(*),
    'completed',       count(*) filter (where status = 'completed'),
    'in_progress',     count(*) filter (where status in ('accepted','en_route','arrived','in_progress')),
    'scheduled',       count(*) filter (where status = 'confirmed' and mower_id is not null),
    'awaiting_mower',  count(*) filter (where status = 'confirmed' and mower_id is null),
    'cancelled',       count(*) filter (where status in ('cancelled','expired'))
  ) into v_jobs
  from public.bookings
  where scheduled_date between p_from and p_to;

  -- Money from jobs completed within the range.
  select jsonb_build_object(
    'gross',        round(coalesce(sum(coalesce(captured_amount, total_amount)), 0), 2),
    'commission',   round(coalesce(sum(commission_amount), 0), 2),
    'mower_payout', round(coalesce(sum(mower_amount), 0), 2),
    'jobs',         count(*)
  ) into v_revenue
  from public.bookings
  where status = 'completed'
    and completed_at is not null
    and (completed_at at time zone v_tz)::date between p_from and p_to;

  -- The mower roster (not range-scoped — it's the current picture).
  select jsonb_build_object(
    'total',              count(*),
    'approved',           count(*) filter (where coalesce(mower_approved,false)),
    'active',             count(*) filter (where coalesce(mower_approved,false)
                                             and coalesce(connect_onboarded,false)),
    'awaiting_approval',  count(*) filter (where not coalesce(mower_approved,false))
  ) into v_mowers
  from public.profiles where role = 'mower';

  -- Things needing a human.
  select jsonb_build_object(
    'revision_approvals', (select count(*) from public.bookings where approval_status = 'pending'),
    'unassigned',         (select count(*) from public.bookings where status = 'confirmed' and mower_id is null)
  ) into v_attention;

  -- Next 7 days, jobs per day.
  select coalesce(jsonb_agg(jsonb_build_object('date', d, 'count', c) order by d), '[]'::jsonb)
    into v_upcoming
  from (
    select scheduled_date as d, count(*) as c
    from public.bookings
    where scheduled_date between (now() at time zone v_tz)::date
                             and (now() at time zone v_tz)::date + 6
      and status not in ('cancelled','expired')
    group by scheduled_date
  ) u;

  return jsonb_build_object(
    'range',     jsonb_build_object('from', p_from, 'to', p_to),
    'jobs',      v_jobs,
    'revenue',   v_revenue,
    'mowers',    v_mowers,
    'attention', v_attention,
    'upcoming',  v_upcoming
  );
end;
$func$;

grant execute on function public.admin_dashboard(date, date) to authenticated;
