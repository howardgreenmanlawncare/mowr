-- MOWR — On-site re-measure + reprice (Increment 2b)
-- Lets the assigned mower correct the lawn measurements on arrival. The price is
-- recomputed SERVER-SIDE from pricing_rules (never trust a client amount for
-- money), then compared to the held amount:
--   * revised <= hold                 -> capture the lower amount (partial capture)
--   * revised  > hold, within limit   -> capture hold + auto off-session top-up
--   * revised  > hold, over the limit -> needs customer approval before capture
-- The "limit" is an admin-editable percentage. Run in the Supabase SQL editor.

-- ---------------------------------------------------------------------------
-- 1. Admin-editable auto-approve threshold (percent). Lives on the single
--    pricing_rules row so it changes with the rest of the pricing config.
-- ---------------------------------------------------------------------------
alter table public.pricing_rules
  add column if not exists revise_auto_threshold_pct numeric(6,3) not null default 5;

-- ---------------------------------------------------------------------------
-- 2. Booking-level revision state.
-- ---------------------------------------------------------------------------
alter table public.bookings
  add column if not exists revised_total   numeric(10,2),
  add column if not exists revised_at      timestamptz,
  add column if not exists captured_amount numeric(10,2),
  add column if not exists approval_status text
    check (approval_status in ('not_required','pending','approved','declined'))
    default 'not_required';

-- ---------------------------------------------------------------------------
-- 3. Per-lawn revised measurements (snapshot for THIS visit; the property's
--    permanent lawn_areas row is left untouched).
-- ---------------------------------------------------------------------------
alter table public.booking_lawns
  add column if not exists revised_area_sqm  numeric(10,2),
  add column if not exists revised_perimeter numeric(10,2);

-- ---------------------------------------------------------------------------
-- 4. Re-measure + reprice. Only the assigned mower may call it. Recomputes the
--    total with the SAME formula as the client PricingEngine (one turn-up + one
--    minimum per visit, per-lawn height multiplier, edging on chosen lawns).
--    p_lawns = [{"lawn_area_id":"..","area_sqm":123.4,"perimeter":45.6}, ...]
-- ---------------------------------------------------------------------------
create or replace function public.revise_job_measurements(
  p_booking_id uuid,
  p_lawns      jsonb
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

  -- Apply the incoming revised measurements onto the per-visit snapshot columns.
  update public.booking_lawns bl2
     set revised_area_sqm  = (e.item->>'area_sqm')::numeric,
         revised_perimeter = (e.item->>'perimeter')::numeric
    from jsonb_array_elements(p_lawns) as e(item)
   where bl2.booking_id = p_booking_id
     and bl2.lawn_area_id = (e.item->>'lawn_area_id')::uuid;

  -- Recompute from the (possibly revised) measurements.
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

  if v_delta <= 0 then
    v_status := 'not_required';        -- lower / equal: capture the lower amount
  elsif v_pct <= v_threshold then
    v_status := 'not_required';        -- small rise: auto top-up on capture
  else
    v_status := 'pending';             -- big rise: needs customer approval
  end if;

  update public.bookings
     set revised_total   = v_total,
         revised_at      = now(),
         approval_status = v_status
   where id = p_booking_id;

  return jsonb_build_object(
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
grant execute on function public.revise_job_measurements(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Customer responds to an over-threshold increase. (UI comes later; this is
--    the backend so capture-payment can respect the decision.)
-- ---------------------------------------------------------------------------
create or replace function public.respond_to_revision(p_booking_id uuid, p_approve boolean)
returns boolean language plpgsql security definer set search_path = public
as $func$
declare updated int;
begin
  update public.bookings
     set approval_status = case when p_approve then 'approved' else 'declined' end
   where id = p_booking_id and customer_id = auth.uid()
     and approval_status = 'pending';
  get diagnostics updated = row_count;
  return updated = 1;
end;
$func$;
grant execute on function public.respond_to_revision(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. job_detail now also returns the revision state + per-lawn revised values.
-- ---------------------------------------------------------------------------
create or replace function public.job_detail(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare result jsonb;
begin
  select to_jsonb(x) into result from (
    select b.id as booking_id, b.status, b.asap, b.scheduled_date, b.time_window,
           b.access_provided, b.total_amount, b.payment_status,
           b.revised_total, b.approval_status,
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
    from bookings b join properties p on p.id = b.property_id
    where b.id = p_booking_id
      and (b.mower_id = auth.uid() or b.customer_id = auth.uid())
  ) x;
  return result;
end;
$func$;
grant execute on function public.job_detail(uuid) to authenticated;
