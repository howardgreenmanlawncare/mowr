// MOWR — Edge Function: process-notifications
//
// Drains the notifications queue: reads pending rows, sends each as an email via
// Resend, and marks it sent/failed. Invoked on a schedule (pg_cron + pg_net —
// see 0018_notifications.sql), so a slow send never blocks a booking.
//
// Env required:
//   RESEND_API_KEY   — from resend.com
//   NOTIFY_FROM      — a verified from-address, e.g. "MOWR <hello@mowr.co.uk>"
// Deploy: supabase functions deploy process-notifications

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const RESEND_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const FROM = Deno.env.get('NOTIFY_FROM') ?? 'MOWR <onboarding@resend.dev>';
const BATCH = 25;

async function sendEmail(to: string, subject: string, text: string): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: FROM, to, subject, text }),
  });
  if (!res.ok) {
    throw new Error(`Resend ${res.status}: ${await res.text()}`);
  }
}

Deno.serve(async () => {
  const admin = createClient(
    Deno.env.get('SUPABASE_URL') as string,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') as string,
  );

  if (!RESEND_KEY) {
    return new Response(
      JSON.stringify({ error: 'RESEND_API_KEY not set' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: pending, error } = await admin
    .from('notifications')
    .select('id, recipient_email, subject, body')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(BATCH);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let sent = 0;
  let failed = 0;
  for (const n of pending ?? []) {
    try {
      await sendEmail(n.recipient_email, n.subject, n.body);
      await admin
        .from('notifications')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .eq('id', n.id);
      sent++;
    } catch (e) {
      await admin
        .from('notifications')
        .update({ status: 'failed', error: String(e) })
        .eq('id', n.id);
      failed++;
    }
  }

  return new Response(JSON.stringify({ processed: (pending ?? []).length, sent, failed }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
