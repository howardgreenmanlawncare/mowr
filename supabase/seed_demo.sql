-- MOWR — demo data seed
--
-- Populates realistic properties + bookings so the mower and admin views have
-- something to show: available work, an active multi-stop day (for the route
-- map), and completed history (for earnings + the admin dashboard).
--
-- Safe to re-run: it tags its rows with a marker in access_notes and clears
-- previous demo rows first, so it won't pile up duplicates.
--
-- Assumes the existing accounts from this project:
--   mower    a70fac7b-ed03-41ed-8cc8-c65b08c398cc  (howardmowr@mowr.co.uk)
--   customers: howard / howard2 / howard3 / howard4
-- Run in the Supabase SQL editor.

do $$
declare
  v_mower  uuid := 'a70fac7b-ed03-41ed-8cc8-c65b08c398cc';
  v_custs  uuid[] := array[
    'a121b343-1d34-4626-8ab0-3946853e7188',
    '6db4276d-32a4-4911-ba15-d2cc773e42fc',
    '19256087-6a33-4d7b-93f5-feee98b27f9b',
    'e69c8fcb-4538-4d94-9b90-4daf5fb9d104'
  ];
  v_prop uuid;
  v_lawn uuid;
  v_book uuid;
  v_total numeric;
  v_ci int := 0;
  rec record;
begin
  -- Demo shortcut: make the mower fully live so they see available work and
  -- can accept it (triggers the day-fit sheet). connect_onboarded is faked —
  -- no real Stripe account — which is fine for a demo but never for production.
  update public.profiles
    set mower_approved = true, connect_onboarded = true
    where id = v_mower;

  -- Clear any prior demo rows (tagged in access_notes).
  delete from public.booking_lawns bl using public.bookings b
    where bl.booking_id = b.id and b.property_id in
      (select id from public.properties where access_notes = 'demo-seed');
  delete from public.bookings
    where property_id in (select id from public.properties where access_notes = 'demo-seed');
  delete from public.lawn_areas
    where property_id in (select id from public.properties where access_notes = 'demo-seed');
  delete from public.properties where access_notes = 'demo-seed';

  for rec in
    select * from (values
      -- line1,                 postcode,   lat,     lng,     area, perim, status,       win,        day_off, assign, done, days_ago
      ('2 Aldham Lane',         'CO6 3RR',  51.9055, 0.8290, 180,  58,  'confirmed',   'morning',   0,  false, false, 0),
      ('7 Fordham Road',        'CO6 3NX',  51.9120, 0.8410, 240,  70,  'confirmed',   'afternoon', 0,  false, false, 0),
      ('The Willows, Church Rd','CO6 3PW',  51.8980, 0.8215, 90,   40,  'confirmed',   'morning',   1,  false, false, 0),
      ('14 Marks Tey Green',    'CO6 1LN',  51.8875, 0.8590, 320,  84,  'confirmed',   'any',       2,  false, false, 0),
      -- The mower's active day (all today, different spots → a real route):
      ('3 Wakes Colne Rise',    'CO6 2BY',  51.9200, 0.7980, 150,  50,  'accepted',    'morning',   0,  true,  false, 0),
      ('22 Chappel View',       'CO6 2DE',  51.9260, 0.7850, 200,  62,  'accepted',    'morning',   0,  true,  false, 0),
      ('9 Eight Ash Green',     'CO6 3QF',  51.8930, 0.8080, 120,  44,  'accepted',    'afternoon', 0,  true,  false, 0),
      ('5 Copford Lane',        'CO6 1DH',  51.8790, 0.8460, 260,  75,  'in_progress', 'morning',   0,  true,  false, 0),
      -- Completed history (for earnings + admin dashboard):
      ('11 Stanway Close',      'CO3 0LP',  51.8810, 0.8710, 210,  64,  'completed',   'morning',   0,  true,  true,  1),
      ('40 Lexden Road',        'CO3 3RW',  51.8845, 0.8830, 175,  55,  'completed',   'afternoon', 0,  true,  true,  2),
      ('8 Shrub End',           'CO3 4RL',  51.8720, 0.8790, 300,  80,  'completed',   'any',       0,  true,  true,  4),
      ('16 Prettygate',         'CO3 4AB',  51.8760, 0.8930, 140,  48,  'completed',   'morning',   0,  true,  true,  6)
    ) as t(line1, postcode, lat, lng, area, perim, status, win, day_off, assign, done, days_ago)
  loop
    v_ci := v_ci + 1;
    -- Roughly: mow £12 + £0.15/m² (medium ×1.6) + edge £6 + £0.40/m.
    v_total := round((12 + rec.area * 0.15 * 1.6 + 6 + rec.perim * 0.40)::numeric, 2);

    insert into public.properties (customer_id, line1, city, postcode, lat, lng, access_notes)
      values (v_custs[1 + (v_ci % 4)], rec.line1, 'Colchester', rec.postcode,
              rec.lat, rec.lng, 'demo-seed')
      returning id into v_prop;

    insert into public.lawn_areas (property_id, name, area_sqm, perimeter, source)
      values (v_prop, 'Main lawn', rec.area, rec.perim, 'manual')
      returning id into v_lawn;

    insert into public.bookings (
      customer_id, property_id, mower_id, status, asap, scheduled_date,
      time_window, access_provided, total_amount, currency,
      payment_status, mower_amount, commission_amount, completed_at, created_at)
    values (
      v_custs[1 + (v_ci % 4)], v_prop,
      case when rec.assign then v_mower else null end,
      rec.status,
      false,
      current_date + rec.day_off,
      rec.win,
      true,
      v_total, 'GBP',
      case when rec.done then 'captured' else 'authorized' end,
      case when rec.done then round(v_total * 0.85, 2) else null end,
      case when rec.done then round(v_total * 0.15, 2) else null end,
      case when rec.done then now() - (rec.days_ago || ' days')::interval else null end,
      now() - (rec.days_ago || ' days')::interval)
    returning id into v_book;

    insert into public.booking_lawns (booking_id, lawn_area_id, grass_height, edging, mow_price, edge_price)
      values (v_book, v_lawn, 'medium', true,
              round(rec.area * 0.15 * 1.6, 2), round(rec.perim * 0.40, 2));
  end loop;
end $$;

-- Quick check:
select status, count(*), coalesce(sum(mower_amount),0) as mower_earn
from public.bookings b
join public.properties p on p.id = b.property_id
where p.access_notes = 'demo-seed'
group by status order by status;
