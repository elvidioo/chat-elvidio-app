import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presence.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';

/// Profil d'un contact : photo, pseudo, biographie, statut.
class ContactProfileScreen extends StatefulWidget {
  const ContactProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    this.onMessage,
  });

  final String userId;
  final String name;
  final VoidCallback? onMessage;

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _db
          .from('profiles')
          .select('id, pseudo, avatar_url, bio, last_seen')
          .eq('id', widget.userId)
          .maybeSingle();
      _profile = p;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _block() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Bloquer ${widget.name} ?'),
        content: const Text(
            'Cette personne sera retirée de tes amis et ne pourra plus t\'écrire.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bloquer')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Repo.I.blockUser(widget.userId);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Blocage impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bio = _profile?['bio']?.toString() ?? '';
    final photo = _profile?['avatar_url']?.toString();
    final seen = DateTime.tryParse(_profile?['last_seen']?.toString() ?? '');
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Avatar(
                    name: widget.name,
                    size: 120,
                    userId: widget.userId,
                    photoUrl: photo,
                    showOnline: true,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _profile?['pseudo']?.toString() ?? widget.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: LivePresence.I.online,
                    builder: (context, on, _) {
                      final isOn = on.contains(widget.userId);
                      return Text(
                        isOn ? 'En ligne' : lastSeenText(seen),
                        style: TextStyle(
                            color: isOn ? AppColors.online : AppColors.muted),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                if (bio.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: LinkText(
                      bio,
                      style: TextStyle(
                          fontSize: 15.5, height: 1.35, color: AppColors.text),
                      linkColor: AppColors.primary,
                    ),
                  )
                else
                  Center(
                    child: Text('Pas de biographie.',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                const SizedBox(height: 24),
                if (widget.onMessage != null)
                  FilledButton.icon(
                    onPressed: widget.onMessage,
                    icon: const Icon(Icons.chat_bubble),
                    label: const Text('Envoyer un message'),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _block,
                  icon: const Icon(Icons.block, color: Colors.redAccent),
                  label: const Text('Bloquer',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
    );
  }
}
