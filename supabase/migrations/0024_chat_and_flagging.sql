-- MOWR — En-route customer↔mower chat, off-app/cash flagging, and cancel-after-
-- accept reliability tracking.
--
-- Two anti-circumvention concerns from the owner:
--   1. Mowers who accept then bail — especially after going en route — may be
--      doing the job for cash off-app. Track cancels alongside the existing
--      auto-accept refusals (0023) as reliability events, and alert admin the
--      moment a mower cancels after they were already on the way.
--   2. Once a job is under way the customer and mower can chat. Any message that
--      hints at taking the job off-app (cash, bank transfer, "cancel the
--      booking", swapping phone numbers, …) is flagged server-side and admin is
--      notified immediately.
--
-- Run after 0023 (needs mower_job_refusals + mower_refusal_count) and after
-- 0018_notifications (needs the notifications queue + _enqueue).

-- ---------------------------------------------------------------------------
-- Part 0: admin fan-out helpers (notifications queue → every admin).
-- ---------------------------------------------------------------------------
create or replace function public._admin_emails()
returns setof text language sql stable security definer
set search_path = public, auth as $func$
  select coalesce(p.email, u.email)
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.role = 'admin' and coalesce(p.email, u.email) is not null;
$func$;

create or replace function public._enqueue_admins(
  p_booking uuid, p_kind text, p_subject text, p_body text)
returns void language plpgsql security definer set search_path = public as $func$
declare e text;
begin
  for e in select public._admin_emails() loop
    insert into public.notifications (booking_id, recipient_email, kind, subject, body)
      values (p_booking, e, p_kind, p_subject, p_body);
  end loop;
end;
$func$;

-- ---------------------------------------------------------------------------
-- Part A: cancel-after-accept reliability.
-- ---------------------------------------------------------------------------
-- Distinguish a pre-start release ('refusal', from 0023's release_auto_job)
-- from bailing after acceptance ('cancel'). Both count toward the rolling
-- reliability total, but a cancel after going en route is the loud signal.
alter table public.mower_job_refusals
  add column if not exists event_type text not null default 'refusal';

create or replace function public.mower_cancel_job(
  p_booking_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $func$
declare
  v_status text; v_auto boolean; v_visited boolean;
  v_count int := 0; v_paused boolean := false; v_threshold int := 3;
  v_name text; v_reason text;
begin
  select b.status, coalesce(b.auto_allocated, false),
         coalesce(p.full_name, 'A mower')
    into v_status, v_auto, v_name
    from public.bookings b
    left join public.profiles p on p.id = auth.uid()
    where b.id = p_booking_id and b.mower_id = auth.uid();
  if v_status is null then raise exception 'Not your job'; end if;
  if v_status not in ('accepted','en_route','arrived','in_progress') then
    raise exception 'This job can no longer be cancelled here';
  end if;

  -- en_route+ means the address was unlocked and they likely attended.
  v_visited := v_status in ('en_route','arrived','in_progress');
  v_reason := nullif(trim(p_reason), '');

  update public.bookings
     set status = 'confirmed', mower_id = null, auto_allocated = false
   where id = p_booking_id;

  insert into public.mower_job_refusals (mower_id, booking_id, reason, event_type)
    values (auth.uid(), p_booking_id, v_reason,
            case when v_visited then 'cancel' else 'refusal' end);

  v_count := public.mower_refusal_count(auth.uid(), 30);
  if v_auto and v_count >= v_threshold then
    update public.profiles set auto_allocate = false where id = auth.uid();
    v_paused := true;
  end if;

  if v_visited then
    perform public._enqueue_admins(p_booking_id, 'mower_cancelled_after_enroute',
      'Reliability flag: mower cancelled after going en route',
      v_name || ' cancelled a job after being marked en route / on site — a '
      || 'possible off-app cash job. Booking ' || p_booking_id::text
      || '. Reason given: ' || coalesce(v_reason, '(none)'));
    insert into public.support_tickets (user_id, summary, transcript, status)
      values (auth.uid(),
        'Mower cancelled after going en route (possible off-app job)',
        'Booking ' || p_booking_id::text || ' — ' || v_name
          || ' cancelled at status ''' || v_status || '''. Reason: '
          || coalesce(v_reason, '(none)'),
        'open');
  end if;

  return jsonb_build_object(
    'cancelled', true, 'was_visited', v_visited,
    'refusals_30d', v_count, 'auto_paused', v_paused);
end;
$func$;
grant execute on function public.mower_cancel_job(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Part B: chat.
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references public.bookings(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  sender_role text not null check (sender_role in ('customer','mower')),
  body        text not null,
  flagged     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists messages_booking_idx
  on public.messages(booking_id, created_at);

alter table public.messages enable row level security;

-- Participants (and admins) can read a booking's thread. Direct reads keep
-- realtime subscriptions simple; there is deliberately NO insert policy —
-- every message goes through send_message() so it can be flag-scanned.
drop policy if exists "messages: participants read" on public.messages;
create policy "messages: participants read"
  on public.messages for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.bookings b
      where b.id = messages.booking_id
        and (b.customer_id = auth.uid() or b.mower_id = auth.uid())
    )
  );

-- Admins read every flagged message.
drop policy if exists "messages: admin read" on public.messages;
create policy "messages: admin read"
  on public.messages for select using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Part C: off-app / cash flag terms (admin-tunable, no deploy needed).
-- ---------------------------------------------------------------------------
create table if not exists public.chat_flag_terms (
  id       uuid primary key default gen_random_uuid(),
  pattern  text not null,
  is_regex boolean not null default false,
  active   boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.chat_flag_terms enable row level security;
-- Read/managed only by admins via SECURITY DEFINER paths; no public policy.

insert into public.chat_flag_terms (pattern, is_regex) values
  ('cash', false),
  ('cash in hand', false),
  ('in hand', false),
  ('off the app', false),
  ('off app', false),
  ('outside the app', false),
  ('outside of the app', false),
  ('without the app', false),
  ('not through the app', false),
  ('not through app', false),
  ('bank transfer', false),
  ('paypal', false),
  ('venmo', false),
  ('revolut', false),
  ('pay me direct', false),
  ('pay direct', false),
  ('pay directly', false),
  ('pay you direct', false),
  ('cancel the booking', false),
  ('cancel the job', false),
  ('cancel your booking', false),
  ('cancel it', false),
  ('don''t book', false),
  ('do not book', false),
  ('no need to book', false),
  ('cheaper if', false),
  ('sort you out', false),
  ('between us', false),
  ('cut out the app', false),
  ('cut out mowr', false),
  -- a phone number being exchanged to arrange things off-app
  ('(\+?\d[\d ]{8,}\d)', true)
on conflict do nothing;

create or replace function public._message_flagged(p_body text)
returns boolean language plpgsql stable security definer
set search_path = public as $func$
declare t record; v text := lower(p_body);
begin
  for t in select pattern, is_regex from public.chat_flag_terms where active loop
    if t.is_regex then
      if v ~ t.pattern then return true; end if;
    elsif position(lower(t.pattern) in v) > 0 then
      return true;
    end if;
  end loop;
  return false;
end;
$func$;

-- ---------------------------------------------------------------------------
-- Part D: send / list.
-- ---------------------------------------------------------------------------
create or replace function public.send_message(p_booking_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $func$
declare
  v_customer uuid; v_mower uuid; v_status text; v_role text;
  v_flag boolean; v_id uuid; v_name text;
begin
  if coalesce(trim(p_body), '') = '' then raise exception 'Empty message'; end if;

  select customer_id, mower_id, status into v_customer, v_mower, v_status
    from public.bookings where id = p_booking_id;
  if v_customer is null then raise exception 'No such booking'; end if;

  if auth.uid() = v_customer then v_role := 'customer';
  elsif auth.uid() = v_mower then v_role := 'mower';
  else raise exception 'Not a participant'; end if;

  -- Chat opens once the mower is on the way (address just unlocked) and closes
  -- when the job is done or gone.
  if v_status not in ('en_route','arrived','in_progress') then
    raise exception 'Chat opens once the mower is on the way to the job';
  end if;

  v_flag := public._message_flagged(p_body);

  insert into public.messages (booking_id, sender_id, sender_role, body, flagged)
    values (p_booking_id, auth.uid(), v_role, p_body, v_flag)
    returning id into v_id;

  if v_flag then
    select coalesce(full_name, v_role) into v_name
      from public.profiles where id = auth.uid();
    perform public._enqueue_admins(p_booking_id, 'chat_flagged',
      'Chat flagged: possible off-app / cash arrangement',
      'A message on booking ' || p_booking_id::text || ' from '
        || coalesce(v_name, v_role) || ' (' || v_role || ') was flagged: "'
        || p_body || '"');
    insert into public.support_tickets (user_id, summary, transcript, status)
      values (auth.uid(),
        'Flagged chat message (possible off-app / cash)',
        'Booking ' || p_booking_id::text || ' — ' || v_role || ': ' || p_body,
        'open');
  end if;

  return jsonb_build_object('id', v_id, 'flagged', v_flag);
end;
$func$;
grant execute on function public.send_message(uuid, text) to authenticated;

-- Whether the chat channel is currently open for a booking (participant view).
create or replace function public.chat_open(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = public as $func$
  select exists (
    select 1 from public.bookings b
    where b.id = p_booking_id
      and (b.customer_id = auth.uid() or b.mower_id = auth.uid())
      and b.status in ('en_route','arrived','in_progress')
  );
$func$;
grant execute on function public.chat_open(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Part E: admin chat-term CRUD + flagged-message review.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_flag_terms()
returns jsonb language plpgsql stable security definer set search_path = public as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'pattern', pattern, 'is_regex', is_regex, 'active', active
    ) order by created_at), '[]'::jsonb) from public.chat_flag_terms);
end;
$func$;
grant execute on function public.admin_list_flag_terms() to authenticated;

create or replace function public.admin_save_flag_term(
  p_id uuid, p_pattern text, p_is_regex boolean, p_active boolean)
returns void language plpgsql security definer set search_path = public as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_id is null then
    insert into public.chat_flag_terms (pattern, is_regex, active)
      values (trim(p_pattern), coalesce(p_is_regex,false), coalesce(p_active,true));
  else
    update public.chat_flag_terms
       set pattern = trim(p_pattern),
           is_regex = coalesce(p_is_regex,false),
           active = coalesce(p_active,true)
     where id = p_id;
  end if;
end;
$func$;
grant execute on function public.admin_save_flag_term(uuid, text, boolean, boolean) to authenticated;

create or replace function public.admin_delete_flag_term(p_id uuid)
returns void language plpgsql security definer set search_path = public as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  delete from public.chat_flag_terms where id = p_id;
end;
$func$;
grant execute on function public.admin_delete_flag_term(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Part F: realtime — the chat screen streams the thread, so the table must be
-- in the realtime publication (RLS still scopes each subscriber's rows).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='messages'
  ) then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;
end $$;