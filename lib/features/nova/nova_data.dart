import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme.dart';

/// Données et outils partagés de l'application Lumi (éducation).
final novaDb = Supabase.instance.client;

const novaLevels = [
  '6ème', '5ème', '4ème', '3ème', '2nde', '1ère', 'Terminale', 'Université',
];

List<String> novaSubjectsFor(String level) {
  if (level == 'Université') {
    return ['Mathématiques', 'Informatique', 'Physique', 'Économie', 'Droit', 'Anglais'];
  }
  final lycee = ['2nde', '1ère', 'Terminale'].contains(level);
  return [
    'Mathématiques', 'Français', 'Anglais', 'Physique-Chimie', 'SVT',
    'Histoire-Géographie',
    if (lycee) ...['Philosophie', 'Économie'],
  ];
}

IconData novaIcon(String subject) {
  final s = subject.toLowerCase();
  if (s.startsWith('math')) return Icons.calculate_rounded;
  if (s.startsWith('fran')) return Icons.menu_book_rounded;
  if (s.startsWith('angl')) return Icons.translate_rounded;
  if (s.startsWith('phys')) return Icons.science_rounded;
  if (s.startsWith('svt')) return Icons.biotech_rounded;
  if (s.startsWith('hist')) return Icons.public_rounded;
  if (s.startsWith('philo')) return Icons.psychology_rounded;
  if (s.startsWith('éco') || s.startsWith('eco')) return Icons.trending_up_rounded;
  if (s.startsWith('info')) return Icons.code_rounded;
  if (s.startsWith('droit')) return Icons.gavel_rounded;
  return Icons.school_rounded;
}

const _subjectColors = [
  Color(0xFF2D7BFF), Color(0xFF22D3EE), Color(0xFF7C4DFF), Color(0xFF14B8A6),
  Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF6366F1), Color(0xFF10B981),
];
Color novaColor(String subject) =>
    _subjectColors[subject.codeUnits.fold<int>(0, (a, b) => a + b) % _subjectColors.length];

const novaGradient = LinearGradient(
  colors: [Color(0xFF2D7BFF), Color(0xFF7C4DFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Appelle la fonction serveur qui prépare (et met en cache) les contenus.
Future<Map<String, dynamic>> novaCall(Map<String, dynamic> body,
    {String fn = 'nova-generate'}) async {
  try {
    final r = await novaDb.functions
        .invoke(fn, body: body)
        .timeout(const Duration(seconds: 70));
    final d = r.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    throw 'Réponse inattendue';
  } on FunctionException catch (e) {
    final d = e.details;
    if (d is Map && d['error'] != null) throw d['error'].toString();
    throw 'Le contenu n\'a pas pu être préparé. Réessaie.';
  } catch (e) {
    if (e is String) rethrow;
    throw 'Connexion impossible. Vérifie ton Internet et réessaie.';
  }
}

/// Texte avec **gras** pour les leçons.
List<InlineSpan> novaSpans(String t, TextStyle base) {
  final out = <InlineSpan>[];
  final parts = t.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    out.add(TextSpan(
      text: parts[i],
      style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w800) : base,
    ));
  }
  return out;
}

/// Page poussée avec le thème bleu nuit de Lumi.
Route<T> novaRoute<T>(Widget page) => MaterialPageRoute<T>(
      builder: (_) => Theme(data: buildTheme(true, nova: true), child: page),
    );
