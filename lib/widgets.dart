import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'presence.dart';
import 'theme.dart';

const _videoExt = ['mp4', 'mov', '3gp', 'webm', 'mkv'];

bool isVideoUrl(String url) {
  final clean = url.split('?').first.toLowerCase();
  return _videoExt.any(clean.endsWith);
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatTime(DateTime? date) {
  if (date == null) return '';
  return '${_two(date.hour)}:${_two(date.minute)}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Heure dans la liste des discussions : 14:32, Hier, 05/10.
String formatListTime(DateTime? date) {
  if (date == null) return '';
  final now = DateTime.now();
  if (_sameDay(date, now)) return formatTime(date);
  if (_sameDay(date, now.subtract(const Duration(days: 1)))) return 'Hier';
  return '${_two(date.day)}/${_two(date.month)}';
}

/// Séparateur de temps dans une conversation.
String formatHeaderTime(DateTime date) {
  if (_sameDay(date, DateTime.now())) return formatTime(date);
  return '${_two(date.day)}/${_two(date.month)} ${formatTime(date)}';
}

Color _avatarColor(String name) {
  const palette = [
    Color(0xFF0084FF),
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
  const Avatar({
    super.key,
    required this.name,
    this.size = 46,
    this.userId,
    this.showOnline = false,
    this.photoUrl,
  });

  final String name;
  final double size;
  final String? userId;
  final bool showOnline;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final id = userId;
    if (id == null && photoUrl == null) return _circle(photoUrl);
    return ListenableBuilder(
      listenable: Listenable.merge([LivePresence.I.avatars, LivePresence.I.online]),
      builder: (context, _) {
        final url = photoUrl ?? LivePresence.I.avatars.value[id];
        final isOn = showOnline && id != null && LivePresence.I.online.value.contains(id);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _circle(url),
            if (isOn)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: size * 0.28,
                  height: size * 0.28,
                  decoration: BoxDecoration(
                    color: AppColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bg, width: 2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _circle(String? url) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _letter(letter),
        ),
      );
    }
    return _letter(letter);
  }

  Widget _letter(String letter) {
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
      decoration: BoxDecoration(
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
            borderRadius: BorderRadius.circular(26),
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

/// Bulle de message façon Messenger : bleue pour moi, grise pour l'autre,
/// coins resserrés quand plusieurs messages se suivent.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.mine,
    this.sender,
    this.media,
    this.text,
    this.time,
    this.avatarName,
    this.avatarId,
    this.quoteName,
    this.quoteText,
    this.status,
    this.read = false,
    this.joinedAbove = false,
    this.joinedBelow = false,
  });

  final bool mine;
  final String? sender;
  final Widget? media;
  final String? text;
  final String? time;
  final String? avatarName;
  final String? avatarId;
  final String? quoteName;
  final String? quoteText;
  final String? status;
  final bool read;
  final bool joinedAbove;
  final bool joinedBelow;

  BorderRadius _radius() {
    const big = Radius.circular(18);
    const small = Radius.circular(4);
    return BorderRadius.only(
      topLeft: (!mine && joinedAbove) ? small : big,
      bottomLeft: (!mine && joinedBelow) ? small : big,
      topRight: (mine && joinedAbove) ? small : big,
      bottomRight: (mine && joinedBelow) ? small : big,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = text != null && text!.isNotEmpty;
    final hasQuote = quoteText != null;
    final onlyMedia = media != null && !hasText && sender == null && !hasQuote;
    final bigEmoji = hasText && media == null && text!.trim() == '\u{1F44D}';
    final reserveAvatar = !mine && avatarName != null;
    final showAvatar = reserveAvatar && !joinedBelow;

    final Widget content;
    if (bigEmoji) {
      content = const Text('\u{1F44D}', style: TextStyle(fontSize: 46));
    } else if (onlyMedia) {
      content = media!;
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.bubbleTheirs,
          borderRadius: _radius(),
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
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (hasQuote)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: mine ? Colors.white24 : Colors.black12,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 3,
                            color: mine ? Colors.white : AppColors.primary,
                          ),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    quoteName ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: mine
                                          ? Colors.white
                                          : AppColors.primary,
                                    ),
                                  ),
                                  Text(
                                    quoteText!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: mine
                                          ? Colors.white70
                                          : AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (media != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: media,
              ),
            if (hasText)
              LinkText(
                text!,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.3,
                  color: mine ? Colors.white : AppColors.text,
                ),
                linkColor: mine ? Colors.white : AppColors.primary,
              ),
            if (time != null && time!.isNotEmpty)
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    time!,
                    style: TextStyle(
                      fontSize: 11,
                      color: mine ? Colors.white70 : AppColors.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: joinedAbove ? 1.5 : 6),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (reserveAvatar)
            SizedBox(
              width: 34,
              child: showAvatar ? Avatar(name: avatarName!, size: 26, userId: avatarId) : null,
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  content,
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 2),
                      child: Text(
                        status!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: read ? FontWeight.w700 : FontWeight.w400,
                          color: read ? AppColors.primary : AppColors.muted,
                        ),
                      ),
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

class TimeHeader extends StatelessWidget {
  const TimeHeader(this.date, {super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          formatHeaderTime(date),
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    );
  }
}

/// Zone de saisie façon Messenger : champ "Aa", puis envoyer ou pouce.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttach,
    this.onLike,
    this.onMic,
    this.onTyping,
    this.hint = 'Aa',
    this.sending = false,
    this.attachIcon = Icons.photo_library_rounded,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onLike;
  final VoidCallback? onMic;
  final VoidCallback? onTyping;
  final String hint;
  final bool sending;
  final IconData attachIcon;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  void _changed() {
    if (widget.controller.text.isNotEmpty) widget.onTyping?.call();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final likeMode = !hasText && widget.onLike != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.onAttach != null)
              IconButton(
                onPressed: widget.sending ? null : widget.onAttach,
                icon: Icon(widget.attachIcon, color: AppColors.primary),
              ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            if (!hasText && widget.onMic != null)
              IconButton(
                onPressed: widget.sending ? null : widget.onMic,
                icon: Icon(Icons.mic, color: AppColors.primary, size: 28),
              ),
            IconButton(
              onPressed: widget.sending
                  ? null
                  : (likeMode ? widget.onLike : widget.onSend),
              icon: Icon(
                likeMode ? Icons.thumb_up_alt_rounded : Icons.send_rounded,
                color: AppColors.primary,
                size: 28,
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
                        color:
                            AppColors.primary.withAlpha((200 * (1 - t)).toInt()),
                        width: 2,
                      ),
                    ),
                  );
                }),
              Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
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


/// Texte dont les liens (http, https, www) sont cliquables.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, required this.style, required this.linkColor});

  final String text;
  final TextStyle style;
  final Color linkColor;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _taps = [];

  void _disposeTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _disposeTaps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeTaps();
    final re = RegExp(r'((https?://|www\.)[^\s]+)', caseSensitive: false);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(widget.text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      var link = m.group(0)!;
      // ponctuation finale qui ne fait pas partie du lien
      var trail = '';
      while (link.isNotEmpty && '.,;:!?)'.contains(link[link.length - 1])) {
        trail = link[link.length - 1] + trail;
        link = link.substring(0, link.length - 1);
      }
      final url = link.toLowerCase().startsWith('www.') ? 'https://$link' : link;
      final tap = TapGestureRecognizer()
        ..onTap = () {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        };
      _taps.add(tap);
      spans.add(TextSpan(
        text: link,
        style: TextStyle(
          color: widget.linkColor,
          decoration: TextDecoration.underline,
        ),
        recognizer: tap,
      ));
      if (trail.isNotEmpty) spans.add(TextSpan(text: trail));
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
