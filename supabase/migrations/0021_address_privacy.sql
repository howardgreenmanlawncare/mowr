-- MOWR — Withhold the exact address until the mower is on the way
--
-- Anti-circumvention: a mower who accepts a job for tomorrow should NOT be able
-- to see the exact property and just turn up off-app. Until they mark themselves
-- en route, they see only the POSTCODE — no street line, no exact lat/lng, no
-- access notes. The moment status becomes 'en_route' (or later) the full address
-- and pin unlock so "Take me there" works.
--
-- Enforced server-side (not just hidden in the app): the street/coords never
-- leave the database until the gate opens. The customer always sees their own
-- property regardless of status. Run after 0020.
--
-- Unlock gate (reused below): the caller is the booking's customer, OR the job
-- is en route or beyond.
--   b.customer_id = auth.uid()
--   OR b.status in ('en_route','arrived','in_progress','completed')

-- 1. Job lists (available_jobs / my_jobs / my_job_history all call this).
create or replace function public._job_json(where_clause text)
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare result jsonb;
begin
  execute format($q$
    select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) from (
      select b.id as booking_id, b.status, b.created_at, b.scheduled_date,
             b.asap, b.time_window, b.access_provided, b.total_amount,
             b.mower_amount, b.commission_amount,
             case when b.customer_id = auth.uid()
                   or b.status in ('en_route','arrived','in_progress','completed')
                  then p.line1 else null end as line1,
             case when b.customer_id = auth.uid()
                   or b.status in ('en_route','arrived','in_progress','completed')
                  then p.city else null end as city,
             p.postcode,
             case when b.customer_id = auth.uid()
                   or b.status in ('en_route','arrived','in_progress','completed')
                  then p.lat else null end as lat,
             case when b.customer_id = auth.uid()
                   or b.status in ('en_route','arrived','in_progress','completed')
                  then p.lng else null end as lng,
             case when b.customer_id = auth.uid()
                   or b.status in ('en_route','arrived','in_progress','completed')
                  then p.access_notes else null end as access_notes,
             (select count(*) from booking_lawns bl where bl.booking_id = b.id) as lawn_count,
             (select coalesce(sum(la.area_sqm), 0) from booking_lawns bl
                join lawn_areas la on la.id = bl.lawn_area_id
              where bl.booking_id = b.id) as total_area
      from bookings b join properties p on p.id = b.property_id
      where %s
      order by b.created_at desc
    ) t
  $q$, where_clause) into result;
  return result;
end;
$func$;

-- 2. Job detail — same gate. Customer keeps full access to their own property.
create or replace function public.job_detail(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare result jsonb;
begin
  select to_jsonb(x) into result from (
    select b.id as booking_id, b.status, b.asap, b.scheduled_date, b.time_window,
           b.access_provided, b.total_amount, b.payment_status,
           b.revised_total, b.approval_status,
           b.captured_amount, b.mower_amount, b.commission_amount,
           coalesce(mp.commission_pct, pr.default_commission_pct, 15) as commission_pct,
           (b.customer_id = auth.uid()
             or b.status in ('en_route','arrived','in_progress','completed'))
             as address_unlocked,
           case when b.customer_id = auth.uid()
                 or b.status in ('en_route','arrived','in_progress','completed')
                then p.line1 else null end as line1,
           case when b.customer_id = auth.uid()
                 or b.status in ('en_route','arrived','in_progress','completed')
                then p.city else null end as city,
           p.postcode,
           case when b.customer_id = auth.uid()
                 or b.status in ('en_route','arrived','in_progress','completed')
                then p.lat else null end as lat,
           case when b.customer_id = auth.uid()
                 or b.status in ('en_route','arrived','in_progress','completed')
                then p.lng else null end as lng,
           case when b.customer_id = auth.uid()
                 or b.status in ('en_route','arrived','in_progress','completed')
                then p.access_notes else null end as access_notes,
           case when b.customer_id = auth.uid()
                 or b.status in ('en_route','arrived','in_progress','completed')
                then p.access_presets else null end as access_presets,
           (select coalesce(jsonb_agg(jsonb_build_object(
                'lawn_area_id', bl.lawn_area_id,
                'name', la.name,
                'area_sqm', la.area_sqm,
                'perimeter', la.perimeter,
                'revised_area_sqm', bl.revised_area_sqm,
                'revised_perimeter', bl.revised_perimeter,
                'grass_height', bl.grass_height,
                'edging', bl.edging)), '[]'::jsonb)
            from booking_lawns bl join lawn_areas la on la.id = bl.lawn_area_id
            where bl.booking_id = b.id) as lawns
    from bookings b
      join properties p on p.id = b.property_id
      left join profiles mp on mp.id = b.mower_id
      left join pricing_rules pr on pr.id = 1
    where b.id = p_booking_id
      and (b.mower_id = auth.uid() or b.customer_id = auth.uid())
  ) x;
  return result;
end;
$func$;
grant execute on function public.job_detail(uuid) to authenticated;
