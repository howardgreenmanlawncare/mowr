// MOWR — Edge Function: weather-sweep
//
// Nightly weather-aware scheduling (keyless Open-Meteo — no API key needed).
// For each upcoming job it reads the forecast at the property and:
//   * flags the job rain_risk / clear (set_job_weather) so mowrs can pick up
//     DRY work nearby when their own area is wet;
//   * if the job is rained off *tomorrow*, moves recurring jobs to the next dry
//     day (weather_reschedule) instead of skipping a week. One-offs are flagged
//     so the customer is nudged to reschedule (they approve the move).
//
// Env required (defaults exist for the Supabase-provided ones):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy: supabase functions deploy weather-sweep
// Schedule: pg_cron + pg_net, nightly ~20:00 (see 0027_weather.sql).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// Rain thresholds.
const RAIN_PROB = 60;   // % chance of precip → too wet to mow
const RAIN_MM = 4;      // or this much rain (mm) in the day
const DRY_PROB = 40;    // a "dry enough" day to move a job to
const DRY_MM = 2;
const LOOKAHEAD_DAYS = 7;

interface Daily { time: string[]; precipitation_probability_max: (number | null)[]; precipitation_sum: (number | null)[]; }

function ymd(d: Date): string { return d.toISOString().slice(0, 10); }

async function forecast(lat: number, lng: number): Promise<Daily | null> {
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(3)}` +
    `&longitude=${lng.toFixed(3)}&daily=precipitation_probability_max,precipitation_sum` +
    `&forecast_days=${LOOKAHEAD_DAYS}&timezone=Europe%2FLondon`;
  try {
    const r = await fetch(url);
    if (!r.ok) return null;
    const j = await r.json();
    return j.daily ?? null;
  } catch {
    return null;
  }
}

function isWet(daily: Daily, date: string): boolean | null {
  const i = daily.time.indexOf(date);
  if (i < 0) return null;
  const p = daily.precipitation_probability_max?.[i] ?? 0;
  const mm = daily.precipitation_sum?.[i] ?? 0;
  return (p ?? 0) >= RAIN_PROB || (mm ?? 0) >= RAIN_MM;
}

function nextDryDate(daily: Daily, afterDate: string): string | null {
  for (let i = 0; i < daily.time.length; i++) {
    const d = daily.time[i];
    if (d <= afterDate) continue;
    const p = daily.precipitation_probability_max?.[i] ?? 0;
    const mm = daily.precipitation_sum?.[i] ?? 0;
    if ((p ?? 0) < DRY_PROB && (mm ?? 0) < DRY_MM) return d;
  }
  return null;
}

Deno.serve(async () => {
  const supa = createClient(SUPABASE_URL, SERVICE_KEY);
  const today = new Date();
  const from = ymd(today);
  const toDate = new Date(today); toDate.setDate(toDate.getDate() + 4);
  const to = ymd(toDate);
  const tomorrow = ymd(new Date(today.getTime() + 86400000));

  // Upcoming, still-schedulable jobs with a located property.
  const { data: jobs, error } = await supa
    .from('bookings')
    .select('id, scheduled_date, status, recurrence_interval_days, properties(lat, lng)')
    .in('status', ['confirmed', 'broadcast', 'accepted'])
    .gte('scheduled_date', from)
    .lte('scheduled_date', to);

  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    });
  }

  // Batch forecasts by rounded location to cut API calls.
  const cache = new Map<string, Daily | null>();
  let flagged = 0, moved = 0, skipped = 0;

  for (const b of jobs ?? []) {
    const prop = (b as { properties?: { lat?: number; lng?: number } }).properties;
    const lat = prop?.lat, lng = prop?.lng;
    if (lat == null || lng == null) { skipped++; continue; }

    const key = `${lat.toFixed(2)},${lng.toFixed(2)}`;
    if (!cache.has(key)) cache.set(key, await forecast(lat, lng));
    const daily = cache.get(key);
    if (!daily) { skipped++; continue; }

    const wet = isWet(daily, b.scheduled_date as string);
    if (wet == null) { skipped++; continue; }

    await supa.rpc('set_job_weather', {
      p_booking_id: b.id,
      p_rain_risk: wet,
      p_note: wet ? 'Rain forecast for this date.' : null,
    });
    flagged++;

    // Rained off tomorrow → move recurring jobs to the next dry day.
    const recurring = ((b as { recurrence_interval_days?: number }).recurrence_interval_days ?? 0) > 0;
    if (wet && b.scheduled_date === tomorrow && recurring) {
      const dry = nextDryDate(daily, b.scheduled_date as string);
      if (dry) {
        await supa.rpc('weather_reschedule', {
          p_booking_id: b.id,
          p_new_date: dry,
          p_note: `Rain was forecast, so we moved your recurring mow to ${dry} — the next dry day.`,
        });
        moved++;
      }
    }
  }

  return new Response(
    JSON.stringify({ ok: true, checked: jobs?.length ?? 0, flagged, moved, skipped }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
