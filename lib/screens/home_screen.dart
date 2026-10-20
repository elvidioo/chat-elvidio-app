import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';
import 'nearby_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> future = loadProfiles();

  Future<List<Map<String, dynamic>>> loadProfiles() async {
    final uid = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('profiles')
        .select('id, pseudo')
        .neq('id', uid)
        .order('pseudo');
    return List<Map<String, dynamic>>.from(data);
  }

  void reload() {
    setState(() => future = loadProfiles());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ensureProfile());
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
        await openProfile(firstTime: true);
      }
    } catch (_) {}
  }

  Future<void> openProfile({bool firstTime = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(firstTime: firstTime)),
    );
    if (mounted) reload();
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Widget nearbyBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NearbyScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          children: [
            Icon(Icons.wifi_tethering, size: 34, color: Colors.white),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mode proche',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Discute sans internet avec les téléphones autour de toi',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget message(IconData icon, String title, String subtitle,
      {VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 64, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }

  Widget userTile(Map<String, dynamic> profile) {
    final pseudo = profile['pseudo']?.toString() ?? 'Utilisateur';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Avatar(name: pseudo),
        title: Text(
          pseudo,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        subtitle: const Text(
          'Appuie pour discuter',
          style: TextStyle(color: AppColors.muted),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              receiverId: profile['id'].toString(),
              receiverName: pseudo,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Text('Chat Elvidio'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => openProfile(),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await future;
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            final children = <Widget>[nearbyBanner()];
            if (snapshot.hasError) {
              children.add(message(
                Icons.cloud_off,
                'Pas de connexion',
                'Impossible de charger les contacts.\nTu peux utiliser le Mode proche.',
                onRetry: reload,
              ));
            } else if (!snapshot.hasData) {
              children.add(const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ));
            } else if (snapshot.data!.isEmpty) {
              children.add(message(
                Icons.people_outline,
                'Personne d\'autre pour le moment',
                'Invite tes amis à installer l\'app,\nils apparaîtront ici.',
              ));
            } else {
              children.addAll(snapshot.data!.map(userTile));
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: children,
            );
          },
        ),
      ),
    );
  }
}
