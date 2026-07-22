-- MOWR — Job completion (Phase 4, step 2)
-- Mower lifecycle (en route -> arrived -> in progress -> completed), before/after
-- photos, and job detail. Payment capture is done by the capture-payment Edge
-- Function. Run in the Supabase SQL editor.

-- 1. Extend booking statuses with en_route / arrived.
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check
  check (status in ('draft','confirmed','broadcast','accepted','en_route',
                    'arrived','in_progress','completed','cancelled','expired'));

-- 2. Before/after evidence photos.
create table if not exists public.job_photos (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid not null references public.bookings (id) on delete cascade,
  mower_id     uuid not null references public.profiles (id),
  kind         text not null check (kind in ('before', 'after')),
  storage_path text not null,
  created_at   timestamptz not null default now()
);
alter table public.job_photos enable row level security;

create policy "job_photos: assigned mower"
  on public.job_photos for all
  using (auth.uid() = mower_id)
  with check (auth.uid() = mower_id);

-- 3. Storage bucket for those photos (private).
insert into storage.buckets (id, name, public)
  values ('job-photos', 'job-photos', false)
  on conflict (id) do nothing;

create policy "job-photos upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'job-photos');

create policy "job-photos read"
  on storage.objects for select to authenticated
  using (bucket_id = 'job-photos');

-- 4. Advance a job's status (only the assigned mower).
create or replace function public.set_job_status(p_booking_id uuid, p_status text)
returns boolean language plpgsql security definer set search_path = public
as $func$
declare updated int;
begin
  if p_status not in ('en_route','arrived','in_progress','completed') then
    raise exception 'Invalid status';
  end if;
  update public.bookings set status = p_status
    where id = p_booking_id and mower_id = auth.uid();
  get diagnostics updated = row_count;
  return updated = 1;
end;
$func$;
grant execute on function public.set_job_status(uuid, text) to authenticated;

-- 5. Full job detail for the assigned mower (or the owning customer).
create or replace function public.job_detail(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public
as $func$
declare result jsonb;
begin
  select to_jsonb(x) into result from (
    select b.id as booking_id, b.status, b.asap, b.scheduled_date, b.time_window,
           b.access_provided, b.total_amount, b.payment_status,
           p.line1, p.city, p.postcode, p.lat, p.lng,
           p.access_notes, p.access_presets,
           (select coalesce(jsonb_agg(jsonb_build_object(
                'lawn_area_id', bl.lawn_area_id,
                'name', la.name,
                'area_sqm', la.area_sqm,
                'perimeter', la.perimeter,
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
