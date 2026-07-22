-- MOWR — Re-measure override (Increment 2b, follow-up)
-- Adds a second outcome to the on-site re-measure: the mower can KEEP this
-- visit's price as booked but correct the property's saved lawn size so FUTURE
-- bookings are priced right. Run in the Supabase SQL editor.
--
-- revise_job_measurements now takes a mode:
--   'reprice'   (default) — reprice THIS visit; permanent lawn untouched.
--   'next_time'           — charge this visit as booked; write the corrected
--                           area/perimeter to the property's lawn_areas rows.

-- The signature changes (extra arg), so drop the old 2-arg version first.
drop function if exists public.revise_job_measurements(uuid, jsonb);

create or replace function public.revise_job_measurements(
  p_booking_id uuid,
  p_lawns      jsonb,
  p_mode       text default 'reprice'
)
returns jsonb language plpgsql security definer set search_path = public
as $func$
declare
  v_booking   public.bookings%rowtype;
  r           public.pricing_rules%rowtype;
  v_mow_raw   numeric := 0;
  v_edge_raw  numeric := 0;
  v_mow_sub   numeric := 0;
  v_edge_sub  numeric := 0;
  v_has_mow   boolean := false;
  v_has_edge  boolean := false;
  v_total     numeric;
  v_original  numeric;
  v_delta     numeric;
  v_pct       numeric;
  v_threshold numeric;
  v_status    text;
  v_mult      numeric;
  bl          record;
begin
  select * into v_booking from public.bookings
    where id = p_booking_id and mower_id = auth.uid();
  if not found then
    raise exception 'Not your job';
  end if;

  select * into r from public.pricing_rules where id = 1;

  -- Record the corrected measurements on the per-visit snapshot (either mode).
  update public.booking_lawns bl2
     set revised_area_sqm  = (e.item->>'area_sqm')::numeric,
         revised_perimeter = (e.item->>'perimeter')::numeric
    from jsonb_array_elements(p_lawns) as e(item)
   where bl2.booking_id = p_booking_id
     and bl2.lawn_area_id = (e.item->>'lawn_area_id')::uuid;

  -- Reprice from the (revised) measurements — same formula as the app.
  for bl in
    select b2.grass_height, b2.edging,
           coalesce(b2.revised_area_sqm,  la.area_sqm)  as area,
           coalesce(b2.revised_perimeter, la.perimeter) as perimeter
      from public.booking_lawns b2
      join public.lawn_areas la on la.id = b2.lawn_area_id
     where b2.booking_id = p_booking_id
  loop
    v_has_mow := true;
    v_mult := case bl.grass_height
                when 'low'  then r.height_mult_low
                when 'high' then r.height_mult_high
                else r.height_mult_medium end;
    v_mow_raw := v_mow_raw + r.mow_rate_per_sqm * bl.area * v_mult;
    if bl.edging then
      v_has_edge := true;
      v_edge_raw := v_edge_raw + r.edge_rate_per_metre * bl.perimeter;
    end if;
  end loop;

  if v_has_mow then
    v_mow_sub := greatest(r.mow_turn_up + v_mow_raw, r.mow_minimum);
  end if;
  if v_has_edge then
    v_edge_sub := greatest(r.edge_turn_up + v_edge_raw, r.edge_minimum);
  end if;

  v_total     := round(v_mow_sub + v_edge_sub, 2);
  v_original  := coalesce(v_booking.total_amount, v_total);
  v_delta     := round(v_total - v_original, 2);
  v_threshold := coalesce(r.revise_auto_threshold_pct, 5);
  if v_original > 0 then
    v_pct := round((v_delta / v_original) * 100, 2);
  else
    v_pct := 0;
  end if;

  if p_mode = 'next_time' then
    -- Persist the corrected size to the property's PERMANENT lawns so future
    -- bookings price correctly. Only lawns in this booking are touched.
    update public.lawn_areas la
       set area_sqm  = (e.item->>'area_sqm')::numeric,
           perimeter = (e.item->>'perimeter')::numeric
      from jsonb_array_elements(p_lawns) as e(item),
           public.booking_lawns bl2
     where bl2.booking_id = p_booking_id
       and bl2.lawn_area_id = (e.item->>'lawn_area_id')::uuid
       and la.id = bl2.lawn_area_id;

    -- This visit stays as booked: no reprice, nothing to approve.
    update public.bookings
       set revised_total   = null,
           revised_at      = now(),
           approval_status = 'not_required'
     where id = p_booking_id;

    return jsonb_build_object(
      'mode',              'next_time',
      'original_total',    v_original,
      'revised_total',     v_total,
      'delta',             v_delta,
      'pct',               v_pct,
      'threshold_pct',     v_threshold,
      'approval_status',   'not_required',
      'requires_approval', false
    );
  end if;

  -- Default: reprice THIS visit; the permanent lawn is left untouched.
  if v_delta <= 0 then
    v_status := 'not_required';
  elsif v_pct <= v_threshold then
    v_status := 'not_required';
  else
    v_status := 'pending';
  end if;

  update public.bookings
     set revised_total   = v_total,
         revised_at      = now(),
         approval_status = v_status
   where id = p_booking_id;

  return jsonb_build_object(
    'mode',              'reprice',
    'original_total',    v_original,
    'revised_total',     v_total,
    'delta',             v_delta,
    'pct',               v_pct,
    'threshold_pct',     v_threshold,
    'approval_status',   v_status,
    'requires_approval', v_status = 'pending'
  );
end;
$func$;
grant execute on function public.revise_job_measurements(uuid, jsonb, text) to authenticated;
