import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';

class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final bool autoScroll; final bool autofocus; final FocusNode? focusNode;
  final VoidCallback? onMoveLeft; final VoidCallback? onMoveRight;

  const TVFocusableItem({super.key, required this.onSelect, required this.builder, this.autoScroll = true, this.autofocus = false, this.focusNode, this.onMoveLeft, this.onMoveRight});

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode, autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f && widget.autoScroll && mounted) Scrollable.ensureVisible(context, alignment: 0.35, duration: const Duration(milliseconds: 150));
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) { widget.onSelect(); return KeyEventResult.handled; }
          if (widget.onMoveLeft != null && key == LogicalKeyboardKey.arrowLeft) { widget.onMoveLeft!(); return KeyEventResult.handled; }
          if (widget.onMoveRight != null && key == LogicalKeyboardKey.arrowRight) { widget.onMoveRight!(); return KeyEventResult.handled; }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onSelect, child: widget.builder(context, _isFocused)),
    );
  }
}

class TVIconButton extends StatelessWidget {
  final IconData icon; final VoidCallback onPressed; final Color color; final double size; final bool autofocus;
  const TVIconButton({super.key, required this.icon, required this.onPressed, this.color = Colors.white70, this.size = 20, this.autofocus = false});
  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      autofocus: autofocus, autoScroll: false, onSelect: onPressed,
      builder: (context, isFocused) => AnimatedScale(
        scale: isFocused ? 1.12 : 1.0, duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: isFocused ? const Color(0xFF00E5FF).withOpacity(0.25) : Colors.transparent, borderRadius: BorderRadius.circular(9), border: Border.all(color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent, width: 1.5)),
          child: Icon(icon, color: isFocused ? Colors.white : color, size: size),
        ),
      ),
    );
  }
}

Widget buildStreamingPosterCard({required String title, required String subtitle, required String logoUrl, required String badgeText, required VoidCallback onTap, bool isFocused = false, bool isPlaying = false, bool isFavorite = false, double? progress, VoidCallback? onFavoriteTap}) {
  return AnimatedScale(
    scale: isFocused ? 1.06 : 1.0, duration: const Duration(milliseconds: 150),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121622), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isFocused ? const Color(0xFF00E5FF) : isPlaying ? const Color(0xFF2979FF) : Colors.white12, width: isFocused ? 2.5 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            logoUrl.isNotEmpty ? Image.network(logoUrl, fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_,__,___) => const Icon(Icons.movie, color: Color(0xFF00E5FF))) : const Icon(Icons.movie, color: Color(0xFF00E5FF)),
            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, Colors.transparent, Colors.black87], stops: const [0.0, 0.4, 1.0]))),
            Positioned(top: 8, left: 8, child: buildQualityBadge(badgeText)),
            if (onFavoriteTap != null) Positioned(top: 6, right: 6, child: GestureDetector(onTap: onFavoriteTap, child: Icon(isFavorite ? Icons.star : Icons.star_border, color: isFavorite ? Colors.amber : Colors.white70, size: 20))),
            Positioned(
              bottom: 10, left: 10, right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF))),
                  if (progress != null && progress > 0) 
                    Padding(
                      padding: const EdgeInsets.only(top: 6), 
                      child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white24, color: const Color(0xFF00E5FF)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildQualityBadge(String tag) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF).withOpacity(0.25) : Colors.black87, borderRadius: BorderRadius.circular(5), border: Border.all(color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF) : Colors.white24, width: 0.8)),
    child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF) : Colors.white)),
  );
}

Widget buildChannelLogo(String url, {double size = 44}) {
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(color: const Color(0xFF08090E), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
    child: ClipRRect(borderRadius: BorderRadius.circular(10), child: url.isNotEmpty ? Image.network(url, fit: BoxFit.contain, cacheWidth: 100, errorBuilder: (_,__,___) => const Icon(Icons.tv, color: Color(0xFF00E5FF))) : const Icon(Icons.tv, color: Color(0xFF00E5FF))),
  );
}

Future<Duration?> showVodResumePrompt({required BuildContext context, required VodProgressEntry entry}) async {
  return showDialog<Duration?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121622), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF00E5FF))),
      title: Text(entry.item.name, maxLines: 1, style: const TextStyle(fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Você parou em ${entry.formattedPosition} (${entry.formattedRemaining}).', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: entry.progress, minHeight: 6, color: const Color(0xFF00E5FF), backgroundColor: Colors.white12),
      ]),
      actions: [
        TVFocusableItem(autofocus: true, onSelect: () => Navigator.pop(ctx, Duration(seconds: entry.positionSeconds)), builder: (c, f) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: f ? Colors.white : const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(8)), child: const Text('Continuar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
        TVFocusableItem(onSelect: () => Navigator.pop(ctx, Duration.zero), builder: (c, f) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white12), borderRadius: BorderRadius.circular(8)), child: const Text('Do Início'))),
      ],
    ),
  );
}
