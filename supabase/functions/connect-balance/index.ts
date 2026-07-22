// MOWR — Edge Function: connect-balance
//
// Reads the mower's Stripe Connect balance and upcoming payout so the app can
// show an "expected payouts" summary (available, on the way, next arrival date).
//
// Request body: {}

import Stripe from 'https://esm.sh/stripe@16.12.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') as string, {
  apiVersion: '2024-06-20',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function sumGbp(entries: Array<{ amount: number; currency: string }> = []): number {
  return entries
    .filter((e) => e.currency === 'gbp')
    .reduce((s, e) => s + e.amount, 0);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization' }, 401);

    const base = Deno.env.get('SUPABASE_URL') as string;
    const userClient = createClient(
      base,
      Deno.env.get('SUPABASE_ANON_KEY') as string,
      { global: { headers: { Authorization: authHeader } } },
    );
    const {
      data: { user },
    } = await userClient.auth.getUser();
    if (!user) return json({ error: 'Not authenticated' }, 401);

    const admin = createClient(
      base,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') as string,
    );
    const { data: profile } = await admin
      .from('profiles')
      .select('stripe_connect_id, connect_onboarded')
      .eq('id', user.id)
      .single();

    const acctId = profile?.stripe_connect_id as string | null | undefined;
    if (!acctId || !profile?.connect_onboarded) {
      return json({ exists: false });
    }

    // Balance + payouts are read on the connected account (Stripe-Account header).
    const balance = await stripe.balance.retrieve({ stripeAccount: acctId });
    const available = sumGbp(balance.available as never);
    const pending = sumGbp(balance.pending as never);

    const payouts = await stripe.payouts.list(
      { limit: 5 },
      { stripeAccount: acctId },
    );

    let nextPayout: Record<string, unknown> | null = null;
    const upcoming = payouts.data.find(
      (p) => p.status === 'pending' || p.status === 'in_transit',
    );
    if (upcoming) {
      nextPayout = {
        amount: upcoming.amount,
        currency: upcoming.currency,
        status: upcoming.status,
        arrivalDate: upcoming.arrival_date, // unix seconds
      };
    }

    const recent = payouts.data.map((p) => ({
      amount: p.amount,
      currency: p.currency,
      status: p.status,
      arrivalDate: p.arrival_date,
    }));

    return json({
      exists: true,
      currency: 'gbp',
      available, // pence — settled, ready to pay out
      pending, // pence — still clearing
      nextPayout,
      recent,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
