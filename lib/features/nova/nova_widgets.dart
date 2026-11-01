import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'nova_data.dart';

/// Anneau de progression (objectif du jour, résultat de quiz).
class NovaRing extends StatelessWidget {
  const NovaRing({super.key, required this.value, required this.size, this.child, this.color});
  final double value; // 0..1
  final double size;
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0, 1).toDouble(), color ?? Colors.white),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color);
  final double v;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(6, 6, s.width - 12, s.height - 12);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = color.withValues(alpha: 0.18);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;
    c.drawArc(r, 0, math.pi * 2, false, bg);
    c.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

class NovaCard extends StatelessWidget {
  const NovaCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.gradient});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? AppColors.surface : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(22),
            border: gradient == null ? Border.all(color: AppColors.surface2) : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

class NovaBadge extends StatelessWidget {
  const NovaBadge(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF22D3EE).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 11, color: Color(0xFF22D3EE), fontWeight: FontWeight.w700)),
      );
}

class SubjectChip extends StatelessWidget {
  const SubjectChip(this.subject, {super.key, this.size = 46});
  final String subject;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = novaColor(subject);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(novaIcon(subject), color: c, size: size * 0.55),
    );
  }
}

class NovaLoading extends StatelessWidget {
  const NovaLoading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
}

class NovaError extends StatelessWidget {
  const NovaError(this.text, this.onRetry, {super.key});
  final String text;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ]),
        ),
      );
}
