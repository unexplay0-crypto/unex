import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';

// =============================================================================
// COMPONENTES OTIMIZADOS E CONTROLOS DE TV (10-FOOT UI)
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
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 150),
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.gameButtonA) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (widget.onMoveLeft != null && key == LogicalKeyboardKey.arrowLeft) {
            widget.onMoveLeft!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveRight != null && key == LogicalKeyboardKey.arrowRight) {
            widget.onMoveRight!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveUp != null && key == LogicalKeyboardKey.arrowUp) {
            widget.onMoveUp!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveDown != null && key == LogicalKeyboardKey.arrowDown) {
            widget.onMoveDown!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _isFocused),
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
    this.autofocus = false,
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
            border: Border.all(
              color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(icon, color: isFocused ? Colors.white : color, size: size),
        ),
      ),
    );
  }
}

// =============================================================================
// NOVO TECLADO VIRTUAL DE TV (FOCO NO 'Q', 3 BOTÕES NA BASE, ATALHOS INTEGRADOS)
// =============================================================================
Future<void> showTVVirtualKeyboard(
  BuildContext context,
  TextEditingController ctrl,
  String title, {
  bool isPassword = false,
  ValueChanged<String>? onChanged,
}) async {
  const row1 = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  const row2 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  const row3 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  const row4 = ['z', 'x', 'c', 'v', 'b', 'n', 'm', 'http://', '.'];

  bool isUpper = false;
  final FocusNode qFocusNode = FocusNode();

  void focusQKey() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (qFocusNode.canRequestFocus) {
        qFocusNode.requestFocus();
      }
    });
  }

  // Garante foco imediato na tecla 'Q/q' ao abrir o teclado
  focusQKey();

  await showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) {
        final displayText = ctrl.text.isEmpty
            ? 'Use as setas para escrever...'
            : (isPassword ? '•' * ctrl.text.length : ctrl.text);

        void insertText(String value) {
          setModal(() {
            ctrl.text += value;
          });
          onChanged?.call(ctrl.text);
        }

        void backspace() {
          if (ctrl.text.isNotEmpty) {
            setModal(() {
              ctrl.text = ctrl.text.substring(0, ctrl.text.length - 1);
            });
            onChanged?.call(ctrl.text);
          }
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 700,
              margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0C12).withOpacity(0.98),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.85),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. VISOR DO CAMPO ATUAL + BOTÃO OK PARA FECHAR
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151124),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            '$displayText▌',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: ctrl.text.isEmpty ? Colors.white38 : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => Navigator.pop(ctx),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: f ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: const Text(
                            'CONCLUÍR',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. GRELHA DE TECLAS: LINHA 1 (Números)
                  Wrap(
                    spacing: 6,
                    children: row1
                        .map((k) => _buildKeyBtn(
                              label: k,
                              width: 56,
                              onTap: () => insertText(k),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 6),

                  // 3. GRELHA DE TECLAS: LINHA 2 (Foco cravado no Q/q)
                  Wrap(
                    spacing: 6,
                    children: row2.map((k) {
                      final isQ = k == 'q';
                      final label = isUpper ? k.toUpperCase() : k;
                      return _buildKeyBtn(
                        label: label,
                        width: 56,
                        focusNode: isQ ? qFocusNode : null,
                        autofocus: isQ,
                        onTap: () => insertText(label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),

                  // 4. GRELHA DE TECLAS: LINHA 3
                  Wrap(
                    spacing: 6,
                    children: row3.map((k) {
                      final label = isUpper ? k.toUpperCase() : k;
                      return _buildKeyBtn(
                        label: label,
                        width: 56,
                        onTap: () => insertText(label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),

                  // 5. GRELHA DE TECLAS: LINHA 4 (Integra http:// e .)
                  Wrap(
                    spacing: 6,
                    children: row4.map((k) {
                      final isSpecial = k == 'http://' || k == '.';
                      final label = isSpecial ? k : (isUpper ? k.toUpperCase() : k);
                      return _buildKeyBtn(
                        label: label,
                        width: k == 'http://' ? 100 : 56,
                        color: isSpecial ? const Color(0xFF1A253B) : const Color(0xFF151124),
                        textColor: isSpecial ? const Color(0xFF00E5FF) : Colors.white,
                        onTap: () => insertText(label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // 6. BASE: EXATAMENTE 3 BOTÕES IGUAIS
                  Row(
                    children: [
                      Expanded(
                        child: _buildKeyBtn(
                          label: isUpper ? '⇧ MAIÚSC. (ON)' : '⇧ MAIÚSCULA',
                          color: isUpper ? const Color(0xFF2979FF) : const Color(0xFF181C28),
                          onTap: () {
                            setModal(() => isUpper = !isUpper);
                            // Sempre que muda de layout, recoloca o foco no 'Q'
                            focusQKey();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKeyBtn(
                          label: 'ESPAÇO',
                          color: const Color(0xFF181C28),
                          onTap: () => insertText(' '),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKeyBtn(
                          label: '⌫ APAGAR',
                          color: const Color(0xFF2C1D24),
                          textColor: Colors.orangeAccent,
                          onTap: backspace,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildKeyBtn({
  required String label,
  required VoidCallback onTap,
  double? width,
  FocusNode? focusNode,
  bool autofocus = false,
  Color color = const Color(0xFF151124),
  Color textColor = Colors.white,
}) {
  return TVFocusableItem(
    focusNode: focusNode,
    autofocus: autofocus,
    autoScroll: false,
    onSelect: onTap,
    builder: (c, f) => AnimatedScale(
      scale: f ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: f ? const Color(0xFF00E5FF) : color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: f ? Colors.white : Colors.white24,
            width: f ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: f ? Colors.black : textColor,
          ),
        ),
      ),
    ),
  );
}

// =============================================================================
// MODAL CONTROLO PARENTAL (+18) USANDO O NOSSO TECLADO NATIVO
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conteúdo Adulto (+18)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aperte OK para introduzir o PIN de bloqueio parental (Padrão: 0000):',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TVFocusableItem(
              autofocus: true,
              autoScroll: false,
              onSelect: () async {
                // Chama o nosso teclado em dock invisivelmente
                await showTVVirtualKeyboard(context, pinCtrl, 'PIN', isPassword: true);
                setModal(() {});
              },
              builder: (c, f) => Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0C12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: f ? const Color(0xFF00E5FF) : Colors.white24,
                    width: f ? 2 : 1,
                  ),
                ),
                child: Text(
                  pinCtrl.text.isEmpty ? 'Aperte OK para digitar...' : '•' * pinCtrl.text.length,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    letterSpacing: pinCtrl.text.isEmpty ? 0 : 8,
                    fontWeight: FontWeight.bold,
                    color: pinCtrl.text.isEmpty ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
            ),
            if (errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  errorText,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TVFocusableItem(
            autoScroll: false,
            onSelect: () => Navigator.pop(ctx),
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: f ? Colors.white : Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white)),
            ),
          ),
          TVFocusableItem(
            autoScroll: false,
            onSelect: () {
              if (pinCtrl.text.trim() == correctPin) {
                unlocked = true;
                Navigator.pop(ctx);
              } else {
                setModal(() {
                  errorText = 'PIN incorreto. Tente novamente.';
                  pinCtrl.clear();
                });
              }
            },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: f ? Colors.white : Colors.redAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Desbloquear',
                style: TextStyle(
                  color: f ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return unlocked;
}

// =============================================================================
// CACHE ESTREITO DE IMAGENS P/ TV BOXES
// =============================================================================
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
  VoidCallback? onFavoriteTap,
}) {
  return AnimatedScale(
    scale: isFocused ? 1.05 : 1.0,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOutCubic,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151124),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused
              ? const Color(0xFF00E5FF)
              : isPlaying
                  ? const Color(0xFF2979FF)
                  : Colors.white12,
          width: isFocused ? 2.5 : 1.5,
        ),
        boxShadow: isFocused
            ? [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 12, spreadRadius: 2)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            logoUrl.isNotEmpty
                ? Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 200, // Proteção Anti-OutOfMemory
                    errorBuilder: (_, __, ___) => const Icon(Icons.movie_creation_rounded, color: Color(0xFF00E5FF), size: 40),
                  )
                : const Icon(Icons.movie_creation_rounded, color: Color(0xFF00E5FF), size: 40),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black38, Colors.transparent, Colors.black87],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
            Positioned(top: 8, left: 8, child: buildQualityBadge(badgeText)),
            if (onFavoriteTap != null)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onFavoriteTap,
                  child: Icon(
                    isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isFavorite ? Colors.amber : Colors.white70,
                    size: 22,
                  ),
                ),
              ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                  ),
                  if (progress != null && progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          color: const Color(0xFF00E5FF),
                        ),
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
      border: Border.all(
        color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF) : Colors.white24,
        width: 1,
      ),
    ),
    child: Text(
      tag,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
        color: tag == '4K' || tag == 'FHD' ? const Color(0xFF00E5FF) : Colors.white,
      ),
    ),
  );
}

Widget buildChannelLogo(String url, {double size = 48}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF090B10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.contain,
              cacheWidth: 120, // Proteção Anti-OutOfMemory
              errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
            )
          : const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
    ),
  );
}

Future<Duration?> showVodResumePrompt({
  required BuildContext context,
  required VodProgressEntry entry,
}) async {
  return showDialog<Duration?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121622),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF00E5FF)),
      ),
      title: Text(entry.item.name, maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parou em ${entry.formattedPosition} (${entry.formattedRemaining}).',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 6,
              color: const Color(0xFF00E5FF),
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
      actions: [
        TVFocusableItem(
          autofocus: true,
          onSelect: () => Navigator.pop(ctx, Duration(seconds: entry.positionSeconds)),
          builder: (c, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: f ? Colors.white : const Color(0xFF00E5FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Continuar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
        TVFocusableItem(
          onSelect: () => Navigator.pop(ctx, Duration.zero),
          builder: (c, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Do Início'),
          ),
        ),
      ],
    ),
  );
}
