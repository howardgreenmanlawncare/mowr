-- MOWR — AI assistant: record-action tools + support escalation
--
-- The merged chat assistant executes these server-side (scoped to the signed-in
-- customer). Booking itself is NOT here — the assistant hands the customer off
-- to the existing booking flow so the map-draw and payment step are unchanged
-- and money stays human-in-the-loop. These are the post-booking record actions
-- (reschedule / cancel) — which also fill a real product gap — plus escalation.
-- Run after 0018.

-- ---------------------------------------------------------------------------
-- 1. Reschedule a booking the customer owns, before work has started.
-- ---------------------------------------------------------------------------
create or replace function public.reschedule_booking(
  p_booking_id uuid, p_date date, p_window text default 'any')
returns boolean language plpgsql security definer set search_path = public as $func$
declare v_status text;
begin
  select status into v_status from public.bookings
    where id = p_booking_id and customer_id = auth.uid();
  if v_status is null then raise exception 'No such booking'; end if;
  if v_status not in ('confirmed','broadcast','accepted') then
    raise exception 'This booking can no longer be rescheduled';
  end if;
  if p_window not in ('any','morning','afternoon','evening') then
    raise exception 'Invalid time window';
  end if;

  update public.bookings
     set scheduled_date = p_date, time_window = p_window, asap = false
   where id = p_booking_id and customer_id = auth.uid();
  return true;
end;
$func$;
grant execute on function public.reschedule_booking(uuid, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Cancel a booking the customer owns. Payment is only authorised (held),
--    not captured, until the job completes — so cancelling before completion
--    simply releases it (the hold is never taken).
-- ---------------------------------------------------------------------------
create or replace function public.cancel_booking(p_booking_id uuid)
returns boolean language plpgsql security definer set search_path = public as $func$
declare v_status text;
begin
  select status into v_status from public.bookings
    where id = p_booking_id and customer_id = auth.uid();
  if v_status is null then raise exception 'No such booking'; end if;
  if v_status in ('completed','cancelled','expired') then
    raise exception 'This booking can no longer be cancelled';
  end if;

  update public.bookings set status = 'cancelled', mower_id = null
   where id = p_booking_id and customer_id = auth.uid();
  return true;
end;
$func$;
grant execute on function public.cancel_booking(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Support escalation — when the assistant can't resolve something, it opens
--    a ticket for a human (admin) to pick up.
-- ---------------------------------------------------------------------------
create table if not exists public.support_tickets (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  summary    text not null,
  transcript text,
  status     text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);

alter table public.support_tickets enable row level security;

create policy "support_tickets: owner reads own"
  on public.support_tickets for select
  using (auth.uid() = user_id);

create or replace function public.escalate_support(p_summary text, p_transcript text default null)
returns uuid language plpgsql security definer set search_path = public as $func$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into public.support_tickets (user_id, summary, transcript)
    values (auth.uid(), p_summary, p_transcript)
    returning id into v_id;
  return v_id;
end;
$func$;
grant execute on function public.escalate_support(text, text) to authenticated;

-- Admins can see the queue.
create or replace function public.admin_list_support_tickets()
returns jsonb language plpgsql stable security definer set search_path = public as $func$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'summary', t.summary, 'status', t.status,
    'created_at', t.created_at,
    'customer', coalesce(p.full_name, u.email)) order by t.created_at desc), '[]'::jsonb)
    into v
  from public.support_tickets t
  left join public.profiles p on p.id = t.user_id
  left join auth.users u on u.id = t.user_id;
  return v;
end;
$func$;
grant execute on function public.admin_list_support_tickets() to authenticated;
