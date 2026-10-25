// Renvoie des serveurs de relais d'appel (TURN) aux utilisateurs connectés.
// Option A (simple) : secrets TURN_USERNAME et TURN_PASSWORD (page « Informations d'identification » de Metered).
// Option B : secrets METERED_APP (ex: monapp.metered.live) et METERED_API_KEY.
const headers = { 'Content-Type': 'application/json' };
const reply = (body: unknown) => new Response(JSON.stringify(body), { headers });

Deno.serve(async () => {
  const user = Deno.env.get('TURN_USERNAME');
  const pass = Deno.env.get('TURN_PASSWORD');
  if (user && pass) {
    return reply({
      configured: true,
      iceServers: [
        { urls: 'stun:stun.relay.metered.ca:80' },
        {
          urls: [
            'turn:global.relay.metered.ca:80',
            'turn:global.relay.metered.ca:80?transport=tcp',
            'turn:global.relay.metered.ca:443',
            'turns:global.relay.metered.ca:443?transport=tcp',
          ],
          username: user,
          credential: pass,
        },
      ],
    });
  }
  const app = Deno.env.get('METERED_APP');
  const key = Deno.env.get('METERED_API_KEY');
  if (!app || !key) return reply({ configured: false });
  try {
    const r = await fetch(`https://${app}/api/v1/turn/credentials?apiKey=${key}`);
    if (!r.ok) {
      console.log('metered error', r.status);
      return reply({ configured: false });
    }
    return reply({ configured: true, iceServers: await r.json() });
  } catch (e) {
    console.log('turn error', String(e));
    return reply({ configured: false });
  }
});
