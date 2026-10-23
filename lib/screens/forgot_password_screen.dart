import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';
import 'home_screen.dart';

/// Mot de passe oublié : un code est envoyé par e-mail, puis nouveau mot de passe.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String _message = '';

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final mail = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) {
      setState(() => _message = 'Entre une adresse e-mail valide.');
      return;
    }
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(mail);
      setState(() {
        _codeSent = true;
        _message = 'Un code a été envoyé à $mail (regarde aussi les spams).';
      });
    } on AuthException catch (e) {
      setState(() => _message = e.message);
    } catch (_) {
      setState(() => _message = 'Pas de connexion internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().length < 6 || _password.text.length < 6) {
      setState(() => _message =
          'Entre le code reçu et un mot de passe de 6 caractères minimum.');
      return;
    }
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final auth = Supabase.instance.client.auth;
      await auth.verifyOTP(
        email: _email.text.trim().toLowerCase(),
        token: _code.text.trim(),
        type: OtpType.recovery,
      );
      await auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      setState(() => _message = e.message.toLowerCase().contains('expired') ||
              e.message.toLowerCase().contains('invalid')
          ? 'Code incorrect ou expiré.'
          : e.message);
    } catch (_) {
      setState(() => _message = 'Pas de connexion internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _codeSent
                  ? 'Entre le code reçu par e-mail et choisis un nouveau mot de passe.'
                  : 'Entre l\'e-mail de ton compte. Nous t\'envoyons un code pour choisir un nouveau mot de passe.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'E-mail',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Code reçu',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Nouveau mot de passe',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent)),
              ),
            const SizedBox(height: 20),
            GradientButton(
              label: _codeSent ? 'Changer le mot de passe' : 'Envoyer le code',
              loading: _loading,
              onPressed: _codeSent ? _reset : _sendCode,
            ),
            if (_codeSent)
              TextButton(
                onPressed: _loading ? null : _sendCode,
                child: const Text('Renvoyer le code'),
              ),
          ],
        ),
      ),
    );
  }
}
