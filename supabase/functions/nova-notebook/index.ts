// Carnet Lumi (type NotebookLM) : réponses UNIQUEMENT à partir des sources de l'élève.
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

async function generate(system: string, prompt: string, asJson: boolean, image?: { data: string; mime: string }): Promise<string> {
  const gem = Deno.env.get('GEMINI_API_KEY');
  const ant = Deno.env.get('ANTHROPIC_API_KEY');
  const errs: string[] = [];
  if (gem) {
    for (const m of ['gemini-flash-latest', 'gemini-3.8-flash', 'gemini-flash-lite-latest']) {
      try {
        const parts: any[] = [{ text: prompt }];
        if (image) parts.push({ inlineData: { mimeType: image.mime, data: image.data } });
        const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`, {
          method: 'POST',
          signal: AbortSignal.timeout(45000),
          headers: { 'Content-Type': 'application/json', 'x-goog-api-key': gem },
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: system }] },
            contents: [{ role: 'user', parts }],
            generationConfig: { maxOutputTokens: 3500, temperature: 0.3, ...(asJson ? { responseMimeType: 'application/json' } : {}) },
          }),
        });
        if (res.ok) {
          const j = await res.json();
          const t = (j.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? '').join('').trim();
          if (t) return t;
          errs.push(`${m} vide`);
          continue;
        }
        errs.push(`${m} ${res.status}`);
        if (res.status !== 404 && res.status !== 400) break;
      } catch (e) {
        errs.push(`${m} ${String(e).slice(0, 60)}`);
      }
    }
  }
  if (ant && !image) {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      signal: AbortSignal.timeout(45000),
      headers: { 'Content-Type': 'application/json', 'x-api-key': ant, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({
        model: Deno.env.get('AI_MODEL') || 'claude-haiku-5-5',
        max_tokens: 3500,
        system,
        messages: [{ role: 'user', content: prompt }],
      }),
    });
    if (res.ok) {
      const j = await res.json();
      return (j.content ?? []).map((p: any) => p.text ?? '').join('').trim();
    }
    errs.push(`anthropic ${res.status}`);
  }
  throw new Error(errs.join(' | ') || 'aucune clé IA configurée');
}
const parse = (t: string) => JSON.parse(t.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '').trim());

const RULES =
  "Tu es Lumi, assistant d'étude. Tu travailles UNIQUEMENT à partir des SOURCES fournies par l'élève. " +
  "N'utilise aucune connaissance extérieure pour les faits : si la réponse n'est pas dans les sources, dis-le clairement. " +
  "Écris en français simple, maths en texte lisible avec symboles Unicode (x², √x, ≤, a/b), jamais de LaTeX ni de $. **gras** autorisé, pas de titres avec #.";

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
  const { data: { user } } = await db.auth.getUser(jwt);
  if (!user) return json(401, { error: 'non connecté' });
  try {
    const b = await req.json();
    const action = String(b.action ?? '');
    const dayAgo = new Date(Date.now() - 24 * 3600_000).toISOString();
    const { count } = await db.from('edu_gen_log').select('id', { count: 'exact', head: true })
      .eq('user_id', user.id).gt('created_at', dayAgo);
    if ((count ?? 0) >= 60) return json(429, { error: "Limite du jour atteinte. Reviens demain !" });
    await db.from('edu_gen_log').insert({ user_id: user.id });

    if (action === 'ocr') {
      const data = String(b.image ?? '');
      if (!data || data.length > 6_000_000) return json(400, { error: 'image invalide ou trop lourde' });
      const text = await generate(
        'Tu transcris fidèlement le texte de photos de cours.',
        "Recopie fidèlement tout le texte visible sur cette photo de cours (maths en texte lisible, sans LaTeX). Ne commente pas, n'ajoute rien. S'il n'y a pas de texte, réponds seulement : AUCUN TEXTE.",
        false, { data, mime: String(b.mime ?? 'image/jpeg') });
      return json(200, { text: text.slice(0, 20000) });
    }

    let q = db.from('edu_sources').select('id,title,content').eq('user_id', user.id).order('created_at');
    if (Array.isArray(b.source_ids) && b.source_ids.length) q = q.in('id', b.source_ids.slice(0, 20));
    const { data: srcs } = await q;
    if (!srcs?.length) return json(400, { error: 'Ajoute d\'abord au moins une source.' });
    let budget = 30000;
    const ctx = srcs.map((s, i) => {
      const c = s.content.slice(0, Math.max(0, Math.min(12000, budget)));
      budget -= c.length;
      return `[${i + 1}] ${s.title}\n${c}`;
    }).join('\n\n');
    const names = srcs.map((s, i) => `[${i + 1}] ${s.title}`).join(' ; ');

    if (action === 'ask') {
      const question = String(b.question ?? '').trim().slice(0, 1000);
      if (!question) return json(400, { error: 'question vide' });
      const answer = await generate(RULES,
        `SOURCES :\n${ctx}\n\nQUESTION : ${question}\n\nRéponds à partir des sources et cite le numéro de la source entre crochets, ex. [1]. Sources disponibles : ${names}.`, false);
      return json(200, { answer: answer.slice(0, 4000) });
    }
    if (action === 'make') {
      const type = String(b.type ?? '');
      if (type === 'quiz') {
        const out = parse(await generate(RULES,
          `SOURCES :\n${ctx}\n\nCrée un quiz de 8 questions à choix multiples (4 propositions, une seule bonne) UNIQUEMENT sur le contenu des sources. JSON : {"questions":[{"q":"...","options":["...","...","...","..."],"answer":0,"explain":"..."}]}`, true));
        const qs = (out.questions ?? []).filter((x: any) => x && typeof x.q === 'string' && Array.isArray(x.options) &&
          x.options.length === 4 && Number.isInteger(x.answer) && x.answer >= 0 && x.answer <= 3).slice(0, 10);
        if (qs.length < 3) throw new Error('quiz invalide');
        return json(200, { questions: qs });
      }
      if (type === 'cards') {
        const out = parse(await generate(RULES,
          `SOURCES :\n${ctx}\n\nCrée 12 fiches de révision (recto = question ou notion, verso = réponse courte) UNIQUEMENT à partir des sources. JSON : {"cards":[{"front":"...","back":"..."}]}`, true));
        const cards = (out.cards ?? []).filter((x: any) => x && x.front && x.back).slice(0, 20);
        if (cards.length < 3) throw new Error('fiches invalides');
        return json(200, { cards });
      }
      const tasks: Record<string, string> = {
        summary: "Fais un résumé clair et structuré des sources : l'essentiel, les définitions, les formules ou dates clés. Court.",
        guide: "Fais un guide d'étude : points clés à maîtriser, vocabulaire, méthode, 5 questions de réflexion avec leurs réponses brèves.",
        faq: "Fais une FAQ : 8 questions que se poserait un élève sur ces sources, avec une réponse courte à chacune.",
      };
      if (!tasks[type]) return json(400, { error: 'type inconnu' });
      const text = await generate(RULES, `SOURCES :\n${ctx}\n\n${tasks[type]}`, false);
      return json(200, { text: text.slice(0, 6000) });
    }
    return json(400, { error: 'action inconnue' });
  } catch (e) {
    console.log('nova-notebook error', String(e));
    try {
      await db.from('app_config').upsert({ key: 'ai_last_error', value: `${new Date().toISOString()} notebook ${String(e).slice(0, 300)}` });
    } catch (_) { /* ignore */ }
    return json(500, { error: "Lumi n'a pas pu répondre. Réessaie dans un instant." });
  }
});
