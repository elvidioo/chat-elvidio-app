import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../call_service.dart';
import '../notifications.dart';
import '../presence.dart';
import '../push.dart';
import '../repo.dart';
import '../settings.dart';
import '../updater.dart';
import 'app_nav_bar.dart';
import 'chats_tab.dart';
import 'new_chat_sheet.dart';
import 'feed_tab.dart';
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
    LivePresence.I.start();
    Push.init();
    CallService.I.start();
    Repo.I.touchLastSeen();
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
    if (state == AppLifecycleState.paused) Repo.I.touchLastSeen();
    if (state == AppLifecycleState.resumed) {
      CallService.I.start();
      Repo.I.touchLastSeen();
      Repo.I.start();
      LivePresence.I.start();
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
    final uid = supabase.auth.currentUser?.id;
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          ChatsTab(
            key: ValueKey('chats$version'),
            onOpenProfile: () => setState(() => index = 3),
            onOpenNearby: () => setState(() => index = 1),
            onOpenStories: () => setState(() => index = 2),
          ),
          const NearbyScreen(),
          const FeedTab(),
          ProfileScreen(
            key: ValueKey('profile$version'),
            showLogout: true,
            onSaved: () => setState(() => version++),
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: Repo.I.messages,
        builder: (context, _) => AppNavBar(
        index: index,
        onSelect: (i) => setState(() => index = i),
        onCenter: () => showNewChatSheet(context),
        badges: {0: Repo.I.messages.value.where((m) => m['receiver'] == uid && m['read_at'] == null).length},
        items: const [
          NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
              'Discussions'),
          NavItem(Icons.sensors_rounded, Icons.sensors_rounded, 'À proximité'),
          NavItem(Icons.auto_stories_outlined, Icons.auto_stories, 'Stories'),
          NavItem(Icons.account_circle_outlined, Icons.account_circle,
              'Profil'),
        ],
      ),
      ),
    );
  }
}
