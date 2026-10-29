/// Rend le texte de l'IA lisible : formules LaTeX → symboles ordinaires,
/// Markdown simple nettoyé. (Le gras **comme ça** est géré à l'affichage.)

const _sup = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷',
  '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
  'n': 'ⁿ', 'i': 'ⁱ', 'x': 'ˣ', 'k': 'ᵏ', 'm': 'ᵐ', 'p': 'ᵖ', 't': 'ᵗ', 'a': 'ᵃ', 'b': 'ᵇ',
};
const _sub = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇',
  '8': '₈', '9': '₉', '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  'n': 'ₙ', 'i': 'ᵢ', 'x': 'ₓ', 'k': 'ₖ', 'm': 'ₘ', 'p': 'ₚ', 't': 'ₜ', 'a': 'ₐ',
};

const _symbols = {
  r'\times': '×', r'\cdot': '·', r'\leq': '≤', r'\le': '≤', r'\geq': '≥', r'\ge': '≥',
  r'\neq': '≠', r'\ne': '≠', r'\approx': '≈', r'\infty': '∞', r'\pm': '±', r'\mp': '∓',
  r'\to': '→', r'\rightarrow': '→', r'\longrightarrow': '⟶', r'\leftarrow': '←',
  r'\Rightarrow': '⇒', r'\implies': '⇒', r'\Leftrightarrow': '⇔', r'\iff': '⇔',
  r'\in': '∈', r'\notin': '∉', r'\subset': '⊂', r'\subseteq': '⊆', r'\cup': '∪', r'\cap': '∩',
  r'\emptyset': '∅', r'\forall': '∀', r'\exists': '∃', r'\sum': 'Σ', r'\prod': 'Π',
  r'\int': '∫', r'\partial': '∂', r'\nabla': '∇', r'\ldots': '…', r'\dots': '…', r'\cdots': '⋯',
  r'\circ': '∘', r'\perp': '⊥', r'\parallel': '∥', r'\angle': '∠', r'\degree': '°',
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ', r'\epsilon': 'ε',
  r'\varepsilon': 'ε', r'\theta': 'θ', r'\lambda': 'λ', r'\mu': 'μ', r'\pi': 'π', r'\rho': 'ρ',
  r'\sigma': 'σ', r'\tau': 'τ', r'\phi': 'φ', r'\varphi': 'φ', r'\omega': 'ω',
  r'\Delta': 'Δ', r'\Sigma': 'Σ', r'\Omega': 'Ω', r'\Pi': 'Π', r'\Phi': 'Φ',
  r'\ln': 'ln', r'\log': 'log', r'\exp': 'exp', r'\sin': 'sin', r'\cos': 'cos', r'\tan': 'tan',
  r'\lim': 'lim', r'\max': 'max', r'\min': 'min', r'\det': 'det',
};

const _blackboard = {'R': 'ℝ', 'N': 'ℕ', 'Z': 'ℤ', 'Q': 'ℚ', 'C': 'ℂ'};

/// Contenu entre accolades à partir de [start] (qui pointe sur '{'). Retourne (contenu, index après '}').
(String, int)? _braced(String s, int start) {
  if (start >= s.length || s[start] != '{') return null;
  var depth = 0;
  for (var i = start; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}') {
      depth--;
      if (depth == 0) return (s.substring(start + 1, i), i + 1);
    }
  }
  return null;
}

String _wrap(String x) {
  final t = x.trim();
  return RegExp(r'^[\w.,]+$').hasMatch(t) ? t : '($t)';
}

String _script(String content, Map<String, String> table, String marker) {
  final c = content.trim();
  final ok = c.isNotEmpty && c.split('').every((ch) => table.containsKey(ch));
  if (ok) return c.split('').map((ch) => table[ch]!).join();
  return c.length == 1 ? '$marker$c' : '$marker($c)';
}

