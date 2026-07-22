// MOWR — Edge Function: connect-status
//
// Re-checks the mower's Stripe Connect account and syncs profiles.connect_onboarded.
// Called after the mower returns from Stripe onboarding, and whenever the app
// wants to know if payouts are ready.
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

// Turn a Stripe requirement code into a plain-English action for the mower.
function friendlyRequirement(
  code: string | null,
  disabled: boolean,
): string | null {
  if (!code && !disabled) return null;
  const c = code ?? '';
  if (c.includes('verification.additional_document')) {
    return 'Stripe needs an additional ID document to verify you.';
  }
  if (c.includes('verification.document')) {
    return 'Stripe needs a photo ID (passport or driving licence) to verify you.';
  }
  if (c.includes('id_number')) return 'Stripe needs your ID number.';
  if (c.includes('dob')) return 'Stripe needs your date of birth confirmed.';
  if (c.includes('address')) return 'Stripe needs your address confirmed.';
  if (c.startsWith('external_account') || c.includes('bank')) {
    return 'Stripe needs your bank account details.';
  }
  return 'Stripe needs a bit more information to finish verifying your payouts.';
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

    const acctId = profile?.stripe_connect_id as string | null | undefined;
    if (!acctId) {
      return json({ onboarded: false, exists: false });
    }

    let acct;
    try {
      acct = await stripe.accounts.retrieve(acctId);
    } catch (_) {
      // Stored account is gone under this key — clear it so the mower can
      // start fresh instead of getting stuck.
      await admin
        .from('profiles')
        .update({ stripe_connect_id: null, connect_onboarded: false })
        .eq('id', user.id);
      return json({ onboarded: false, exists: false, reset: true });
    }
    const onboarded = !!acct.details_submitted && !!acct.payouts_enabled;

    // Outstanding Stripe requirements (e.g. "upload a photo ID").
    const reqs = acct.requirements ?? {};
    const due: string[] = [
      ...(reqs.past_due ?? []),
      ...(reqs.currently_due ?? []),
    ];
    const actionRequired = due.length > 0 || !!reqs.disabled_reason;
    const requirement = friendlyRequirement(due[0] ?? null, !!reqs.disabled_reason);

    await admin
      .from('profiles')
      .update({
        connect_onboarded: onboarded,
        connect_action_required: actionRequired,
        connect_requirement: requirement,
      })
      .eq('id', user.id);

    return json({
      onboarded,
      exists: true,
      detailsSubmitted: !!acct.details_submitted,
      payoutsEnabled: !!acct.payouts_enabled,
      chargesEnabled: !!acct.charges_enabled,
      actionRequired,
      requirement,
      currentlyDue: reqs.currently_due ?? [],
      pastDue: reqs.past_due ?? [],
      disabledReason: reqs.disabled_reason ?? null,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
