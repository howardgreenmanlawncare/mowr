// MOWR — Edge Function: connect-dashboard
//
// Returns a single-use login link to the mower's Stripe **Express dashboard**,
// where they can see their balance, payouts and full transaction history.
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
      return json({ error: 'Finish payout setup first.' }, 400);
    }

    const link = await stripe.accounts.createLoginLink(acctId);
    return json({ url: link.url });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
