import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/nearby_screen.dart';
import 'screens/profile_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(const SetupApp());
    return;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  runApp(const ChatElvidioApp());
}

class SetupApp extends StatelessWidget {
  const SetupApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF10111B),
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'CHAT ELVIDIO\n\nConfiguration Supabase requise '
                'pour démarrer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
          ),
        ),
      );
}

class ChatElvidioApp extends StatelessWidget {
  const ChatElvidioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat Elvidio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF10111B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthPage(),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool signup = false;
  String message = '';

  Future<void> submit() async {
    setState(() {
      loading = true;
      message = '';
    });

    try {
      final auth = Supabase.instance.client.auth;

      if (signup) {
        await auth.signUp(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }

      if (!mounted) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else {
        setState(() => message =
            'Vérifie ton e-mail pour confirmer ton inscription.');
      }
    } on AuthException catch (e) {
      setState(() => message = e.message);
    } catch (_) {
      setState(() => message = 'Erreur de connexion. Réessaie.');
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
            child: Column(
              children: [
                const Icon(Icons.forum, size: 72, color: Color(0xFF00E5FF)),
                const SizedBox(height: 12),
                const Text(
                  'CHAT ELVIDIO',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const Text('Connecte-toi. Discute. Partage.'),
                const SizedBox(height: 32),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Adresse e-mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: loading ? null : submit,
                    child: Text(loading
                        ? 'Chargement...'
                        : signup
                            ? 'Créer mon compte'
                            : 'Se connecter'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    signup = !signup;
                    message = '';
                  }),
                  child: Text(signup
                      ? 'Déjà inscrit ? Se connecter'
                      : 'Créer un nouveau compte'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NearbyScreen()),
                  ),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Mode proche (sans internet)'),
                ),
                if (message.isNotEmpty)
                  Text(message, style: const TextStyle(color: Colors.orange)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> loadProfiles() async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('profiles')
        .select('id, pseudo')
        .neq('id', userId)
        .order('pseudo');
    return List<Map<String, dynamic>>.from(data);
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Elvidio'),
        actions: [
          IconButton(
            tooltip: 'Mode proche (sans internet)',
            icon: const Icon(Icons.wifi_tethering),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NearbyScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ).then((_) {
              if (mounted) setState(() {});
            }),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthPage()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: loadProfiles(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Impossible de charger les profils. Vérifie Supabase.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final profiles = snapshot.data!;
          if (profiles.isEmpty) {
            return const Center(
              child: Text('Bienvenue ! Aucun autre profil pour le moment.'),
            );
          }

          return ListView.builder(
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF00E5FF),
                  child: Icon(Icons.person, color: Colors.black),
                ),
                title: Text(profile['pseudo']?.toString() ?? 'Utilisateur'),
                subtitle: const Text('Ouvrir la conversation'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      receiverId: profile['id'].toString(),
                      receiverName:
                          profile['pseudo']?.toString() ?? 'Utilisateur',
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final pseudo = TextEditingController();
            return AlertDialog(
              title: const Text('Choisir un pseudo'),
              content: TextField(
                controller: pseudo,
                decoration: const InputDecoration(hintText: 'Ton pseudo'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () async {
                    final value = pseudo.text.trim();
                    if (value.isEmpty) return;
                    try {
                      await supabase.from('profiles').upsert({
                        'id': user.id,
                        'pseudo': value,
                      });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (mounted) setState(() {});
                    } catch (_) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Pseudo indisponible ou erreur réseau.'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        ),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;

  const ChatPage({
    super.key,
    required this.receiverId,
    required this.receiverName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const maxMediaBytes = 50 * 1024 * 1024;
  static const videoExt = ['mp4', 'mov', '3gp', 'webm', 'mkv'];

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();
  final messageController = TextEditingController();
  late final String uid = supabase.auth.currentUser!.id;
  late final Stream<List<Map<String, dynamic>>> stream = supabase
      .from('messages')
      .stream(primaryKey: ['id']).order('created_at', ascending: false);
  bool sending = false;

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> sendMessage() async {
    final content = messageController.text.trim();
    if (content.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await supabase.from('messages').insert({
        'sender': uid,
        'receiver': widget.receiverId,
        'content': content,
      });
      messageController.clear();
    } catch (_) {
      toast('Envoi impossible. Réessaie.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> sendMedia({required bool video}) async {
    if (sending) return;
    try {
      final file = video
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 2),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1280,
              imageQuality: 70,
            );
      if (file == null) return;
      setState(() => sending = true);

      final bytes = await file.readAsBytes();
      if (bytes.length > maxMediaBytes) {
        toast('Fichier trop lourd (50 Mo maximum).');
        return;
      }

      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await supabase.storage.from('media').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: file.mimeType),
          );
      final url = supabase.storage.from('media').getPublicUrl(path);

      await supabase.from('messages').insert({
        'sender': uid,
        'receiver': widget.receiverId,
        'media_url': url,
      });
    } catch (_) {
      toast('Envoi du fichier impossible. Réessaie.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void pickMedia() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(sheet);
                sendMedia(video: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Vidéo'),
              onTap: () {
                Navigator.pop(sheet);
                sendMedia(video: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool isVideo(String url) {
    final clean = url.split('?').first.toLowerCase();
    return videoExt.any(clean.endsWith);
  }

  Widget mediaBubble(String url) {
    if (isVideo(url)) {
      return InkWell(
        onTap: () => launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication),
        child: const SizedBox(
          width: 200,
          height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill, size: 48),
              SizedBox(height: 6),
              Text('Vidéo · toucher pour lire'),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 220,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 220,
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 220,
            height: 80,
            child: Center(child: Text('Image indisponible')),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.receiverName)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Erreur de chargement.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!
                    .where((m) =>
                        (m['sender'] == uid &&
                            m['receiver'] == widget.receiverId) ||
                        (m['sender'] == widget.receiverId &&
                            m['receiver'] == uid))
                    .toList();
                if (messages.isEmpty) {
                  return const Center(child: Text('Dis bonjour 👋'));
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final item = messages[index];
                    final mine = item['sender'] == uid;
                    final mediaUrl = item['media_url']?.toString();
                    final text = item['content']?.toString() ?? '';
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFF006B78)
                              : const Color(0xFF292B3D),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mediaUrl != null && mediaUrl.isNotEmpty)
                              mediaBubble(mediaUrl),
                            if (text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(text),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (sending) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: sending ? null : pickMedia,
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Écris un message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
