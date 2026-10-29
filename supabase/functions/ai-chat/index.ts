// Discussion directe avec l'assistant IA de Chat Elvidio.
// Clés (secrets de fonction) : GEMINI_API_KEY (gratuit) ou ANTHROPIC_API_KEY ; AI_MODEL optionnel.
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

type Turn = { role: 'user' | 'assistant'; text: string };

async function generate(system: string, convo: Turn[]): Promise<string> {
  const gem = Deno.env.get('GEMINI_API_KEY');
  const ant = Deno.env.get('ANTHROPIC_API_KEY');
  const custom = Deno.env.get('AI_MODEL');
  if (gem) {
    const models = custom ? [custom] : ['gemini-flash-latest', 'gemini-3.8-flash', 'gemini-flash-lite-latest'];
    let last = '';
    const all: string[] = [];
    for (const m of models) {
      let res: Response;
      try {
        res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`, {
        method: 'POST',
        signal: AbortSignal.timeout(14000),
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': gem },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: system }] },
          contents: convo.map((c) => ({ role: c.role === 'user' ? 'user' : 'model', parts: [{ text: c.text }] })),
          generationConfig: {
            maxOutputTokens: 1000,
            temperature: 0.7,
            ...(m.startsWith('gemini-2.5') ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
          },
        }),
      });
      } catch (e) {
        last = `gemini ${m} ${String(e)}`;
        continue; // délai dépassé : on essaie le modèle suivant
      }
      if (res.ok) {
        const j = await res.json();
        const t = (j.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? '').join('').trim();
        if (t) return t;
        last = 'réponse vide';
        continue;
      }
      last = `gemini ${m} ${res.status} ${(await res.text()).slice(0, 120)}`;
      all.push(last);
      if (res.status !== 404 && res.status !== 400) break; // quota, clé... : inutile d'essayer un autre modèle
    }
    throw new Error(all.join(' | ') || last);
  }
  if (ant) {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      signal: AbortSignal.timeout(25000),
      headers: { 'Content-Type': 'application/json', 'x-api-key': ant, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({
        model: custom || 'claude-haiku-5-5',
        max_tokens: 800,
        system,
        messages: convo.map((c) => ({ role: c.role, content: c.text })),
      }),
    });
    if (!res.ok) throw new Error('anthropic ' + res.status + ' ' + (await res.text()).slice(0, 200));
    const j = await res.json();
    return (j.content ?? []).map((p: any) => p.text ?? '').join('').trim();
  }
  throw new Error('aucune clé IA configurée');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
  const { data: { user } } = await db.auth.getUser(jwt);
  if (!user) return json(401, { error: 'non connecté' });
  try {
    const { text } = await req.json();
    const msg = (text ?? '').toString().trim().slice(0, 2000);
    if (!msg) return json(400, { error: 'message vide' });

    const hourAgo = new Date(Date.now() - 3600_000).toISOString();
    const [{ count }, { data: me }, { data: hist }] = await Promise.all([
      db.from('ai_chats').select('id', { count: 'exact', head: true })
        .eq('user_id', user.id).eq('role', 'user').gt('created_at', hourAgo),
      db.from('profiles').select('pseudo').eq('id', user.id).maybeSingle(),
      db.from('ai_chats').select('role, content')
        .eq('user_id', user.id).order('created_at', { ascending: false }).limit(12),
    ]);
    if ((count ?? 0) >= 40) return json(429, { error: 'Tu as beaucoup discuté : réessaie dans un moment.' });
    const convo: Turn[] = [];
    for (const h of (hist ?? []).reverse()) convo.push({ role: h.role, text: h.content });
    convo.push({ role: 'user', text: msg });
    while (convo.length > 1 && convo[0].role !== 'user') convo.shift();

    const today = new Date().toLocaleDateString('fr-FR', { dateStyle: 'full', timeZone: 'Africa/Porto-Novo' });
    const first = convo.length <= 1;
    const system =
      `Tu es « Elvidio IA », l'assistant intelligent intégré à l'application Chat Elvidio. Nous sommes le ${today}. ` +
      `L'utilisateur s'appelle ${me?.pseudo ?? 'inconnu'} (n'utilise son prénom que très rarement, jamais à chaque message). ` +
      `${first ? 'C\'est le début de la discussion : tu peux saluer une seule fois, brièvement.' : 'La discussion est déjà en cours : NE SALUE PAS et ne demande PAS « comment ça va » ; va directement au fond.'} ` +
      `Réponds d'abord précisément à ce qui est demandé, sans formule d'introduction ni remplissage. ` +
      `Sois vraiment utile et intelligent : raisonne, donne des explications claires, des exemples concrets, des étapes quand il le faut, et propose la suite utile. ` +
      `Adapte la longueur : court pour une question simple, détaillé pour un sujet complexe ou un cours. ` +
      `Pose une question de clarification seulement si c'est indispensable. ` +
      `Réponds dans la langue de l'utilisateur (français par défaut), ton naturel et chaleureux, comme un ami compétent. ` +
      `Tu peux aider à : répondre à des questions, expliquer, réviser (maths, sciences, philosophie…), rédiger des messages, coder, planifier, proposer des idées. ` +
      `FORMULES : écris toujours les mathématiques en texte simple et lisible par un humain, avec des symboles Unicode (x², √x, ≤, ≥, ≠, ×, ÷, π, ∞, Σ, ℝ, ℕ, ∈, ⇒, uₙ₊₁, a/b pour les fractions, lim n→∞). N'utilise JAMAIS LaTeX : aucun $, aucun \\frac, \\sqrt, \\leq, ^{}, _{} ni autre commande avec une barre oblique inverse. Pas de titres avec #. ` +
      `Sois honnête : si tu ne sais pas ou si l'information peut avoir changé, dis-le au lieu d'inventer. ` +
      `Pour la santé, le droit ou l'argent, donne des informations générales et conseille un professionnel. ` +
      `Refuse poliment ce qui est dangereux ou illégal. Ne prétends pas être humain.`;

    const reply = (await generate(system, convo)).slice(0, 3500);
    const saved = Promise.resolve(db.from('ai_chats').insert([
      { user_id: user.id, role: 'user', content: msg },
      { user_id: user.id, role: 'assistant', content: reply },
    ]));
    // Répond tout de suite ; l'enregistrement de l'historique finit en arrière-plan.
    // @ts-ignore EdgeRuntime est fourni par Supabase
    if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(saved); else await saved;
    return json(200, { reply });
  } catch (e) {
    console.log('ai-chat error', String(e));
    // Dernière erreur gardée pour le diagnostic (jamais la clé : seulement le message du service).
    try {
      await db.from('app_config').upsert({ key: 'ai_last_error', value: `${new Date().toISOString()} ${String(e).slice(0, 400)}` });
    } catch (_) { /* ignore */ }
    return json(500, { error: 'L\'assistant n\'est pas disponible pour le moment.' });
  }
});
