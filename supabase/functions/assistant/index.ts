// MOWR — Supabase Edge Function: assistant
//
// The merged AI chat assistant. A customer chats in plain English; Claude
// answers support questions AND does what they ask against their own records:
// list bookings, reschedule, cancel, respond to a mower's on-site re-price, or
// escalate to a human. Booking a NEW job is handed back to the app's existing
// flow (map-draw + payment) via a client action — money stays human-in-the-loop.
//
// Every record action runs through a user-scoped Supabase client, so RLS + the
// SECURITY DEFINER RPCs (0019) scope everything to the signed-in customer. The
// function never sees a card number and never captures money.
//
// Request body:  { "messages": [{ "role": "user"|"assistant", "content": "…" }] }
// Response:      { "reply": "…", "action": { "type": "start_booking" } | null }
//
// Secrets (set as edge-function secrets, never in code):
//   ANTHROPIC_API_KEY   — the Claude key (rotate the one pasted in chat)
//   SUPABASE_URL / SUPABASE_ANON_KEY — injected by the platform

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') as string;
const MODEL = 'claude-opus-4-8';
const MAX_TOOL_ROUNDS = 6;

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

// Today, in the UK, so the model can resolve "next Tuesday" etc. correctly.
function todayLondon(): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/London',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

const SYSTEM = (today: string) => `
You are the MOWR assistant. MOWR is an on-demand lawn-mowing marketplace in the
UK: a customer books a mow, a vetted local "mower" turns up and does it, and
they pay by card. The only services are **mowing** and **edging** (edging is an
optional add-on within a mow) — never offer or imply any other service.

Today's date is ${today} (Europe/London). Resolve relative dates ("tomorrow",
"next Tuesday") against it and always pass dates to tools as YYYY-MM-DD.

You are chatting with a signed-in customer. You can:
- Answer questions about MOWR, pricing, and how it works.
- Look up their bookings (get_my_bookings) and explain status/price.
- Reschedule a booking (reschedule_booking) — only before the job is done.
- Cancel a booking (cancel_booking).
- Respond to a mower's on-site re-measure when the price changed enough to need
  their approval (respond_to_revision).
- Help them start a NEW booking (start_booking) — this hands them to the app's
  booking screen so they can draw their lawn on the map and pay. You do NOT take
  measurements, prices, or card details yourself.
- Escalate to a human when you cannot resolve something (escalate_support).

Rules:
- Never invent booking details, prices, dates, or statuses. Call
  get_my_bookings and use what it returns. If they have several bookings and
  it's ambiguous which one they mean, ask before acting.
- Cancelling and rescheduling change real records. Before you call
  cancel_booking or reschedule_booking, briefly confirm the specific booking and
  the change with the customer in your reply, then act once they say yes.
- If a tool returns an error, explain it plainly and offer escalate_support.
- Keep replies short, friendly, and concrete. Prices are in GBP (£).
`.trim();

// Tool schemas. get_my_bookings / the four record actions run server-side;
// start_booking is a CLIENT action — the function returns it to the app.
const TOOLS = [
  {
    name: 'get_my_bookings',
    description:
      "List the signed-in customer's bookings (newest first) with status, " +
      'schedule, address and prices. Call this before answering anything about ' +
      'their existing bookings or before reschedule/cancel/approve.',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'reschedule_booking',
    description:
      'Move a booking to a new date/time window. Only works before the job is ' +
      'completed. Confirm the booking and new date with the customer first.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string', description: 'The booking id (from get_my_bookings).' },
        date: { type: 'string', description: 'New date, YYYY-MM-DD.' },
        window: {
          type: 'string',
          enum: ['any', 'morning', 'afternoon', 'evening'],
          description: 'Preferred time window.',
        },
      },
      required: ['booking_id', 'date'],
    },
  },
  {
    name: 'cancel_booking',
    description:
      'Cancel a booking. Payment is only held (not taken) until a job is done, ' +
      'so cancelling before completion releases the hold. Confirm with the ' +
      'customer first.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string', description: 'The booking id (from get_my_bookings).' },
      },
      required: ['booking_id'],
    },
  },
  {
    name: 'respond_to_revision',
    description:
      "Approve or decline a mower's on-site re-measure when the price change " +
      'was large enough to need the customer\'s agreement (approval_status is ' +
      '"pending"). Approving lets the revised price be charged; declining keeps ' +
      'the originally-agreed price.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string', description: 'The booking id (from get_my_bookings).' },
        approve: { type: 'boolean', description: 'true to approve the revised price, false to decline.' },
      },
      required: ['booking_id', 'approve'],
    },
  },
  {
    name: 'start_booking',
    description:
      'Open the app\'s booking flow so the customer can book a NEW mow — they ' +
      'draw their lawn on the map and pay there. Use this whenever they want to ' +
      'book a new job; do not try to take measurements or payment yourself.',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'escalate_support',
    description:
      'Open a support ticket for a human operator when you cannot resolve the ' +
      "customer's issue. Summarise the problem clearly.",
    input_schema: {
      type: 'object',
      properties: {
        summary: { type: 'string', description: 'One or two sentences describing the issue.' },
      },
      required: ['summary'],
    },
  },
];

