-- MOWR — Transactional notifications (email) foundation
--
-- The app never told anyone anything happened — this is the fix. A trigger
-- enqueues an email on the key booking events; an edge function
-- (`process-notifications`) drains the queue and sends via Resend. Decoupled on
-- purpose: a slow or failed email must never block a booking.
--
-- Run after 0017. THREE setup steps make it actually send (see bottom):
--   1. Set RESEND_API_KEY (+ a verified from-domain) on the edge function.
--   2. Deploy the process-notifications edge function.
--   3. Schedule the drain (pg_cron + pg_net snippet at the bottom).
-- Until then, rows just accumulate as 'pending' — harmless.

-- ---------------------------------------------------------------------------
-- 1. The queue / log.
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id             uuid primary key default gen_random_uuid(),
  booking_id     uuid references public.bookings (id) on delete cascade,
  recipient_email text not null,
  kind           text not null,   -- booking_confirmed | mower_assigned | approval_needed | job_completed
  subject        text not null,
  body           text not null,
  status         text not null default 'pending'
                 check (status in ('pending','sent','failed','skipped')),
  error          text,
  created_at     timestamptz not null default now(),
  sent_at        timestamptz
);

alter table public.notifications enable row level security;
-- No public policies: only the service role (the edge function) and admins,
-- via SECURITY DEFINER RPCs, ever touch this table.

create index if not exists notifications_pending_idx
  on public.notifications (created_at) where status = 'pending';

-- ---------------------------------------------------------------------------
-- 2. Enqueue helpers.
-- ---------------------------------------------------------------------------
create or replace function public._customer_email(p_booking uuid)
returns text language sql stable security definer set search_path = public, auth as $func$
  select coalesce(p.email, u.email)
  from public.bookings b
  join public.profiles p on p.id = b.customer_id
  left join auth.users u on u.id = b.customer_id
  where b.id = p_booking;
$func$;

create or replace function public._enqueue(
  p_booking uuid, p_kind text, p_subject text, p_body text)
returns void language plpgsql security definer set search_path = public as $func$
declare v_email text;
begin
  v_email := public._customer_email(p_booking);
  if v_email is null then return; end if;
  insert into public.notifications (booking_id, recipient_email, kind, subject, body)
    values (p_booking, v_email, p_kind, p_subject, p_body);
end;
$func$;

-- ---------------------------------------------------------------------------
-- 3. Enqueue on the events that matter to a customer.
-- ---------------------------------------------------------------------------
create or replace function public.tg_booking_notify()
returns trigger language plpgsql security definer set search_path = public as $func$
begin
  if tg_op = 'INSERT' then
    if new.status in ('confirmed','broadcast') then
      perform public._enqueue(new.id, 'booking_confirmed',
        'Your MOWR booking is confirmed',
        'Thanks for booking with MOWR. We''re finding you a vetted local mower '
        'and will let you know as soon as it''s accepted. You''re only charged '
        'once the job is done.');
    end if;
    return new;
  end if;

  if new.mower_id is not null and old.mower_id is null then
    perform public._enqueue(new.id, 'mower_assigned',
      'A mower has accepted your job',
      'Good news — a mower has accepted your MOWR job. You can track its '
      'progress in the app.');
  end if;

  if new.approval_status = 'pending'
     and coalesce(old.approval_status, '') <> 'pending' then
    perform public._enqueue(new.id, 'approval_needed',
      'Action needed: approve your updated MOWR price',
      'Your mower re-measured the lawn on site and the price changed. Open the '
      'MOWR app to approve or decline — the job can''t be completed until you do.');
  end if;

  if new.status = 'completed' and old.status <> 'completed' then
    perform public._enqueue(new.id, 'job_completed',
      'Your lawn is done',
      'Your MOWR mow is complete and payment has been taken. Thanks for using MOWR!');
  end if;

  return new;
end;
$func$;

drop trigger if exists booking_notify on public.bookings;
create trigger booking_notify
  after insert or update on public.bookings
  for each row execute function public.tg_booking_notify();

-- ---------------------------------------------------------------------------
-- 4. Drain scheduling — run ONCE after deploying process-notifications and
--    enabling pg_cron + pg_net. Fill in your project ref and service_role key
--    (ideally from Vault, not inline):
--
--   create extension if not exists pg_cron;
--   create extension if not exists pg_net;
--   select cron.schedule('drain-notifications', '* * * * *', $drain$
--     select net.http_post(
--       url := 'https://ypbizskokuxpfdyvdgmg.supabase.co/functions/v1/process-notifications',
--       headers := jsonb_build_object(
--         'Authorization', 'Bearer <SERVICE_ROLE_KEY>',
--         'Content-Type',  'application/json'),
--       body := '{}'::jsonb);
--   $drain$);
-- ---------------------------------------------------------------------------
