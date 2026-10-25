import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Écran de lancement : logo, nom et signature, avec une animation discrète.
/// [error] affiche un message et un bouton pour réessayer (pas de chargement infini).
class SplashView extends StatelessWidget {
  const SplashView({super.key, this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.dark
                ? const [Color(0xFF0B241A), Color(0xFF07130F)]
                : const [Color(0xFFE8F3EC), Color(0xFFF6F8F5)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
                ),
                child: Column(
                  children: [
                    const AppLogo(size: 110),
                    const SizedBox(height: 20),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: 'Chat ',
                            style: TextStyle(color: AppColors.text)),
                        TextSpan(
                            text: 'Elvidio',
                            style: TextStyle(color: AppColors.goldText)),
                      ]),
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plus proches, même sans internet.',
                      style: TextStyle(color: AppColors.muted, fontSize: 15),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              if (error == null)
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.gold,
                      backgroundColor: AppColors.surface2,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Text('Démarrage impossible',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                      const SizedBox(height: 8),
                      Text(error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: onRetry, child: const Text('Réessayer')),
                    ],
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
