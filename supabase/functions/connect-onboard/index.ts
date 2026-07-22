// MOWR — Edge Function: connect-onboard
//
// Creates (or reuses) the signed-in mower's Stripe Connect **Express** account
// and returns a Stripe-hosted onboarding URL. The app opens it in the browser;
// the mower fills in bank + ID details on Stripe. On return the app calls
// connect-status to sync whether onboarding finished.
//
// Request body: {}  (identity comes from the auth token)

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
      .select('stripe_connect_id')
      .eq('id', user.id)
      .single();

    let acctId = profile?.stripe_connect_id as string | null | undefined;

    // Self-heal: if a stored account no longer exists under the current Stripe
    // key (e.g. the key/account changed), forget it and make a fresh one.
    if (acctId) {
      try {
        await stripe.accounts.retrieve(acctId);
      } catch (_) {
        acctId = null;
        await admin
          .from('profiles')
          .update({ stripe_connect_id: null, connect_onboarded: false })
          .eq('id', user.id);
      }
    }

    if (!acctId) {
      const acct = await stripe.accounts.create({
        type: 'express',
        country: 'GB',
        email: user.email,
        capabilities: { transfers: { requested: true } },
        business_profile: {
          product_description: 'Lawn mowing services via MOWR',
        },
        metadata: { user_id: user.id },
      });
      acctId = acct.id;
      await admin
        .from('profiles')
        .update({ stripe_connect_id: acctId })
        .eq('id', user.id);
    }

    const link = await stripe.accountLinks.create({
      account: acctId,
      refresh_url: `${base}/functions/v1/connect-return?state=refresh`,
      return_url: `${base}/functions/v1/connect-return`,
      type: 'account_onboarding',
    });

    return json({ url: link.url });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
