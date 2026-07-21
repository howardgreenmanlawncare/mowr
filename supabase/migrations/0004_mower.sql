-- MOWR — Mower marketplace (Phase 4, step 1)
-- Lets approved mowers see unassigned confirmed jobs and claim them atomically.
-- Customer data stays owner-only in RLS; mowers reach jobs ONLY through the
-- SECURITY DEFINER functions below, which enforce the rules centrally.
-- Run in the Supabase SQL editor.

alter table public.profiles
  add column if not exists mower_approved boolean not null default false;

alter table public.bookings
  add column if not exists mower_id uuid references public.profiles (id);
create index if not exists bookings_mower_idx on public.bookings (mower_id);

create or replace function public.is_approved_mower()
returns boolean language sql stable security definer set search_path = public
as $func$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'mower' and mower_approved
  );
$func$;

create or replace function public._job_json(where_clause text)
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare result jsonb;
begin
  execute format($q$
    select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) from (
      select b.id as booking_id, b.status, b.created_at, b.scheduled_date,
             b.asap, b.time_window, b.access_provided, b.total_amount,
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

create or replace function public.available_jobs()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
begin
  if not public.is_approved_mower() then
    return '[]'::jsonb;
  end if;
  return public._job_json($w$b.status = 'confirmed' and b.mower_id is null$w$);
end;
$func$;

create or replace function public.my_jobs()
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
begin
  return public._job_json(format($w$b.mower_id = %L$w$, auth.uid()));
end;
$func$;

create or replace function public.accept_job(p_booking_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $func$
declare updated int;
begin
  if not public.is_approved_mower() then
    raise exception 'Not an approved mower';
  end if;
  update public.bookings
    set mower_id = auth.uid(), status = 'accepted'
    where id = p_booking_id and status = 'confirmed' and mower_id is null;
  get diagnostics updated = row_count;
  return updated = 1;
end;
$func$;

grant execute on function public.is_approved_mower() to authenticated;
grant execute on function public.available_jobs() to authenticated;
grant execute on function public.my_jobs() to authenticated;
grant execute on function public.accept_job(uuid) to authenticated;
