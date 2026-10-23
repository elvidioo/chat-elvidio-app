import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications.dart';
import '../presence.dart';
import '../repo.dart';
import '../settings.dart';
import '../updater.dart';
import 'chats_tab.dart';
import 'nearby_screen.dart';
import 'profile_screen.dart';

/// Écran principal : 3 onglets comme Messenger.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  int index = 0;
  int version = 0; // change quand le profil est modifié, pour tout recharger

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Repo.I.start();
    Presence.I.start();
    if (AppSettings.I.notifications.value) Notifier.requestPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureProfile();
      if (mounted) checkAndPrompt(context, silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Repo.I.start();
      Presence.I.start();
    }
  }

  // Un nouveau compte doit choisir un pseudo pour apparaître chez les autres.
  Future<void> ensureProfile() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final me = await supabase
          .from('profiles')
          .select('id')
          .eq('id', uid)
          .maybeSingle();
      if (me == null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ProfileScreen(firstTime: true),
          ),
        );
        if (mounted) setState(() => version++);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          ChatsTab(
            key: ValueKey('chats$version'),
            onOpenProfile: () => setState(() => index = 2),
          ),
          const NearbyScreen(),
          ProfileScreen(
            key: ValueKey('profile$version'),
            showLogout: true,
            onSaved: () => setState(() => version++),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Discussions',
          ),
          NavigationDestination(
            icon: Icon(Icons.wifi_tethering),
            label: 'Mode proche',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
