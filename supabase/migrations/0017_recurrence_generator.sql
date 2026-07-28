-- MOWR — Recurring occurrence generator
--
-- Turns a recurrence choice into actual repeat bookings. A daily cron spawns
-- the next occurrence of each active series a couple of days before it's due
-- ("on the day or the day before"), re-applying any loyalty discount that
-- targets that occurrence number. Run after 0016.

-- Undiscounted price of the mow, so each occurrence's discount is applied to a
-- clean base rather than compounding.
alter table public.bookings add column if not exists base_amount numeric(10,2);
update public.bookings set base_amount = total_amount where base_amount is null;

create or replace function public.generate_recurring_occurrences(p_lead_days int default 2)
returns int language plpgsql security definer set search_path = public as $func$
declare
  v_count int := 0;
  r record;
  v_new uuid;
  v_base numeric;
  v_pct numeric;
  v_total numeric;
  v_next date;
  v_occ int;
begin
  for r in
    select b.*
    from public.bookings b
    where b.recurrence_interval_days > 0
      and b.status <> 'cancelled'
      -- only the latest occurrence in each series can spawn the next
      and b.occurrence_number = (
        select max(b2.occurrence_number)
        from public.bookings b2 where b2.series_id = b.series_id)
      -- and only once the next visit is within the lead window
      and (b.scheduled_date + (b.recurrence_interval_days || ' days')::interval)::date
            <= current_date + p_lead_days
  loop
    v_occ  := r.occurrence_number + 1;
    v_next := (r.scheduled_date + (r.recurrence_interval_days || ' days')::interval)::date;

    -- Base = the series' first (undiscounted) price.
    select coalesce(base_amount, total_amount) into v_base
      from public.bookings where series_id = r.series_id
      order by occurrence_number limit 1;

    -- Best loyalty discount that applies to this occurrence.
    select coalesce(max(percent_off), 0) into v_pct
      from public.discount_rules
     where active
       and (case when ongoing then min_occurrence <= v_occ
                 else min_occurrence = v_occ end);

    v_total := round(v_base * (1 - v_pct / 100), 2);

    insert into public.bookings (
      customer_id, property_id, status, asap, scheduled_date, time_window,
      access_provided, total_amount, base_amount, currency,
      series_id, occurrence_number, recurrence_interval_days, next_occurrence_date)
    values (
      r.customer_id, r.property_id, 'confirmed', false, v_next, r.time_window,
      r.access_provided, v_total, v_base, r.currency,
      r.series_id, v_occ, r.recurrence_interval_days,
      (v_next + (r.recurrence_interval_days || ' days')::interval)::date)
    returning id into v_new;

    insert into public.booking_lawns
      (booking_id, lawn_area_id, grass_height, edging, mow_price, edge_price)
      select v_new, lawn_area_id, grass_height, edging, mow_price, edge_price
      from public.booking_lawns where booking_id = r.id;

    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$func$;

-- Daily at 06:00 Europe/London (cron runs in UTC; 06:00 UTC is close enough for
-- a "day before" generator).
create extension if not exists pg_cron;
select cron.schedule(
  'generate-recurring-occurrences',
  '0 6 * * *',
  $cron$ select public.generate_recurring_occurrences(); $cron$
);