String humanizeMath(String input) {
  var s = input;
  // Délimiteurs
  s = s.replaceAll(r'\[', '').replaceAll(r'\]', '').replaceAll(r'\(', '').replaceAll(r'\)', '');
  s = s.replaceAll(r'$$', '').replaceAll(r'\$', '\u0001');
  s = s.replaceAll(r'$', '').replaceAll('\u0001', r'$');
  s = s.replaceAll(r'\left', '').replaceAll(r'\right', '').replaceAll(r'\displaystyle', '');
  s = s.replaceAll(RegExp(r'\\[,;:! ]'), ' ').replaceAll(r'\quad', ' ').replaceAll(r'\qquad', ' ');
  s = s.replaceAll(r'\\', '\n');

  // Commandes à arguments (de l'intérieur vers l'extérieur, plusieurs passes)
  for (var pass = 0; pass < 8; pass++) {
    final before = s;
    s = s.replaceAllMapped(RegExp(r'\\(?:d?frac)\s*(?=\{)'), (m) => '\u0002FRAC');
    s = _replaceFrac(s);
    s = s.replaceAllMapped(RegExp(r'\\sqrt\s*(\[[^\]]*\])?\s*\{'), (m) => '\u0003SQRT{');
    s = _replaceSqrt(s);
    s = s.replaceAllMapped(RegExp(r'\\(?:text|mathrm|mathbf|textbf|operatorname|mathit|boldsymbol)\s*\{([^{}]*)\}'),
        (m) => m[1]!);
    s = s.replaceAllMapped(RegExp(r'\\mathbb\s*\{([A-Z])\}'), (m) => _blackboard[m[1]!] ?? m[1]!);
    s = s.replaceAllMapped(RegExp(r'\\(?:overline|bar)\s*\{([^{}]*)\}'), (m) => '${m[1]}\u0305');
    s = s.replaceAllMapped(RegExp(r'\\(?:vec|overrightarrow)\s*\{([^{}]*)\}'), (m) => '${m[1]}⃗');
    if (s == before) break;
  }

  // Exposants et indices
  s = _scripts(s, '^', _sup);
  s = _scripts(s, '_', _sub);

  // Symboles (les plus longs d'abord)
  final keys = _symbols.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    s = s.replaceAllMapped(RegExp('${RegExp.escape(k)}(?![A-Za-z])'), (_) => _symbols[k]!);
  }
  // Ce qui reste : \commande inconnue → nom seul ; accolades orphelines retirées
  s = s.replaceAllMapped(RegExp(r'\\([A-Za-z]+)'), (m) => m[1]!);
  s = s.replaceAll('{', '').replaceAll('}', '');
  return s;
}

String _replaceFrac(String s) {
  while (true) {
    final i = s.indexOf('\u0002FRAC');
    if (i < 0) return s;
    final a = _braced(s, i + 5);
    final b = a == null ? null : _braced(s, a.$2);
    if (a == null || b == null) return s.replaceFirst('\u0002FRAC', 'frac');
    s = '${s.substring(0, i)}${_wrap(a.$1)}/${_wrap(b.$1)}${s.substring(b.$2)}';
  }
}

String _replaceSqrt(String s) {
  while (true) {
    final i = s.indexOf('\u0003SQRT');
    if (i < 0) return s;
    final a = _braced(s, i + 5);
    if (a == null) return s.replaceFirst('\u0003SQRT', '√');
    final inner = a.$1.trim();
    s = '${s.substring(0, i)}√${_wrap(inner)}${s.substring(a.$2)}';
  }
}

String _scripts(String s, String marker, Map<String, String> table) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s[i] == marker) {
      if (i + 1 < s.length && s[i + 1] == '{') {
        final b = _braced(s, i + 1);
        if (b != null) {
          out.write(_script(b.$1, table, marker));
          i = b.$2;
          continue;
        }
      } else if (i + 1 < s.length && RegExp(r'[0-9a-zA-Z+\-]').hasMatch(s[i + 1]) && marker == '^') {
        out.write(_script(s[i + 1], table, marker));
        i += 2;
        continue;
      } else if (i + 1 < s.length && RegExp(r'[0-9a-zA-Z]').hasMatch(s[i + 1]) && marker == '_') {
        // indice sans accolades : un seul caractère (u_n → uₙ)
        out.write(_script(s[i + 1], table, marker));
        i += 2;
        continue;
      }
    }
    out.write(s[i]);
    i++;
  }
  return out.toString();
}

/// Nettoyage complet du texte de l'IA avant affichage.
String cleanAiText(String input) {
  var s = humanizeMath(input);
  s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'^(\s*)[*\-]\s+', multiLine: true), (m) => '${m[1]}• ');
  s = s.replaceAll('`', '');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
