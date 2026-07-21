// MOWR — Supabase Edge Function: create-payment-intent
//
// Creates a PaymentIntent that AUTHORISES (holds) the booking amount without
// capturing it — the money is captured later, when the mow is completed. Also
// saves the card for future use. Returns what the app's PaymentSheet needs:
//   { paymentIntentClientSecret, ephemeralKey, customerId, paymentIntentId }
//
// Request body: { "amount": <pence:int>, "currency": "gbp" }
//
// The Stripe SECRET key lives only here (STRIPE_SECRET_KEY secret).

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

    const body = await req.json().catch(() => ({}));
    const amount = Number(body.amount);
    const currency = (body.currency as string) ?? 'gbp';
    if (!Number.isFinite(amount) || amount <= 0) {
      return json({ error: 'Invalid amount' }, 400);
    }

    const userClient = createClient(
      Deno.env.get('SUPABASE_URL') as string,
      Deno.env.get('SUPABASE_ANON_KEY') as string,
      { global: { headers: { Authorization: authHeader } } },
    );
    const {
      data: { user },
    } = await userClient.auth.getUser();
    if (!user) return json({ error: 'Not authenticated' }, 401);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') as string,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') as string,
    );
    const { data: profile } = await admin
      .from('profiles')
      .select('stripe_customer_id, email, full_name')
      .eq('id', user.id)
      .single();

    let customerId = profile?.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: profile?.email ?? user.email ?? undefined,
        name: profile?.full_name ?? undefined,
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await admin
        .from('profiles')
        .update({ stripe_customer_id: customerId })
        .eq('id', user.id);
    }

    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2024-06-20' },
    );

    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount),
      currency,
      customer: customerId,
      capture_method: 'manual', // authorise/hold now, capture on completion
      setup_future_usage: 'off_session', // also save the card
      automatic_payment_methods: { enabled: true },
      metadata: { supabase_user_id: user.id },
    });

    return json({
      paymentIntentClientSecret: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customerId,
      paymentIntentId: paymentIntent.id,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
