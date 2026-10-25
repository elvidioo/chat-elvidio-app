// Supprime le compte de l'appelant : fichiers, appartenance des groupes et compte.
// Les données liées (profil, messages, amis...) partent en cascade avec le compte.
import { createClient } from 'npm:@supabase/supabase-js@2';

const headers = { 'Content-Type': 'application/json' };
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (req) => {
  const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return reply(401, { error: 'non connecté' });
  const uid = user.id;
  try {
    // Groupes créés par ce compte : le plus ancien membre restant en devient administrateur.
    const { data: groups } = await admin.from('groups').select('id').eq('created_by', uid);
    for (const g of groups ?? []) {
      const { data: heirs } = await admin.from('group_members').select('user_id')
        .eq('group_id', g.id).neq('user_id', uid).order('joined_at').limit(1);
      const heir = heirs?.[0]?.user_id;
      if (heir) {
        await admin.from('group_members').update({ role: 'admin' }).eq('group_id', g.id).eq('user_id', heir);
        await admin.from('groups').update({ created_by: heir }).eq('id', g.id);
      }
    }
    // Fichiers du compte.
    for (let page = 0; page < 20; page++) {
      const { data: files } = await admin.storage.from('media').list(uid, { limit: 100 });
      if (!files || files.length === 0) break;
      await admin.storage.from('media').remove(files.map((f) => `${uid}/${f.name}`));
      if (files.length < 100) break;
    }
    const { error: delErr } = await admin.auth.admin.deleteUser(uid);
    if (delErr) throw delErr;
    return reply(200, { ok: true });
  } catch (e) {
    console.log('delete-account error', String(e));
    return reply(500, { error: 'suppression impossible' });
  }
});
