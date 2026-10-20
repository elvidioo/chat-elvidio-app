import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';
import 'home_screen.dart';
import 'nearby_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool signup = false;
  bool hidePassword = true;
  String message = '';

  String friendly(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail ou mot de passe incorrect.';
    if (m.contains('already')) return 'Cet e-mail est déjà utilisé.';
    if (m.contains('password')) {
      return 'Mot de passe trop court (6 caractères minimum).';
    }
    if (m.contains('email')) return 'Adresse e-mail invalide.';
    return raw;
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      message = '';
    });

    try {
      final auth = Supabase.instance.client.auth;
      final mail = email.text.trim();

      if (signup) {
        await auth.signUp(email: mail, password: password.text);
        // Le compte est confirmé automatiquement : on connecte tout de suite.
        if (auth.currentSession == null) {
          await auth.signInWithPassword(email: mail, password: password.text);
        }
      } else {
        await auth.signInWithPassword(email: mail, password: password.text);
      }

      if (!mounted) return;
      if (auth.currentUser != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() => message = 'Connexion impossible. Réessaie.');
      }
    } on AuthException catch (e) {
      setState(() => message = friendly(e.message));
    } catch (_) {
      setState(() => message =
          'Pas de connexion internet. Essaie le Mode proche ci-dessous.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const AppLogo(),
                  const SizedBox(height: 16),
                  const Text(
                    'Chat Elvidio',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Discute. Partage. Même sans internet.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Connexion')),
                        ButtonSegment(value: true, label: Text('Inscription')),
                      ],
                      selected: {signup},
                      onSelectionChanged: (s) => setState(() {
                        signup = s.first;
                        message = '';
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Adresse e-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: hidePassword,
                    decoration: InputDecoration(
                      hintText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(hidePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => hidePassword = !hidePassword),
                      ),
                    ),
                    onSubmitted: (_) => loading ? null : submit(),
                  ),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  const SizedBox(height: 20),
                  GradientButton(
                    label: signup ? 'Créer mon compte' : 'Se connecter',
                    loading: loading,
                    onPressed: submit,
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NearbyScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.surface2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_tethering, color: AppColors.cyan),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pas d\'internet ?',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Ouvre le Mode proche, sans compte.',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
