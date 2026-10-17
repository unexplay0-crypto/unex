import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';

// =============================================================================
// COMPONENTES OTIMIZADOS E CONTROLES DE TV (10-FOOT UI)
// =============================================================================

class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final bool autoScroll; 
  final bool autofocus; 
  final FocusNode? focusNode;
  final VoidCallback? onMoveLeft; 
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const TVFocusableItem({
    super.key, 
    required this.onSelect, 
    required this.builder, 
    this.autoScroll = true, 
    this.autofocus = false, 
    this.focusNode, 
    this.onMoveLeft, 
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;
  
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode, 
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f && widget.autoScroll && mounted) {
          Scrollable.ensureVisible(context, alignment: 0.35, duration: const Duration(milliseconds: 150));
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) { 
            widget.onSelect(); 
            return KeyEventResult.handled; 
          }
          if (widget.onMoveLeft != null && key == LogicalKeyboardKey.arrowLeft) { widget.onMoveLeft!(); return KeyEventResult.handled; }
          if (widget.onMoveRight != null && key == LogicalKeyboardKey.arrowRight) { widget.onMoveRight!(); return KeyEventResult.handled; }
          if (widget.onMoveUp != null && key == LogicalKeyboardKey.arrowUp) { widget.onMoveUp!(); return KeyEventResult.handled; }
          if (widget.onMoveDown != null && key == LogicalKeyboardKey.arrowDown) { widget.onMoveDown!(); return KeyEventResult.handled; }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, 
        onTap: widget.onSelect, 
        child: widget.builder(context, _isFocused)
      ),
    );
  }
}

class TVIconButton extends StatelessWidget {
  final IconData icon; 
  final VoidCallback onPressed; 
  final Color color; 
  final double size; 
  final bool autofocus;
  
  const TVIconButton({
    super.key, 
    required this.icon, 
    required this.onPressed, 
    this.color = Colors.white70, 
    this.size = 20, 
    this.autofocus = false
  });
  
  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      autofocus: autofocus, 
      autoScroll: false, 
      onSelect: onPressed,
      builder: (context, isFocused) => AnimatedScale(
        scale: isFocused ? 1.15 : 1.0, 
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isFocused ? const Color(0xFF00E5FF).withOpacity(0.25) : Colors.transparent, 
            borderRadius: BorderRadius.circular(50), 
            border: Border.all(color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent, width: 2)
          ),
          child: Icon(icon, color: isFocused ? Colors.white : color, size: size),
        ),
      ),
    );
  }
}

// Controle de Cache Estrito para Imagens (Prevenção de OutOfMemory)
Widget buildStreamingPosterCard({
  required String title, 
  required String subtitle, 
  required String logoUrl, 
  required String badgeText, 
  required VoidCallback onTap, 
  bool isFocused = false, 
  bool isPlaying = false, 
  bool isFavorite = false, 
  double? progress, 
  VoidCallback? onFavoriteTap
}) {
  return AnimatedScale(
    scale: isFocused ? 1.05 : 1.0, 
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOutCubic,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151124), 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isFocused ? const Color(0xFF00E5FF) : isPlaying ? const Color(0xFF2979FF) : Colors.white12, width: isFocused ? 2.5 : 1.5),
        boxShadow: isFocused ? [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 12, spreadRadius: 2)] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            logoUrl.isNotEmpty 
              ? Image.network(logoUrl, fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_,__,___) => const Icon(Icons.movie_creation_rounded, color: Color(0xFF00E5FF), size: 40)) 
              : const Icon(Icons.movie_creation_rounded, color: Color(0xFF00E5FF), size: 40),
            
            Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, Colors.transparent, Colors.black87], stops: [0.0, 0.4, 1.0]))),
            Positioned(top: 8, left: 8, child: buildQualityBadge(badgeText)),
            if (onFavoriteTap != null) 
              Positioned(top: 6, right: 6, child: GestureDetector(onTap: onFavoriteTap, child: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: isFavorite ? Colors.amber : Colors.white70, size: 22))),
            
            Positioned(
              bottom: 10, left: 10, right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                  if (progress != null && progress > 0) 
                    Padding(
                      padding: const EdgeInsets.only(top: 6), 
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white24, color: const Color(0xFF00E5FF)),
                      ),
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
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF).withOpacity(0.25) : Colors.black87, 
      borderRadius: BorderRadius.circular(4), 
      border: Border.all(color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF) : Colors.white24, width: 1)
    ),
    child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF) : Colors.white)),
  );
}

Widget buildChannelLogo(String url, {double size = 48}) {
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(color: const Color(0xFF090B10), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10), 
      child: url.isNotEmpty 
        ? Image.network(url, fit: BoxFit.contain, cacheWidth: 120, errorBuilder: (_,__,___) => const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF))) 
        : const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF))
    ),
  );
}

// =============================================================================
// MODAL DE CONTROLE PARENTAL (DESBLOQUEIO DE CONTEÚDO +18) COM TECLADO NATIVO DA TV
// =============================================================================
Future<bool> showParentalPinPrompt(BuildContext context) async {
  bool unlocked = false;
  final pinCtrl = TextEditingController();
  final correctPin = await AppStorage.loadParentalPin();
  String errorText = '';

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) => AlertDialog(
        backgroundColor: const Color(0xFF101420),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.redAccent, width: 2)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('Conteúdo Protegido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Insira o PIN de Controle Parental para acessar este conteúdo.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              autofocus: true, // Isso ativa automaticamente o teclado nativo da TV ao abrir
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF0A0C12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
              ),
              onSubmitted: (val) {
                if (val == correctPin) {
                  unlocked = true;
                  Navigator.pop(ctx);
                } else {
                  setModal(() { errorText = 'PIN Incorreto. Tente novamente.'; pinCtrl.clear(); });
                }
              },
            ),
            if (errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(errorText, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        actions: [
          TVFocusableItem(
            autoScroll: false,
            onSelect: () => Navigator.pop(ctx),
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: f ? Colors.white : Colors.white24), borderRadius: BorderRadius.circular(8)),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white)),
            ),
          ),
          TVFocusableItem(
            autoScroll: false,
            onSelect: () {
              if (pinCtrl.text == correctPin) {
                unlocked = true;
                Navigator.pop(ctx);
              } else {
                setModal(() { errorText = 'PIN Incorreto.'; pinCtrl.clear(); });
              }
            },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: f ? Colors.white : Colors.redAccent, borderRadius: BorderRadius.circular(8)),
              child: Text('Desbloquear', style: TextStyle(color: f ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ),
  );

  return unlocked;
}

// Modal de Retomada VOD
Future<Duration?> showVodResumePrompt({required BuildContext context, required VodProgressEntry entry}) async {
  return showDialog<Duration?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121622), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF00E5FF))),
      title: Text(entry.item.name, maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Parou em ${entry.formattedPosition} (${entry.formattedRemaining}).', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: entry.progress, minHeight: 6, color: const Color(0xFF00E5FF), backgroundColor: Colors.white12),
        ),
      ]),
      actions: [
        TVFocusableItem(
          autofocus: true, 
          onSelect: () => Navigator.pop(ctx, Duration(seconds: entry.positionSeconds)), 
          builder: (c, f) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: f ? Colors.white : const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(8)), child: const Text('Continuar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))
        ),
        TVFocusableItem(
          onSelect: () => Navigator.pop(ctx, Duration.zero), 
          builder: (c, f) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24), borderRadius: BorderRadius.circular(8)), child: const Text('Do Início'))
        ),
      ],
    ),
  );
}
