import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _pseudo = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _pseudo.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return;

      final profile = await _db
          .from('profiles')
          .select('pseudo')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        _pseudo.text = profile?['pseudo']?.toString() ?? '';
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de charger le profil.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final pseudo = _pseudo.text.trim();
    final user = _db.auth.currentUser;

    if (user == null) return;
    if (pseudo.length < 3 || pseudo.length > 30) {
      setState(() => _error = 'Le pseudo doit contenir entre 3 et 30 caractères.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _db.from('profiles').upsert({
        'id': user.id,
        'pseudo': pseudo,
      }, onConflict: 'id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil enregistré !')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _
cd ~/chat-elvidio-app && python - <<'PY'
from pathlib import Path

p = Path("lib/main.dart")
s = p.read_text()

imp = "import 'screens/profile_screen.dart';"
if imp not in s:
    s = s.replace(
        "import 'package:supabase_flutter/supabase_flutter.dart';",
        "import 'package:supabase_flutter/supabase_flutter.dart';\n" + imp,
        1
    )

start = s.find("class HomePage")
if start == -1:
    start = s.find("class HomeScreen")

if start == -1:
    print("Écran d'accueil introuvable : fichier non modifié.")
    raise SystemExit(1)

end = s.find("\nclass ", start + 1)
if end == -1:
    end = len(s)

home = s[start:end]
button = """IconButton(
  tooltip: 'Mon profil',
  icon: const Icon(Icons.account_circle_outlined),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ProfileScreen()),
  ),
),"""

if "const ProfileScreen()" in home:
    print("Le profil est déjà relié à l'accueil.")
elif "actions: [" in home:
    home = home.replace("actions: [", "actions: [\n" + button, 1)
    s = s[:start] + home + s[end:]
    p.write_text(s)
    print("Bouton de profil ajouté à la barre d'actions.")
else:
    print("Barre d'actions introuvable : fichier

cd ~/chat-elvidio-app && flutter analyze




