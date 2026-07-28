-- MOWR — Admin alerts inbox: read + resolve support tickets (incl. chat flags
-- and reliability flags raised by 0024). Extends the 0019 list RPC to carry the
-- transcript (so the flagged message / cancel detail is visible) and adds a
-- resolve action. Run after 0024.

create or replace function public.admin_list_support_tickets()
returns jsonb language plpgsql stable security definer set search_path = public
as $function$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'summary', t.summary, 'transcript', t.transcript,
    'status', t.status, 'created_at', t.created_at,
    'customer', coalesce(p.full_name, u.email)
  ) order by (t.status = 'open') desc, t.created_at desc), '[]'::jsonb)
    into v
  from public.support_tickets t
  left join public.profiles p on p.id = t.user_id
  left join auth.users u on u.id = t.user_id;
  return v;
end;
$function$;
grant execute on function public.admin_list_support_tickets() to authenticated;

create or replace function public.admin_resolve_support_ticket(
  p_id uuid, p_status text default 'resolved')
returns void language plpgsql security definer set search_path = public as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.support_tickets
     set status = coalesce(nullif(trim(p_status), ''), 'resolved')
   where id = p_id;
end;
$func$;
grant execute on function public.admin_resolve_support_ticket(uuid, text) to authenticated;

-- Count of open tickets — drives the admin nav badge.
create or replace function public.admin_open_ticket_count()
returns int language plpgsql stable security definer set search_path = public as $func$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return (select count(*)::int from public.support_tickets where status = 'open');
end;
$func$;
grant execute on function public.admin_open_ticket_count() to authenticated;