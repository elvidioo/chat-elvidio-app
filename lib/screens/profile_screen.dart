import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.firstTime = false});

  final bool firstTime;

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
      setState(
          () => _error = 'Le pseudo doit contenir entre 3 et 30 caractères.');
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré !')),
      );
      if (widget.firstTime) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == '23505'
            ? 'Ce pseudo est déjà pris.'
            : 'Enregistrement impossible : ${e.message}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erreur réseau. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstTime ? 'Bienvenue !' : 'Mon profil'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Avatar(name: _pseudo.text, size: 96)),
                  const SizedBox(height: 18),
                  Text(
                    widget.firstTime
                        ? 'Choisis ton pseudo : c\'est le nom que verront tes amis.'
                        : 'Ton pseudo visible par les autres.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _pseudo,
                    maxLength: 30,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Pseudo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  const SizedBox(height: 6),
                  GradientButton(
                    label: 'Enregistrer',
                    loading: _saving,
                    onPressed: _saveProfile,
                  ),
                ],
              ),
            ),
    );
  }
}