// deno-lint-ignore no-explicit-any
async function runServerTool(client: any, name: string, input: any) {
  switch (name) {
    case 'get_my_bookings': {
      const { data, error } = await client
        .from('bookings')
        .select(
          'id, status, asap, scheduled_date, time_window, total_amount, ' +
            'revised_total, captured_amount, approval_status, currency, ' +
            'created_at, properties(line1, city, postcode)',
        )
        .order('created_at', { ascending: false });
      if (error) return { error: error.message };
      return { bookings: data ?? [] };
    }
    case 'reschedule_booking': {
      const { error } = await client.rpc('reschedule_booking', {
        p_booking_id: input.booking_id,
        p_date: input.date,
        p_window: input.window ?? 'any',
      });
      return error ? { error: error.message } : { ok: true };
    }
    case 'cancel_booking': {
      const { error } = await client.rpc('cancel_booking', {
        p_booking_id: input.booking_id,
      });
      return error ? { error: error.message } : { ok: true };
    }
    case 'respond_to_revision': {
      const { error } = await client.rpc('respond_to_revision', {
        p_booking_id: input.booking_id,
        p_approve: input.approve,
      });
      return error ? { error: error.message } : { ok: true };
    }
    case 'escalate_support': {
      const { data, error } = await client.rpc('escalate_support', {
        p_summary: input.summary,
      });
      return error ? { error: error.message } : { ok: true, ticket_id: data };
    }
    default:
      return { error: `Unknown tool: ${name}` };
  }
}

// deno-lint-ignore no-explicit-any
async function callClaude(system: string, messages: any[]) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1024,
      system,
      tools: TOOLS,
      messages,
    }),
  });
  if (!res.ok) {
    throw new Error(`Claude API ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

// deno-lint-ignore no-explicit-any
function textOf(content: any[]): string {
  return content
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    if (!ANTHROPIC_API_KEY) {
      return json({ error: 'Assistant is not configured yet.' }, 503);
    }
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization' }, 401);

    const body = await req.json().catch(() => ({}));
    const incoming = Array.isArray(body.messages) ? body.messages : [];
    if (incoming.length === 0) return json({ error: 'No messages' }, 400);

    // User-scoped client: every read/RPC runs as the signed-in customer, so RLS
    // and the SECURITY DEFINER functions confine everything to their own data.
    const client = createClient(
      Deno.env.get('SUPABASE_URL') as string,
      Deno.env.get('SUPABASE_ANON_KEY') as string,
      { global: { headers: { Authorization: authHeader } } },
    );
    const {
      data: { user },
    } = await client.auth.getUser();
    if (!user) return json({ error: 'Not authenticated' }, 401);

    const system = SYSTEM(todayLondon());
    // Normalise incoming to the API shape (string content is accepted).
    // deno-lint-ignore no-explicit-any
    const messages: any[] = incoming
      .filter((m: { role?: string; content?: unknown }) =>
        (m.role === 'user' || m.role === 'assistant') &&
        typeof m.content === 'string' && m.content.trim().length > 0)
      .map((m: { role: string; content: string }) => ({
        role: m.role,
        content: m.content,
      }));

    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const resp = await callClaude(system, messages);
      const content = resp.content ?? [];

      if (resp.stop_reason !== 'tool_use') {
        return json({ reply: textOf(content) || '…', action: null });
      }

      // Booking hand-off short-circuits the loop: return control to the app.
      const startBooking = content.find(
        // deno-lint-ignore no-explicit-any
        (b: any) => b.type === 'tool_use' && b.name === 'start_booking',
      );
      if (startBooking) {
        return json({
          reply: textOf(content) ||
            "Let's get your new mow booked — I'll open the booking screen for you.",
          action: { type: 'start_booking' },
        });
      }

      // Run every requested server tool and feed the results back.
      messages.push({ role: 'assistant', content });
      const toolResults = [];
      for (const block of content) {
        if (block.type !== 'tool_use') continue;
        const result = await runServerTool(client, block.name, block.input ?? {});
        toolResults.push({
          type: 'tool_result',
          tool_use_id: block.id,
          content: JSON.stringify(result),
          is_error: result != null && 'error' in result,
        });
      }
      messages.push({ role: 'user', content: toolResults });
    }

    // Ran out of tool rounds — bail gracefully rather than loop forever.
    return json({
      reply:
        "Sorry, I'm having trouble completing that. Would you like me to pass " +
        'this to a human?',
      action: null,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
