import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(const SetupApp());
    return;
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const ChatElvidioApp());
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
