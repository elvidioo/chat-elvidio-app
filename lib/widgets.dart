import 'package:flutter/material.dart';

import 'theme.dart';

String formatTime(DateTime? date) {
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.hour)}:${two(date.minute)}';
}

Color _avatarColor(String name) {
  const palette = [
    Color(0xFF00B8D4),
    Color(0xFF7C4DFF),
    Color(0xFFFF6D91),
    Color(0xFFFFA726),
    Color(0xFF26C6A0),
    Color(0xFF5C7CFA),
  ];
  final hash = name.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return palette[hash % palette.length];
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 46});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarColor(name),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.gradient,
      ),
      child: Icon(Icons.forum_rounded, size: size * 0.5, color: Colors.white),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          width: double.infinity,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.mine,
    this.sender,
    this.media,
    this.text,
    this.time,
  });

  final bool mine;
  final String? sender;
  final Widget? media;
  final String? text;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final hasText = text != null && text!.isNotEmpty;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          gradient: mine ? AppColors.gradient : null,
          color: mine ? null : AppColors.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sender != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  sender!,
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (media != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: media,
              ),
            if (hasText)
              Text(text!, style: const TextStyle(fontSize: 15.5, height: 1.3)),
            if (time != null && time!.isNotEmpty)
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    time!,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttach,
    this.hint = 'Écris un message...',
    this.sending = false,
    this.attachIcon = Icons.add_photo_alternate_outlined,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final String hint;
  final bool sending;
  final IconData attachIcon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surface2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onAttach != null)
              IconButton(
                onPressed: sending ? null : onAttach,
                icon: Icon(attachIcon, color: AppColors.cyan),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: hint,
                  fillColor: AppColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: sending ? 0.5 : 1,
              child: GestureDetector(
                onTap: sending ? null : onSend,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.gradient,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cercles qui pulsent, pour l'écran de recherche hors ligne.
class RadarPulse extends StatefulWidget {
  const RadarPulse({super.key, this.size = 200});

  final double size;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Builder(builder: (context) {
                  final t = (controller.value + i / 3) % 1;
                  return Container(
                    width: size * (0.3 + 0.7 * t),
                    height: size * (0.3 + 0.7 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cyan.withAlpha((200 * (1 - t)).toInt()),
                        width: 2,
                      ),
                    ),
                  );
                }),
              Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.gradient,
                ),
                child: Icon(
                  Icons.wifi_tethering,
                  color: Colors.white,
                  size: size * 0.15,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
