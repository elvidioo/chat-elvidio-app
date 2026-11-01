// Lumi (éducation) : génère et met en cache chapitres, leçons et quiz.
// Secrets : GEMINI_API_KEY (ou ANTHROPIC_API_KEY). Jamais de clé dans l'application.
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

async function generate(system: string, prompt: string, asJson: boolean): Promise<string> {
  const gem = Deno.env.get('GEMINI_API_KEY');
  const ant = Deno.env.get('ANTHROPIC_API_KEY');
  const errs: string[] = [];
  if (gem) {
    for (const m of ['gemini-flash-latest', 'gemini-3.8-flash', 'gemini-flash-lite-latest']) {
      try {
        const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`, {
          method: 'POST',
          signal: AbortSignal.timeout(45000),
          headers: { 'Content-Type': 'application/json', 'x-goog-api-key': gem },
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: system }] },
            contents: [{ role: 'user', parts: [{ text: prompt }] }],
            generationConfig: {
              maxOutputTokens: 3500,
              temperature: 0.5,
              ...(asJson ? { responseMimeType: 'application/json' } : {}),
            },
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
  if (ant) {
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

const BASE =
  "Tu es Lumi, professeur pour les élèves et étudiants du Bénin et d'Afrique francophone (programmes béninois : BEPC, Baccalauréat, université). " +
  "Sois rigoureux, clair, adapté au niveau. N'invente rien. Écris les maths en texte lisible avec des symboles Unicode (x², √x, ≤, π, a/b) et JAMAIS de LaTeX ni de $.";

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
  const { data: { user } } = await db.auth.getUser(jwt);
  if (!user) return json(401, { error: 'non connecté' });
  try {
    const b = await req.json();
    const kind = String(b.kind ?? '');
    const clean = (v: unknown) => String(v ?? '').replace(/[\r\n]+/g, ' ').trim().slice(0, 80);

    // 1) Contenu déjà en cache : on le renvoie sans appeler l'IA.
    if (kind === 'topics') {
      const level = clean(b.level), subject = clean(b.subject);
      if (!level || !subject) return json(400, { error: 'niveau ou matière manquant' });
      const { data: have } = await db.from('edu_topics').select('id,title,position,status')
        .eq('level', level).eq('subject', subject).order('position');
      if ((have ?? []).length) return json(200, { topics: have });
    } else if (kind === 'lesson' || kind === 'quiz') {
      const t = kind === 'lesson' ? 'edu_lessons' : 'edu_quizzes';
      const { data: have } = await db.from(t).select('*').eq('topic_id', b.topic_id).maybeSingle();
      if (have) return json(200, kind === 'lesson' ? { content: have.content, status: have.status } : { questions: have.questions, status: have.status });
    } else return json(400, { error: 'type inconnu' });

    // 2) Limite de générations par élève.
    const dayAgo = new Date(Date.now() - 24 * 3600_000).toISOString();
    const { count } = await db.from('edu_gen_log').select('id', { count: 'exact', head: true })
      .eq('user_id', user.id).gt('created_at', dayAgo);
    if ((count ?? 0) >= 25) return json(429, { error: "Limite de nouveaux contenus atteinte pour aujourd'hui. Reviens demain !" });
    await db.from('edu_gen_log').insert({ user_id: user.id });

    if (kind === 'topics') {
      const level = clean(b.level), subject = clean(b.subject);
      const out = parse(await generate(BASE,
        `Donne la liste ordonnée de 10 à 12 chapitres du programme de « ${subject} » pour le niveau « ${level} » (Bénin). ` +
        `Réponds en JSON : {"topics":["titre court du chapitre", ...]}`, true));
      const titles: string[] = (out.topics ?? []).map((x: unknown) => clean(x)).filter((x: string) => x).slice(0, 14);
      if (titles.length < 3) throw new Error('liste de chapitres invalide');
      await db.from('edu_topics').upsert(
        titles.map((title, i) => ({ level, subject, title, position: i })),
        { onConflict: 'level,subject,title', ignoreDuplicates: true });
      const { data } = await db.from('edu_topics').select('id,title,position,status')
        .eq('level', level).eq('subject', subject).order('position');
      return json(200, { topics: data ?? [] });
    }

    const { data: topic } = await db.from('edu_topics').select('*').eq('id', b.topic_id).maybeSingle();
    if (!topic) return json(404, { error: 'chapitre introuvable' });
    const ctx = `Matière : ${topic.subject}. Niveau : ${topic.level}. Chapitre : « ${topic.title} ».`;

    if (kind === 'lesson') {
      const content = (await generate(BASE,
        `${ctx} Rédige la leçon complète en français, avec ces parties dans cet ordre, chaque titre sur sa ligne et écrit en MAJUSCULES suivi de deux-points : ` +
        `OBJECTIFS, COURS (définitions, propriétés, méthode), EXEMPLE RÉSOLU (pas à pas), À RETENIR (liste courte), ERREURS FRÉQUENTES. ` +
        `Texte clair, sans # ni tableau ; **gras** pour les mots importants.`, false)).slice(0, 9000);
      await db.from('edu_lessons').upsert({ topic_id: topic.id, content });
      return json(200, { content, status: 'ia' });
    }
    const out = parse(await generate(BASE,
      `${ctx} Crée un quiz de 8 questions à choix multiples (4 propositions, une seule bonne), de difficulté progressive. ` +
      `Réponds en JSON : {"questions":[{"q":"...","options":["...","...","...","..."],"answer":0,"explain":"explication courte"}]} ` +
      `où answer est l'indice (0 à 3) de la bonne proposition. Vérifie bien chaque réponse.`, true));
    const qs = (out.questions ?? []).filter((x: any) =>
      x && typeof x.q === 'string' && Array.isArray(x.options) && x.options.length === 4 &&
      Number.isInteger(x.answer) && x.answer >= 0 && x.answer <= 3
    ).slice(0, 10);
    if (qs.length < 4) throw new Error('quiz invalide');
    await db.from('edu_quizzes').upsert({ topic_id: topic.id, questions: qs });
    return json(200, { questions: qs, status: 'ia' });
  } catch (e) {
    console.log('nova-generate error', String(e));
    try {
      await db.from('app_config').upsert({ key: 'ai_last_error', value: `${new Date().toISOString()} nova ${String(e).slice(0, 300)}` });
    } catch (_) { /* ignore */ }
    return json(500, { error: "Le contenu n'a pas pu être préparé. Réessaie dans un instant." });
  }
});
