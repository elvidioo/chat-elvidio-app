// Renvoie des identifiants TURN (relais d'appel) aux utilisateurs connectés.
// Secrets Supabase requis : METERED_APP (ex: monapp.metered.live) et METERED_API_KEY.
const headers = { 'Content-Type': 'application/json' };

Deno.serve(async () => {
  const app = Deno.env.get('METERED_APP');
  const key = Deno.env.get('METERED_API_KEY');
  if (!app || !key) {
    return new Response(JSON.stringify({ configured: false }), { headers });
  }
  try {
    const r = await fetch(`https://${app}/api/v1/turn/credentials?apiKey=${key}`);
    if (!r.ok) {
      console.log('metered error', r.status);
      return new Response(JSON.stringify({ configured: false }), { headers });
    }
    const iceServers = await r.json();
    return new Response(JSON.stringify({ configured: true, iceServers }), { headers });
  } catch (e) {
    console.log('turn error', String(e));
    return new Response(JSON.stringify({ configured: false }), { headers });
  }
});
