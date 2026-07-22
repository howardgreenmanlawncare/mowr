-- MOWR — expose settled earnings on job lists
-- _job_json now includes the mower's payout + commission so the History tab can
-- show what the mower actually earned. Run in the Supabase SQL editor.

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
             p.line1, p.city, p.postcode, p.lat, p.lng, p.access_notes,
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
