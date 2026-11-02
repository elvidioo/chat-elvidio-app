import 'package:flutter/material.dart';

import '../../screens/ai_chat_screen.dart';
import '../../theme.dart';
import 'nova_data.dart';
import 'nova_learn.dart';
import 'nova_notebook.dart';
import 'nova_tabs.dart';

/// Lumi : application éducative intégrée à Veyra.
class NovaShell extends StatefulWidget {
  const NovaShell({super.key});
  @override
  State<NovaShell> createState() => _NovaShellState();
}

class _NovaShellState extends State<NovaShell> {
  int _i = 0;
  bool _loading = true;
  bool _editing = false;
  Map<String, dynamic>? _student;
  final _visited = <int>{0};
  int _homeKey = 0;

  @override
  void initState() {
    super.initState();
    AppColors.nova = true;
    _load();
  }

  @override
  void dispose() {
    AppColors.nova = false;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await novaDb
          .from('ai_student')
          .select()
          .eq('user_id', novaDb.auth.currentUser!.id)
          .maybeSingle();
      if (mounted) _student = s;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool get _ready =>
      _student != null &&
      (_student!['level']?.toString() ?? '').isNotEmpty &&
      ((_student!['subjects'] as List?) ?? const []).isNotEmpty;

  Future<void> _openSubject(String s) async {
    await Navigator.push(
        context, novaRoute(SubjectScreen(level: _student!['level'].toString(), subject: s)));
    if (mounted) setState(() => _homeKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildTheme(true, nova: true),
      child: Builder(builder: (context) {
        if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (!_ready || _editing) {
          return NovaOnboarding(
            initial: _student,
            canSkip: _ready,
            onDone: (row) => setState(() {
              _student = {...?_student, ...row};
              _editing = false;
            }),
          );
        }
        final s = _student!;
        final pages = <Widget>[
          NovaHome(key: ValueKey(_homeKey), student: s, onOpenSubject: _openSubject, onGoCourses: () => setState(() { _i = 1; _visited.add(1); })),
          if (_visited.contains(1)) const NotebookScreen(embedded: true) else const SizedBox(),
          if (_visited.contains(2)) const AiChatScreen() else const SizedBox(),
          if (_visited.contains(3)) const NovaCommunity() else const SizedBox(),
          if (_visited.contains(4)) NovaProfile(student: s, onEdit: () => setState(() => _editing = true)) else const SizedBox(),
        ];
        return Scaffold(
          body: SafeArea(bottom: false, child: IndexedStack(index: _i, children: pages)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _i,
            onDestinationSelected: (v) => setState(() {
              _i = v;
              _visited.add(v);
            }),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
              NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Mes cours'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Tuteur IA'),
              NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Communauté'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'Profil'),
            ],
          ),
        );
      }),
    );
  }
}
