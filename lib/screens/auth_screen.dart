import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'nearby_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final pseudo = TextEditingController();
  final identifier = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool signup = false;
  bool hidePassword = true;
  String message = '';
  bool googleBusy = false;
  bool _navigated = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Retour de la connexion Google (le navigateur rouvre l'app avec la session).
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn && s.session != null) _goHome();
    });
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      googleBusy = true;
      message = '';
    });
    try {
      final ok = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'chatelvidio://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        setState(() => message = 'Impossible d\'ouvrir la connexion Google.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => message = friendly(e.message));
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Connexion Google impossible (internet ? configuration ?).');
      }
    } finally {
      if (mounted) setState(() => googleBusy = false);
    }
  }

  // E-mail tel quel, ou numéro de téléphone -> adresse interne (sans SMS).
  String? loginEmail(String raw) {
    final id = raw.trim().toLowerCase();
    if (id.contains('@')) {
      return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(id) ? id : null;
    }
    var digits = id.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length < 8 || digits.length > 15) return null;
    return '$digits@phone.chatelvidio.app';
  }

  String friendly(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('invalid login')) {
      return 'Identifiant ou mot de passe incorrect.';
    }
    if (m.contains('already')) return 'Ce compte existe déjà.';
    if (m.contains('password')) {
      return 'Mot de passe trop court (6 caractères minimum).';
    }
    return raw;
  }

  String? codeMessage(String? code) {
    switch (code) {
      case 'pseudo_taken':
        return 'Ce pseudo est déjà pris.';
      case 'already_registered':
        return 'Ce numéro ou cet e-mail a déjà un compte.';
      case 'weak_password':
        return 'Mot de passe trop court (6 caractères minimum).';
      case 'invalid_identifier':
        return 'E-mail ou numéro invalide.';
      case 'invalid_pseudo':
        return 'Pseudo invalide (3 à 30 caractères : lettres, chiffres, . _ -).';
    }
    return null;
  }

  // Création du compte : la fonction "register" confirme le compte tout de
  // suite (aucun e-mail envoyé) et enregistre le pseudo.
  Future<void> register(String mail, String chosenPseudo) async {
    final client = Supabase.instance.client;
    try {
      await client.functions.invoke('register', body: {
        'identifier': identifier.text.trim(),
        'password': password.text,
        'pseudo': chosenPseudo,
      });
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error']?.toString() : null;
      final known = codeMessage(code);
      if (known != null) throw _FormError(known);
      if (e.status == 404 || e.status >= 500) {
        // Secours : inscription classique si la fonction est indisponible.
        await client.auth.signUp(email: mail, password: password.text);
        if (client.auth.currentSession == null) {
          await client.auth
              .signInWithPassword(email: mail, password: password.text);
        }
        try {
          await client.from('profiles').upsert({
            'id': client.auth.currentUser!.id,
            'pseudo': chosenPseudo,
          });
        } on PostgrestException catch (pe) {
          if (pe.code == '23505') throw _FormError('Ce pseudo est déjà pris.');
        }
        return;
      }
      throw _FormError('Inscription impossible. Réessaie.');
    }
  }

  Future<void> submit() async {
    final mail = loginEmail(identifier.text);
    if (mail == null || (signup && !identifier.text.contains('@'))) {
      setState(() => message = 'Entre une adresse e-mail valide.');
      return;
    }
    final chosenPseudo = pseudo.text.trim();
    if (signup &&
        !RegExp(r'^[\p{L}\p{N}_.\- ]{3,30}$', unicode: true)
            .hasMatch(chosenPseudo)) {
      setState(() => message =
          'Choisis un pseudo de 3 à 30 caractères (lettres, chiffres, . _ -).');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (signup) await register(mail, chosenPseudo);
      if (auth.currentSession == null) {
        await auth.signInWithPassword(email: mail, password: password.text);
      }

      if (!mounted) return;
      if (auth.currentUser != null) {
        _goHome();
      } else {
        setState(() => message = 'Connexion impossible. Réessaie.');
      }
    } on _FormError catch (e) {
      setState(() => message = e.text);
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
    _authSub?.cancel();
    pseudo.dispose();
    identifier.dispose();
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
                    'Veyra',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
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
                  if (signup) ...[
                    TextField(
                      controller: pseudo,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        hintText: 'Pseudo',
                        counterText: '',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: identifier,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'E-mail',
                      prefixIcon: const Icon(Icons.alternate_email),
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
                  if (!signup)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ForgotPasswordScreen(
                              initialEmail: identifier.text.trim(),
                            ),
                          ),
                        ),
                        child: const Text('Mot de passe oublié ?'),
                      ),
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
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Divider(color: AppColors.surface2)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ou', style: TextStyle(color: AppColors.muted)),
                    ),
                    Expanded(child: Divider(color: AppColors.surface2)),
                  ]),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: (googleBusy || loading) ? null : signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                    ),
                    icon: googleBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.g_mobiledata, size: 32),
                    label: const Text('Continuer avec Google'),
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
                      child: Row(
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

class _FormError implements Exception {
  _FormError(this.text);
  final String text;
}
