import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'storage.dart';
import 'theme.dart';
import 'widgets.dart';

// Clés publiques (anon) du projet chat-elvidio : elles sont faites pour être
// dans l'app, la sécurité repose sur les règles RLS de la base. Le build peut
// les remplacer avec --dart-define si besoin.
const _envUrl = String.fromEnvironment('SUPABASE_URL');
const _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

const supabaseUrl =
    _envUrl == '' ? 'https://cokalbfyyhlrslautebc.supabase.co' : _envUrl;
const supabaseKey = _envKey == ''
    ? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNva2FsYmZ5eWhscnNsYXV0ZWJjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0MjE1ODgsImV4cCI6MjEwNzk5NzU4OH0.c08oSC4URNT26DN7ukAIiYEjZclCEWXu4lGvdDijFVM'
    : _envKey;

Future<void> main() async {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorWidget.builder = (details) => Material(
          color: AppColors.bg,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Erreur d\'affichage :\n${details.exceptionAsString()}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          ),
        );
    runApp(const BootApp());
  }, (error, stack) {
    debugPrint('Erreur non gérée : $error');
  });
}

/// Affiche tout de suite un écran de chargement, puis démarre Supabase.
/// En cas de problème, l'erreur s'affiche au lieu d'un écran noir.
class BootApp extends StatefulWidget {
  const BootApp({super.key});

  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  late Future<void> boot = _boot();

  Future<void> _boot() {
    return Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        localStorage: FileLocalStorage(),
        pkceAsyncStorage: FileAsyncStorage(),
      ),
    )
        .timeout(const Duration(seconds: 20))
        .then((_) {});
  }

  Widget _screen(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _screen(Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(),
                const SizedBox(height: 20),
                const Text(
                  'Démarrage impossible',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => boot = _boot()),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _screen(const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ));
        }
        return const ChatElvidioApp();
      },
    );
  }
}

class SetupApp extends StatelessWidget {
  const SetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLogo(),
                SizedBox(height: 20),
                Text(
                  'Configuration Supabase requise pour démarrer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatElvidioApp extends StatelessWidget {
  const ChatElvidioApp({super.key});

  @override
  Widget build(BuildContext context) {
    // La session est mémorisée : pas besoin de se reconnecter à chaque fois
    // (et ça marche même sans internet).
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    return MaterialApp(
      title: 'Chat Elvidio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: loggedIn ? const HomeScreen() : const AuthScreen(),
    );
  }
}
