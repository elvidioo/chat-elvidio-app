import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../media.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';

/// Recherche dans les vraies données : amis, groupes et messages déjà chargés.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final controller = TextEditingController();
  final uid = Supabase.instance.client.auth.currentUser!.id;
  Timer? _debounce;
  List<Map<String, dynamic>> friends = [];
  bool loading = true;
  String? error;
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await Repo.I.loadProfiles();
      if (mounted) setState(() => friends = list);
    } catch (_) {
      if (mounted) setState(() => error = 'Impossible de charger les contacts.');
    }
    if (mounted) setState(() => loading = false);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = v.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.goldText,
                fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final contacts = query.isEmpty
        ? <Map<String, dynamic>>[]
        : friends
            .where((p) =>
                (p['pseudo']?.toString() ?? '').toLowerCase().contains(query))
            .toList();
    final groups = query.isEmpty
        ? <Map<String, dynamic>>[]
        : Repo.I.groups.value
            .where((g) =>
                (g['name']?.toString() ?? '').toLowerCase().contains(query))
            .toList();
    final messages = query.length < 2
        ? <Map<String, dynamic>>[]
        : Repo.I.messages.value
            .where((m) =>
                (m['content']?.toString() ?? '').toLowerCase().contains(query))
            .take(30)
            .toList();
    final empty =
        contacts.isEmpty && groups.isEmpty && messages.isEmpty && query.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Rechercher un contact, un groupe, un message…',
            prefixIcon: Icon(Icons.search, color: AppColors.muted),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      setState(() => query = '');
                    },
                  ),
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(onPressed: _load, child: const Text('Réessayer')),
                    ],
                  ),
                )
              : query.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Tape un nom ou un mot pour chercher dans tes contacts, tes groupes et les messages de cet appareil.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    )
                  : empty
                      ? Center(
                          child: Text('Aucun résultat pour « $query »',
                              style: TextStyle(color: AppColors.muted)))
                      : ListView(
                          children: [
                            if (contacts.isNotEmpty) _section('CONTACTS'),
                            for (final p in contacts)
                              ListTile(
                                leading: Avatar(
                                    name: p['pseudo'].toString(),
                                    size: 44,
                                    userId: p['id'].toString(),
                                    showOnline: true),
                                title: Text(p['pseudo'].toString()),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                        receiverId: p['id'].toString(),
                                        receiverName: p['pseudo'].toString()),
                                  ),
                                ),
                              ),
                            if (groups.isNotEmpty) _section('GROUPES'),
                            for (final g in groups)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary,
                                  child: const Icon(Icons.groups,
                                      color: Colors.white),
                                ),
                                title: Text(g['name'].toString()),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => GroupChatScreen(group: g)),
                                ),
                              ),
                            if (messages.isNotEmpty) _section('MESSAGES'),
                            for (final m in messages)
                              _messageTile(m),
                          ],
                        ),
    );
  }

  Widget _messageTile(Map<String, dynamic> m) {
    final peer = (m['sender'] == uid ? m['receiver'] : m['sender']).toString();
    final name = Repo.I.names[peer] ?? 'Contact';
    final text = m['content']?.toString() ?? '';
    return ListTile(
      leading: Avatar(name: name, size: 40, userId: peer),
      title: Text(name),
      subtitle: Text(text.isEmpty ? mediaLabel(m['media_url'].toString()) : text,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(receiverId: peer, receiverName: name)),
      ),
    );
  }
}
