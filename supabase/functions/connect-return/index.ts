// MOWR — Edge Function: connect-return
//
// Landing page Stripe redirects the browser to after Connect onboarding (both
// the return_url and refresh_url point here). It just tells the mower to go
// back to the MOWR app, which then calls connect-status to sync.
//
// This page is opened by a plain browser redirect with NO auth token, so it
// must be deployed WITHOUT JWT verification:
//     supabase functions deploy connect-return --no-verify-jwt

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>MOWR — payout setup</title>
  <style>
    body { margin:0; font-family:-apple-system,Segoe UI,Roboto,sans-serif;
           background:#F7F8F5; color:#1b1b1b; display:flex; min-height:100vh;
           align-items:center; justify-content:center; }
    .card { background:#fff; border-radius:20px; padding:32px 28px; max-width:360px;
            text-align:center; box-shadow:0 8px 30px rgba(0,0,0,.08); }
    .dot { width:56px; height:56px; border-radius:50%; background:#2E7D32;
           color:#fff; font-size:28px; display:flex; align-items:center;
           justify-content:center; margin:0 auto 16px; }
    h1 { font-size:20px; margin:0 0 8px; }
    p { color:#555; font-size:15px; line-height:1.5; margin:0; }
  </style>
</head>
<body>
  <div class="card">
    <div class="dot">&#10003;</div>
    <h1>All done here</h1>
    <p>You can close this tab and return to the MOWR app. Tap
       <b>Refresh status</b> to finish setting up payouts.</p>
  </div>
</body>
</html>`;

Deno.serve(() => {
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
});
