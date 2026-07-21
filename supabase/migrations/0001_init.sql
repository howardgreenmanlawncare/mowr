-- MOWR — initial schema (Phase 2, step 1)
-- Core customer-side tables + Row Level Security. Mower/admin/payments tables
-- come in later migrations. Run this in the Supabase SQL editor.
--
-- Design notes:
--   * Every table has RLS enabled (CLAUDE.md: "never ship a table without RLS").
--   * Customers can only see/change their own rows.
--   * pricing_rules is a single admin-editable row read by everyone.

-- ---------------------------------------------------------------------------
-- profiles: extends auth.users with role + contact details
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        text not null default 'customer'
              check (role in ('customer', 'mower', 'admin')),
  full_name   text,
  phone       text,
  email       text,
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: read own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles: update own"
  on public.profiles for update
  using (auth.uid() = id);

create policy "profiles: insert own"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Auto-create a profile row when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- leads: early email capture (may have no account yet)
-- ---------------------------------------------------------------------------
create table if not exists public.leads (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  postcode    text,
  created_at  timestamptz not null default now(),
  booking_id  uuid
);

alter table public.leads enable row level security;

-- Anyone (even not-signed-in) can drop their email in. No read access except
-- admins (added in the admin migration).
create policy "leads: anyone can insert"
  on public.leads for insert
  to anon, authenticated
  with check (true);

-- ---------------------------------------------------------------------------
-- properties: a customer's saved property
-- ---------------------------------------------------------------------------
create table if not exists public.properties (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.profiles (id) on delete cascade,
  line1          text not null,
  city           text,
  postcode       text,
  lat            double precision,
  lng            double precision,
  access_presets text[] not null default '{}',
  access_notes   text,
  created_at     timestamptz not null default now()
);

create index if not exists properties_customer_idx
  on public.properties (customer_id);

alter table public.properties enable row level security;

create policy "properties: owner all"
  on public.properties for all
  using (auth.uid() = customer_id)
  with check (auth.uid() = customer_id);

-- ---------------------------------------------------------------------------
-- lawn_areas: a lawn belonging to a property (permanent to it)
-- ---------------------------------------------------------------------------
create table if not exists public.lawn_areas (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  name         text not null,
  area_sqm     double precision not null,
  perimeter    double precision not null,
  boundary     jsonb,          -- [{"lat":..,"lng":..}, ...] when drawn on the map
  source       text not null default 'manual'
               check (source in ('drawn', 'manual')),
  photo_url    text,
  created_at   timestamptz not null default now()
);

create index if not exists lawn_areas_property_idx
  on public.lawn_areas (property_id);

alter table public.lawn_areas enable row level security;

-- Access a lawn only through a property you own.
create policy "lawn_areas: owner all"
  on public.lawn_areas for all
  using (
    exists (
      select 1 from public.properties p
      where p.id = lawn_areas.property_id and p.customer_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.properties p
      where p.id = lawn_areas.property_id and p.customer_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- bookings
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references public.profiles (id) on delete cascade,
  property_id      uuid not null references public.properties (id),
  status           text not null default 'draft'
                   check (status in ('draft', 'confirmed', 'broadcast',
                                     'accepted', 'in_progress', 'completed',
                                     'cancelled', 'expired')),
  asap             boolean not null default true,
  scheduled_date   date,
  time_window      text check (time_window in ('any','morning','afternoon','evening')),
  access_provided  boolean,
  total_amount     numeric(10,2),
  currency         text not null default 'GBP',
  created_at       timestamptz not null default now()
);

create index if not exists bookings_customer_idx
  on public.bookings (customer_id);

alter table public.bookings enable row level security;

create policy "bookings: owner all"
  on public.bookings for all
  using (auth.uid() = customer_id)
  with check (auth.uid() = customer_id);

-- ---------------------------------------------------------------------------
-- booking_lawns: which lawns are in a booking + per-lawn choices & price snapshot
-- ---------------------------------------------------------------------------
create table if not exists public.booking_lawns (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid not null references public.bookings (id) on delete cascade,
  lawn_area_id  uuid not null references public.lawn_areas (id),
  grass_height  text not null default 'medium'
                check (grass_height in ('low', 'medium', 'high')),
  edging        boolean not null default false,
  mow_price     numeric(10,2),
  edge_price    numeric(10,2)
);

create index if not exists booking_lawns_booking_idx
  on public.booking_lawns (booking_id);

alter table public.booking_lawns enable row level security;

create policy "booking_lawns: owner all"
  on public.booking_lawns for all
  using (
    exists (
      select 1 from public.bookings b
      where b.id = booking_lawns.booking_id and b.customer_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.bookings b
      where b.id = booking_lawns.booking_id and b.customer_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- pricing_rules: single admin-editable row, readable by everyone (to price)
-- ---------------------------------------------------------------------------
create table if not exists public.pricing_rules (
  id                    int primary key default 1 check (id = 1),
  mow_turn_up           numeric(10,2) not null default 12,
  mow_rate_per_sqm      numeric(10,4) not null default 0.15,
  mow_minimum           numeric(10,2) not null default 20,
  edge_turn_up          numeric(10,2) not null default 6,
  edge_rate_per_metre   numeric(10,4) not null default 0.40,
  edge_minimum          numeric(10,2) not null default 10,
  height_mult_low       numeric(6,3)  not null default 1.0,
  height_mult_medium    numeric(6,3)  not null default 1.6,
  height_mult_high      numeric(6,3)  not null default 2.0,
  currency_symbol       text not null default '£',
  updated_at            timestamptz not null default now()
);

insert into public.pricing_rules (id) values (1) on conflict (id) do nothing;

alter table public.pricing_rules enable row level security;

create policy "pricing_rules: anyone can read"
  on public.pricing_rules for select
  to anon, authenticated
  using (true);

-- (Admin-only UPDATE policy is added in the admin migration.)
