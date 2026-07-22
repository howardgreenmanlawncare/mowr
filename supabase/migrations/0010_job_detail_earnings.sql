-- MOWR — Show the mower their earnings on a job
-- job_detail now returns the mower's commission rate and the settled amounts so
-- the app can show "Job total / MOWR fee / You earn". Run in the SQL editor.

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
           p.line1, p.city, p.postcode, p.lat, p.lng,
           p.access_notes, p.access_presets,
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
