// MOWR — Supabase Edge Function: capture-payment
//
// Captures the held PaymentIntent for a completed job and marks the booking
// completed. Only the assigned mower can capture their own job.
//
// Handles on-site re-measures (Increment 2b). The amount actually taken is the
// revised total when the mower corrected the measurements:
//   * approval_status 'pending'            -> refuse; the customer must approve first
//   * revised <= hold  (or 'declined')     -> partial capture of the lower amount
//   * revised  > hold  (auto / approved)   -> capture the full hold, then charge
//                                             the difference off-session on the
//                                             saved card
//
// Request body: { "booking_id": "<uuid>" }

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
    const bookingId = body.booking_id as string | undefined;
    if (!bookingId) return json({ error: 'Missing booking_id' }, 400);

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
    const { data: booking } = await admin
      .from('bookings')
      .select(
        'id, mower_id, payment_intent_id, payment_status, status, ' +
          'total_amount, revised_total, approval_status, currency',
      )
      .eq('id', bookingId)
      .single();

    if (!booking) return json({ error: 'Booking not found' }, 404);
    if (booking.mower_id !== user.id) {
      return json({ error: 'Not your job' }, 403);
    }
    if (booking.payment_status === 'captured') {
      return json({ ok: true, captured: true, alreadyCaptured: true });
    }

    // Mower's Connect account + commission (for the payout after capture).
    const { data: mowerProfile } = await admin
      .from('profiles')
      .select('stripe_connect_id, commission_pct')
      .eq('id', booking.mower_id)
      .single();
    const { data: rules } = await admin
      .from('pricing_rules')
      .select('default_commission_pct')
      .eq('id', 1)
      .single();
    const connectId = mowerProfile?.stripe_connect_id as string | null;
    const commissionPct = Number(
      mowerProfile?.commission_pct ?? rules?.default_commission_pct ?? 15,
    );

    // A big increase must be approved by the customer before we can take money.
    if (booking.approval_status === 'pending') {
      return json(
        { error: 'Waiting for the customer to approve the updated price.' },
        409,
      );
    }

    // What we should actually charge. A declined revision falls back to the
    // originally-agreed amount; otherwise a revised total wins when present.
    const original = Number(booking.total_amount ?? 0);
    const useRevised =
      booking.revised_total != null && booking.approval_status !== 'declined';
    const effective = useRevised ? Number(booking.revised_total) : original;
    const currency = String(booking.currency ?? 'GBP').toLowerCase();

    const originalPence = Math.round(original * 100);
    const effectivePence = Math.round(effective * 100);

    // No payment attached (older/free bookings): just mark complete.
    if (!booking.payment_intent_id) {
      await admin
        .from('bookings')
        .update({
          status: 'completed',
          captured_amount: effective,
          completed_at: new Date().toISOString(),
        })
        .eq('id', bookingId);
      return json({ ok: true, captured: false, amount: effective });
    }

    let topUpCharged = false;
    let topUpError: string | null = null;
    let capturedAmount = effective;

    // Charges captured on the platform, so we can transfer the mower's cut of
    // each one (using source_transaction, which ties the transfer to the charge
    // and doesn't require a pre-funded platform balance).
    const charges: { id: string; amount: number }[] = [];

    if (effectivePence <= originalPence) {
      // Lower or equal — capture only what's owed; the rest of the hold is
      // released automatically by Stripe. (Guard the 0 edge case.)
      const toCapture = Math.max(effectivePence, 1);
      const capd = await stripe.paymentIntents.capture(
        booking.payment_intent_id,
        { amount_to_capture: toCapture },
      );
      capturedAmount = toCapture / 100;
      if (capd.latest_charge) {
        charges.push({ id: String(capd.latest_charge), amount: toCapture });
      }
    } else {
      // Higher (auto within threshold, or customer-approved). Take the full
      // hold, then charge the difference off-session on the saved card.
      const capd = await stripe.paymentIntents.capture(
        booking.payment_intent_id,
      );
      if (capd.latest_charge) {
        charges.push({ id: String(capd.latest_charge), amount: originalPence });
      }
      const topUpPence = effectivePence - originalPence;
      try {
        const hold = await stripe.paymentIntents.retrieve(
          booking.payment_intent_id,
        );
        const customer =
          typeof hold.customer === 'string' ? hold.customer : hold.customer?.id;
        const pm =
          typeof hold.payment_method === 'string'
            ? hold.payment_method
            : hold.payment_method?.id;
        if (!customer || !pm) {
          throw new Error('No saved card to charge the difference.');
        }
        const topUp = await stripe.paymentIntents.create({
          amount: topUpPence,
          currency,
          customer,
          payment_method: pm,
          off_session: true,
          confirm: true,
          metadata: { booking_id: bookingId, kind: 'remeasure_topup' },
        });
        if (topUp.status === 'succeeded') {
          topUpCharged = true;
          capturedAmount = effective;
          if (topUp.latest_charge) {
            charges.push({ id: String(topUp.latest_charge), amount: topUpPence });
          }
        } else {
          topUpError = `Top-up status: ${topUp.status}`;
          capturedAmount = original;
        }
      } catch (e) {
        // Base amount is captured; the extra needs manual follow-up.
        topUpError = String(e);
        capturedAmount = original;
      }
    }

    // Pay the mower their share (total minus commission) of each captured charge.
    let mowerPence = 0;
    let transferId: string | null = null;
    let transferError: string | null = null;
    if (connectId) {
      for (const ch of charges) {
        const mowerPart = Math.round(ch.amount * (1 - commissionPct / 100));
        if (mowerPart <= 0) continue;
        try {
          const t = await stripe.transfers.create({
            amount: mowerPart,
            currency,
            destination: connectId,
            source_transaction: ch.id,
            metadata: { booking_id: bookingId },
          });
          mowerPence += mowerPart;
          transferId = transferId ? `${transferId},${t.id}` : t.id;
        } catch (e) {
          transferError = String(e);
        }
      }
    }
    const mowerAmount = mowerPence / 100;
    const commissionAmount = Math.round((capturedAmount - mowerAmount) * 100) / 100;

    await admin
      .from('bookings')
      .update({
        status: 'completed',
        payment_status: 'captured',
        captured_amount: capturedAmount,
        transfer_id: transferId,
        mower_amount: mowerAmount,
        commission_amount: commissionAmount,
        completed_at: new Date().toISOString(),
      })
      .eq('id', bookingId);

    return json({
      ok: true,
      captured: true,
      amount: capturedAmount,
      mowerAmount,
      commissionAmount,
      topUpCharged,
      topUpError,
      transferError,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
