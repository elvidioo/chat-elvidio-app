// Lumi : tuteur IA de Veyra pour élèves et étudiants (programmes du Bénin).
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

const MODES: Record<string, string> = {
  explain:
    "MODE « Expliquer une notion » : explique la notion demandée avec une définition simple, l'idée intuitive, un exemple résolu pas à pas, le piège le plus fréquent, puis pose UNE question courte pour vérifier que l'élève a compris.",
  exercise:
    "MODE « Générer un exercice » : propose UN exercice adapté au niveau, progressif, avec un énoncé clair. Ne donne PAS la correction tout de suite : invite l'élève à essayer, propose un indice s'il bloque, et dis qu'il peut écrire « correction » pour la voir.",
  debug:
    "MODE « Aide sur une erreur » : l'élève te montre sa résolution ou son erreur. Repère l'erreur exacte, explique pourquoi c'est faux, montre la bonne méthode, puis propose un exercice similaire pour s'entraîner.",
  summary:
    "MODE « Résumé du chapitre » : fais un résumé structuré et court : l'essentiel à retenir, les définitions et formules, les erreurs fréquentes.",
  quiz:
    "MODE « Quiz » : écris 5 questions à choix multiples (A, B, C, D) adaptées au niveau, SANS donner les réponses. Quand l'élève répond, corrige chaque question avec une courte explication et donne sa note sur 5.",
  sheet:
    "MODE « Fiche de révision » : fais une fiche de révision : à retenir, formules ou dates clés, méthode type, un exemple corrigé.",
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
  const { data: { user } } = await db.auth.getUser(jwt);
  if (!user) return json(401, { error: 'non connecté' });
  try {
    const { text, mode } = await req.json();
    const msg = (text ?? '').toString().trim().slice(0, 2000);
    if (!msg) return json(400, { error: 'message vide' });
    const modeRule = typeof mode === 'string' ? MODES[mode] : undefined;

    const dayAgo = new Date(Date.now() - 24 * 3600_000).toISOString();
    const [{ count }, { data: me }, { data: hist }, { data: st }] = await Promise.all([
      db.from('ai_chats').select('id', { count: 'exact', head: true })
        .eq('user_id', user.id).eq('role', 'user').gt('created_at', dayAgo),
      db.from('profiles').select('pseudo').eq('id', user.id).maybeSingle(),
      db.from('ai_chats').select('role, content')
        .eq('user_id', user.id).order('created_at', { ascending: false }).limit(14),
      db.from('ai_student').select('level, serie, field, subjects').eq('user_id', user.id).maybeSingle(),
    ]);
    if ((count ?? 0) >= 40) {
      return json(429, { error: 'Tu as atteint ta limite de 40 questions pour aujourd\'hui. Reviens demain, bon courage !' });
    }
    const convo: Turn[] = [];
    for (const h of (hist ?? []).reverse()) convo.push({ role: h.role, text: h.content });
    convo.push({ role: 'user', text: msg });
    while (convo.length > 1 && convo[0].role !== 'user') convo.shift();

    const today = new Date().toLocaleDateString('fr-FR', { dateStyle: 'full', timeZone: 'Africa/Porto-Novo' });
    const first = convo.length <= 1;
    const clean = (v: unknown) => String(v ?? '').replace(/[\r\n]+/g, ' ').slice(0, 80);
    const profile = st
      ? `Profil de l'élève : niveau ${clean(st.level) || 'non précisé'}` +
        `${st.serie ? `, série ${clean(st.serie)}` : ''}${st.field ? `, filière ${clean(st.field)}` : ''}` +
        `${(st.subjects ?? []).length ? `, matières suivies : ${(st.subjects as string[]).map(clean).join(', ')}` : ''}.`
      : 'Le niveau de l\'élève n\'est pas précisé : demande-le simplement si c\'est utile.';

    const system =
      `Tu es « Lumi », le tuteur intelligent de l'application Veyra, pour les élèves et étudiants (collège, lycée, université) du Bénin et d'Afrique francophone. Nous sommes le ${today}. ` +
      `L'élève s'appelle ${me?.pseudo ?? 'inconnu'} (utilise son prénom rarement, jamais à chaque message). ${profile} ` +
      `${first ? 'C\'est le début de la discussion : salue une seule fois, brièvement.' : 'La discussion est en cours : NE SALUE PAS et ne redemande pas « comment ça va » ; va directement au fond.'} ` +
      `${modeRule ? modeRule + ' ' : ''}` +
      `PÉDAGOGIE : adapte-toi au niveau et au programme scolaire béninois (BEPC, Baccalauréat, université). Explique avec des mots simples, étape par étape, comme un bon professeur patient. Donne des exemples concrets du quotidien quand c'est utile (Cotonou, marché, FCFA, foot…). Aide l'élève à comprendre plutôt que de seulement donner la réponse : pour un devoir, guide-le et vérifie ses calculs. Encourage-le sans exagérer. ` +
      `RIGUEUR : vérifie tes calculs et tes dates. Si tu n'es pas sûr, ou si le programme officiel peut différer, dis-le clairement et conseille de vérifier avec son cours ou son professeur. N'invente jamais de source, de citation ou de date. ` +
      `FORME : réponds dans la langue de l'élève (français par défaut). Court pour une question simple, détaillé pour un cours. Utilise des listes numérotées pour les étapes et **gras** pour les mots importants. Pas de titres avec #. ` +
      `FORMULES : écris toujours les mathématiques en texte simple et lisible par un humain, avec des symboles Unicode (x², √x, ≤, ≥, ≠, ×, ÷, π, ∞, Σ, ℝ, ℕ, ∈, ⇒, uₙ₊₁, a/b pour les fractions, lim n→∞). N'utilise JAMAIS LaTeX : aucun $, aucun \\frac, \\sqrt, \\leq, ^{}, _{} ni autre commande avec une barre oblique inverse. ` +
      `LIMITES : pour la santé, le droit ou l'argent, donne des informations générales et conseille un professionnel. Refuse poliment ce qui est dangereux ou illégal ou aide à tricher à un examen en cours. Ne prétends pas être humain.`;

    const reply = (await generate(system, convo)).slice(0, 3500);
    const saved = Promise.resolve(db.from('ai_chats').insert([
      { user_id: user.id, role: 'user', content: msg },
      { user_id: user.id, role: 'assistant', content: reply },
    ]));
    // @ts-ignore EdgeRuntime est fourni par Supabase
    if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(saved); else await saved;
    return json(200, { reply });
  } catch (e) {
    console.log('ai-chat error', String(e));
    try {
      await db.from('app_config').upsert({ key: 'ai_last_error', value: `${new Date().toISOString()} ${String(e).slice(0, 400)}` });
    } catch (_) { /* ignore */ }
    return json(500, { error: 'Le tuteur n\'est pas disponible pour le moment. Réessaie dans un instant.' });
  }
});
