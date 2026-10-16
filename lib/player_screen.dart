import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';
import 'widgets.dart';

class SmartAdaptivePlayerScreen extends StatefulWidget {
  final StreamItem initialItem;
  final List<StreamItem> playlist;
  final DeviceMode deviceMode;
  final Duration? initialStartPosition;

  const SmartAdaptivePlayerScreen({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.deviceMode,
    this.initialStartPosition,
  });

  @override
  State<SmartAdaptivePlayerScreen> createState() => _SmartAdaptivePlayerScreenState();
}

class _SmartAdaptivePlayerScreenState extends State<SmartAdaptivePlayerScreen> {
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  late StreamItem currentItem;

  bool showOsd = true;
  bool showQuickChannelDrawer = false; // Usado apenas na TV
  Timer? _hideTimer;
  final FocusNode _playPauseFocusNode = FocusNode();

  // Variáveis para Gestos Táteis no Celular
  double _gestureStartVolume = 0.5;
  double _gestureStartBrightness = 0.5;
  int _gestureSeekSeconds = 0;
  bool _isSeekingByGesture = false;
  String _gestureOverlayText = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentItem = widget.initialItem;

    _engine.openStream(currentItem, startPosition: widget.initialStartPosition);
    _resetOsdTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && showOsd && widget.deviceMode == DeviceMode.tv) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playPauseFocusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _switchStream(StreamItem item) {
    setState(() { currentItem = item; showOsd = true; });
    _engine.openStream(item);
    _resetOsdTimer();
  }

  void _resetOsdTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !showQuickChannelDrawer) setState(() => showOsd = false);
    });
  }

  void _stepChannel(int delta) {
    if (widget.playlist.isEmpty) return;
    final idx = widget.playlist.indexWhere((i) => i.id == currentItem.id);
    if (idx == -1) return;
    final next = (idx + delta + widget.playlist.length) % widget.playlist.length;
    _switchStream(widget.playlist[next]);
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mins:$secs' : '$mins:$secs';
  }

  // ===========================================================================
  // GESTOS TÁTEIS (EXCLUSIVO CELULAR)
  // ===========================================================================
  void _onPanStart(DragStartDetails details) async {
    if (widget.deviceMode == DeviceMode.tv) return;
    _isSeekingByGesture = false;
    _gestureSeekSeconds = 0;
    try {
      _gestureStartVolume = await nativeChannel.invokeMethod('getVolume') ?? 0.5;
      _gestureStartBrightness = await nativeChannel.invokeMethod('getBrightness') ?? 0.5;
    } catch (_) {}
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.deviceMode == DeviceMode.tv) return;
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    if (details.delta.dx.abs() > details.delta.dy.abs() && currentItem.type != ContentType.live) {
      _isSeekingByGesture = true;
      _gestureSeekSeconds += (details.delta.dx / width * 300).round();
      setState(() {
        showOsd = true;
        _gestureOverlayText = _gestureSeekSeconds > 0 ? '+${_gestureSeekSeconds}s' : '${_gestureSeekSeconds}s';
      });
      _resetOsdTimer();
      return;
    }

    if (!_isSeekingByGesture) {
      final isLeftSide = details.globalPosition.dx < width / 2;
      final delta = -(details.delta.dy / height);

      if (isLeftSide) {
        _gestureStartBrightness = (_gestureStartBrightness + delta).clamp(0.05, 1.0);
        nativeChannel.invokeMethod('setBrightness', {'value': _gestureStartBrightness});
        setState(() { showOsd = true; _gestureOverlayText = 'Brilho: ${(_gestureStartBrightness * 100).toInt()}%'; });
      } else {
        _gestureStartVolume = (_gestureStartVolume + delta).clamp(0.0, 1.0);
        nativeChannel.invokeMethod('setVolume', {'value': _gestureStartVolume});
        setState(() { showOsd = true; _gestureOverlayText = 'Volume: ${(_gestureStartVolume * 100).toInt()}%'; });
      }
      _resetOsdTimer();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.deviceMode == DeviceMode.tv) return;
    if (_isSeekingByGesture && _gestureSeekSeconds != 0) _engine.seekRelative(_gestureSeekSeconds);
    setState(() { _gestureOverlayText = ''; _isSeekingByGesture = false; });
  }

  // ===========================================================================
  // INTERFACE REFORMULADA: CELULAR
  // ===========================================================================
  void _showMobileChannelList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101420),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(currentItem.type == ContentType.live ? 'Canais Disponíveis' : 'Lista de Reprodução', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                  Text('${widget.playlist.length} itens', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.playlist.length,
                itemBuilder: (context, idx) {
                  final item = widget.playlist[idx];
                  final isPlaying = item.id == currentItem.id;
                  return ListTile(
                    tileColor: isPlaying ? const Color(0xFF00E5FF).withOpacity(0.1) : Colors.transparent,
                    leading: buildChannelLogo(item.logo, size: 40),
                    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal, color: isPlaying ? const Color(0xFF00E5FF) : Colors.white)),
                    subtitle: Text(item.group, maxLines: 1, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    trailing: isPlaying ? const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF)) : null,
                    onTap: () { Navigator.pop(ctx); if (!isPlaying) _switchStream(item); },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileUI() {
    final ctrl = _engine.controller;
    final isReady = _engine.isReady && ctrl != null;
    final isVod = currentItem.type != ContentType.live;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () { setState(() => showOsd = !showOsd); _resetOsdTimer(); },
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. VIDEO
            Center(
              child: _engine.hasError
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
                        const SizedBox(height: 10),
                        const Text('Sinal Indisponível', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                          onPressed: () => _engine.openStream(currentItem, forceReload: true, tryHlsFallback: true),
                          child: const Text('Tentar Novamente', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        )
                      ],
                    )
                  : isReady ? AspectRatio(aspectRatio: ctrl.value.aspectRatio, child: VideoPlayer(ctrl)) : const CircularProgressIndicator(color: Color(0xFF00E5FF)),
            ),

            // 2. OVERLAY TEXTO DE GESTOS
            if (_gestureOverlayText.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00E5FF))),
                  child: Text(_gestureOverlayText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                ),
              ),

            // 3. OSD INTUITIVO DO CELULAR
            if (showOsd)
              Container(
                color: Colors.black.withOpacity(0.55), // Fundo escurecido para destacar botões
                child: SafeArea(
                  child: Column(
                    children: [
                      // BARRA SUPERIOR
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => Navigator.pop(context)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(currentItem.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text(currentItem.group, style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF))),
                                ],
                              ),
                            ),
                            buildQualityBadge(currentItem.qualityTag),
                          ],
                        ),
                      ),
                      
                      const Spacer(),

                      // CONTROLES CENTRAIS GIGANTES
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            iconSize: 48, color: Colors.white,
                            icon: Icon(isVod ? Icons.replay_10_rounded : Icons.skip_previous_rounded),
                            onPressed: () { isVod ? _engine.seekRelative(-10) : _stepChannel(-1); _resetOsdTimer(); },
                          ),
                          GestureDetector(
                            onTap: () { _engine.togglePlayPause(); _resetOsdTimer(); },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF00E5FF), width: 2)),
                              child: Icon(isReady && ctrl!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 64, color: const Color(0xFF00E5FF)),
                            ),
                          ),
                          IconButton(
                            iconSize: 48, color: Colors.white,
                            icon: Icon(isVod ? Icons.forward_10_rounded : Icons.skip_next_rounded),
                            onPressed: () { isVod ? _engine.seekRelative(10) : _stepChannel(1); _resetOsdTimer(); },
                          ),
                        ],
                      ),

                      const Spacer(),

                      // BARRA INFERIOR (VOD VS AO VIVO)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: isVod && isReady
                            ? Column(
                                children: [
                                  VideoProgressIndicator(ctrl!, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 12), colors: const VideoProgressColors(playedColor: Color(0xFF00E5FF), backgroundColor: Colors.white24)),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatDuration(ctrl.value.position), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      Text(_formatDuration(ctrl.value.duration), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  if (_engine.currentEpg != null)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('AGORA NA TV', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                          Text(_engine.currentEpg!.nowTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A2133), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                    icon: const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFF00E5FF)),
                                    label: const Text('Canais', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () { _hideTimer?.cancel(); _showMobileChannelList(); },
                                  )
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // INTERFACE INTACTA: ANDROID TV
  // ===========================================================================
  Widget _buildTVUI() {
    final ctrl = _engine.controller;
    final isReady = _engine.isReady && ctrl != null;
    final isVod = currentItem.type != ContentType.live;

    return PopScope(
      canPop: !showQuickChannelDrawer && !showOsd,
      onPopInvoked: (didPop) {
        if (!didPop) {
          if (showQuickChannelDrawer) setState(() => showQuickChannelDrawer = false);
          else if (showOsd) setState(() => showOsd = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.mediaPlayPause) { _engine.togglePlayPause(); _resetOsdTimer(); return KeyEventResult.handled; }
              if (key == LogicalKeyboardKey.channelUp || key == LogicalKeyboardKey.arrowUp) { _stepChannel(-1); return KeyEventResult.handled; }
              if (key == LogicalKeyboardKey.channelDown || key == LogicalKeyboardKey.arrowDown) { _stepChannel(1); return KeyEventResult.handled; }
              if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
                setState(() => showOsd = true); _resetOsdTimer(); return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                if (isVod) { _engine.seekRelative(-10); setState(() => showOsd = true); } 
                else { setState(() => showQuickChannelDrawer = true); }
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowRight) {
                if (isVod) { _engine.seekRelative(10); setState(() => showOsd = true); }
                return KeyEventResult.handled;
              }
              _resetOsdTimer();
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (showQuickChannelDrawer) setState(() => showQuickChannelDrawer = false);
              else { setState(() => showOsd = !showOsd); _resetOsdTimer(); }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: _engine.hasError
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
                          const SizedBox(height: 10),
                          const Text('Sinal Indisponível ou Codec Não Suportado', style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                            onPressed: () => _engine.openStream(currentItem, forceReload: true, tryHlsFallback: true),
                            child: const Text('Forçar Codec de Software (Fallback)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          )
                        ],
                      )
                    : isReady ? AspectRatio(aspectRatio: ctrl.value.aspectRatio, child: VideoPlayer(ctrl)) : const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                ),

                if (showOsd)
                  Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent, Colors.transparent, Colors.black87])),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            TVIconButton(icon: Icons.arrow_back_ios_new_rounded, onPressed: () => Navigator.pop(context)),
                            TVIconButton(icon: Icons.menu_open_rounded, color: const Color(0xFF00E5FF), onPressed: () => setState(() => showQuickChannelDrawer = !showQuickChannelDrawer)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(currentItem.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(currentItem.group, style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                            ])),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(color: const Color(0xFF10131D).withOpacity(0.94), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isVod && _engine.currentEpg != null)
                                Row(children: [
                                  Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)), child: const Text('AGORA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_engine.currentEpg!.nowTitle, maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                  Text('A Seguir: ${_engine.currentEpg!.nextTitle}', style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF))),
                                ]),
                              if (isVod && isReady)
                                Column(children: [
                                  VideoProgressIndicator(ctrl!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFF00E5FF), backgroundColor: Colors.white10)),
                                  const SizedBox(height: 4),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                    Text(_formatDuration(ctrl.value.position), style: const TextStyle(fontSize: 10)),
                                    Text(_formatDuration(ctrl.value.duration), style: const TextStyle(fontSize: 10)),
                                  ]),
                                ]),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TVIconButton(icon: Icons.skip_previous_rounded, onPressed: () => _stepChannel(-1)),
                                  if (isVod) TVIconButton(icon: Icons.replay_10_rounded, onPressed: () => _engine.seekRelative(-10)),
                                  TVFocusableItem(
                                    focusNode: _playPauseFocusNode, autofocus: true, onSelect: _engine.togglePlayPause,
                                    builder: (c, f) => Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8), padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: f ? const Color(0xFF00E5FF).withOpacity(0.25) : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.transparent, width: 2)),
                                      child: Icon(isReady && ctrl!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: const Color(0xFF00E5FF), size: 34),
                                    ),
                                  ),
                                  if (isVod) TVIconButton(icon: Icons.forward_10_rounded, onPressed: () => _engine.seekRelative(10)),
                                  TVIconButton(icon: Icons.skip_next_rounded, onPressed: () => _stepChannel(1)),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.deviceMode == DeviceMode.mobile ? _buildMobileUI() : _buildTVUI();
  }
}
