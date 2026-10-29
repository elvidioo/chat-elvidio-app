import 'package:chat_elvidio_app/ai_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractions et racines', () {
    expect(humanizeMath(r'$\frac{a}{b}$'), 'a/b');
    expect(humanizeMath(r'\frac{x+1}{2}'), '(x+1)/2');
    expect(humanizeMath(r'\sqrt{x}'), '√x');
    expect(humanizeMath(r'\sqrt{x+1}'), '√(x+1)');
  });

  test('exposants et indices', () {
    expect(humanizeMath(r'x^2 + y^{3}'), 'x² + y³');
    expect(humanizeMath(r'u_{n+1} = u_n + r'), 'uₙ₊₁ = uₙ + r');
    expect(humanizeMath(r'e^{x}'), 'eˣ');
  });

  test('symboles', () {
    expect(humanizeMath(r'a \leq b \Rightarrow c \neq d'), 'a ≤ b ⇒ c ≠ d');
    expect(humanizeMath(r'x \in \mathbb{R}'), 'x ∈ ℝ');
    expect(humanizeMath(r'\lim_{n \to \infty} u_n'), 'lim_(n → ∞) uₙ');
    expect(humanizeMath(r'\pi \times 2'), 'π × 2');
  });

  test('texte normal inchangé et dollars échappés', () {
    expect(humanizeMath('Bonjour, ça va ?'), 'Bonjour, ça va ?');
    expect(humanizeMath(r'Ça coûte 5 \$'), r'Ça coûte 5 $');
  });

  test('markdown nettoyé', () {
    expect(cleanAiText('## Titre\n* un\n* deux'), 'Titre\n• un\n• deux');
  });
}
