-- MOWR — Recurring bookings + loyalty discounts
--
-- Adds recurrence to bookings and an admin-editable discount_rules table that
-- the pricing engine reads. Discounts key off the occurrence number in a
-- recurring series ("your 3rd mow is 20% off"). Run after 0015.

-- ---------------------------------------------------------------------------
-- 1. Recurrence on bookings. A booking belongs to a series (its own id groups
--    the occurrences); occurrence_number counts within it; recurrence_interval
--    _days = 0 means a one-off. next_occurrence_date is what the generator cron
--    will read to spawn the following visit.
-- ---------------------------------------------------------------------------
alter table public.bookings
  add column if not exists series_id uuid default gen_random_uuid(),
  add column if not exists occurrence_number int not null default 1,
  add column if not exists recurrence_interval_days int not null default 0,
  add column if not exists next_occurrence_date date;

-- ---------------------------------------------------------------------------
-- 2. Admin-modelled discount rules.
-- ---------------------------------------------------------------------------
create table if not exists public.discount_rules (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  percent_off    numeric(6,3) not null check (percent_off >= 0 and percent_off <= 100),
  active         boolean not null default true,
  recurring_only boolean not null default true,
  min_occurrence int not null default 1 check (min_occurrence >= 1),
  ongoing        boolean not null default false,
  created_at     timestamptz not null default now()
);

alter table public.discount_rules enable row level security;

-- Anyone can read the active rules (the app prices with them, incl. guests).
create policy "discount_rules: read active"
  on public.discount_rules for select
  to anon, authenticated
  using (active);

-- Seed the owner's example so recurrence is rewarding out of the box.
insert into public.discount_rules (name, percent_off, recurring_only, min_occurrence, ongoing)
select 'Recurring — 3rd mow 20% off', 20, true, 3, false
where not exists (select 1 from public.discount_rules);

-- ---------------------------------------------------------------------------
-- 3. Admin management RPCs (admins see + edit ALL rules, active or not).
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_discounts()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at), '[]'::jsonb)
    into v from public.discount_rules d;
  return v;
end;
$func$;
grant execute on function public.admin_list_discounts() to authenticated;

create or replace function public.admin_save_discount(p jsonb)
returns uuid language plpgsql security definer set search_path = public
as $func$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;

  if (p->>'id') is null or (p->>'id') = '' then
    insert into public.discount_rules
      (name, percent_off, active, recurring_only, min_occurrence, ongoing)
    values (
      coalesce(p->>'name', 'Discount'),
      coalesce((p->>'percent_off')::numeric, 0),
      coalesce((p->>'active')::boolean, true),
      coalesce((p->>'recurring_only')::boolean, true),
      coalesce((p->>'min_occurrence')::int, 1),
      coalesce((p->>'ongoing')::boolean, false))
    returning id into v_id;
  else
    update public.discount_rules set
      name           = coalesce(p->>'name', name),
      percent_off    = coalesce((p->>'percent_off')::numeric, percent_off),
      active         = coalesce((p->>'active')::boolean, active),
      recurring_only = coalesce((p->>'recurring_only')::boolean, recurring_only),
      min_occurrence = coalesce((p->>'min_occurrence')::int, min_occurrence),
      ongoing        = coalesce((p->>'ongoing')::boolean, ongoing)
    where id = (p->>'id')::uuid
    returning id into v_id;
  end if;

  return v_id;
end;
$func$;
grant execute on function public.admin_save_discount(jsonb) to authenticated;

create or replace function public.admin_delete_discount(p_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  delete from public.discount_rules where id = p_id;
  return true;
end;
$func$;
grant execute on function public.admin_delete_discount(uuid) to authenticated;
