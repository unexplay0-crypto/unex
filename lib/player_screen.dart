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
  bool showDrawer = false;
  Timer? _hideTimer;
  final FocusNode _playPauseNode = FocusNode();

  // Gestos Táteis (Exclusivo Telemóvel)
  double _gestureStartVolume = 0.5;
  double _gestureStartBrightness = 0.5;
  int _gestureSeekSeconds = 0;
  bool _isSeekingByGesture = false;
  String _gestureOverlayText = '';
  bool _adultUnlocked = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentItem = widget.initialItem;

    if (_engine.currentItem?.id != currentItem.id) {
      _engine.openStream(currentItem, startPosition: widget.initialStartPosition);
    } else if (widget.initialStartPosition != null && currentItem.type != ContentType.live) {
      _engine.controller?.seekTo(widget.initialStartPosition!);
    }

    _resetOsdTimer();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.deviceMode == DeviceMode.tv) {
        if (_playPauseNode.canRequestFocus) _playPauseNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playPauseNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _switchStream(StreamItem item) async {
    if (item.isAdult && !_adultUnlocked) {
      _hideTimer?.cancel(); 
      final unlocked = await showParentalPinPrompt(context);
      if (!unlocked || !mounted) {
        _resetOsdTimer();
        return;
      }
      setState(() => _adultUnlocked = true);
    }
    
    setState(() { currentItem = item; showOsd = true; showDrawer = false; });
    _engine.openStream(item);
    _resetOsdTimer();
    if (widget.deviceMode == DeviceMode.tv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_playPauseNode.canRequestFocus) _playPauseNode.requestFocus();
      });
    }
  }

  void _resetOsdTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !showDrawer) setState(() => showOsd = false);
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

  void _toggleOsd() {
    setState(() {
      if (showDrawer) {
        showDrawer = false;
      } else {
        showOsd = !showOsd;
      }
    });
    if (showOsd) {
      _resetOsdTimer();
      if (widget.deviceMode == DeviceMode.tv) {
         WidgetsBinding.instance.addPostFrameCallback((_) {
           if (_playPauseNode.canRequestFocus) _playPauseNode.requestFocus();
         });
      }
    }
  }

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

  Widget _buildSideDrawer() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      top: 0, bottom: 0,
      right: showDrawer ? 0 : -320,
      width: 300,
      child: Container(
        color: const Color(0xFF090B10).withOpacity(0.95),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 8, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(currentItem.type == ContentType.live ? 'Canais' : 'Lista', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00E5FF), fontSize: 16)),
                  TVIconButton(icon: Icons.close_rounded, onPressed: () => setState(() => showDrawer = false)),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: widget.playlist.length,
                itemBuilder: (context, idx) {
                  final item = widget.playlist[idx];
                  final isPlaying = item.id == currentItem.id;
                  return TVFocusableItem(
                    autofocus: isPlaying && showDrawer && widget.deviceMode == DeviceMode.tv,
                    onSelect: () => _switchStream(item),
                    builder: (c, isFocused) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isPlaying ? const Color(0xFF00E5FF).withOpacity(0.15) : isFocused ? Colors.white.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent, width: isFocused ? 2 : 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        leading: buildChannelLogo(item.logo, size: 40),
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: isPlaying || isFocused ? FontWeight.bold : FontWeight.normal, color: isPlaying ? const Color(0xFF00E5FF) : Colors.white)),
                        trailing: isPlaying ? const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF), size: 22) : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final ctrl = _engine.controller;
        final isReady = _engine.isReady && ctrl != null && ctrl.value.isInitialized;
        final isVod = currentItem.type != ContentType.live;

        return PopScope(
          canPop: !showDrawer && !showOsd,
          onPopInvoked: (didPop) {
            if (!didPop) {
              if (showDrawer) setState(() => showDrawer = false);
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
                  
                  if (!showOsd && !showDrawer) {
                    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
                      _toggleOsd(); return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isVod) { _engine.seekRelative(-10); _toggleOsd(); } else { setState(() => showDrawer = true); }
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowRight) {
                      if (isVod) { _engine.seekRelative(10); _toggleOsd(); }
                      return KeyEventResult.handled;
                    }
                  } else {
                    _resetOsdTimer();
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // CAMADA 1: VÍDEO
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleOsd,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: Center(
                      child: _engine.hasError
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 54),
                              const SizedBox(height: 12),
                              const Text('Sinal Indisponível', style: TextStyle(color: Colors.white70, fontSize: 16)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Tentar Novamente', style: TextStyle(fontWeight: FontWeight.w900)),
                                onPressed: () => _engine.openStream(currentItem, forceReload: true), // REMOVIDO tryHlsFallback
                              )
                            ],
                          )
                        : isReady 
                            ? AspectRatio(
                                aspectRatio: ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : (16/9), 
                                child: VideoPlayer(ctrl)
                              ) 
                            : const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                    ),
                  ),

                  // CAMADA 2: OVERLAY GESTOS (MÓVEL)
                  if (_gestureOverlayText.isNotEmpty)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00E5FF), width: 2)),
                        child: Text(_gestureOverlayText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF))),
                      ),
                    ),

                  // CAMADA 3: OSD (ON-SCREEN DISPLAY)
                  AnimatedOpacity(
                    opacity: showOsd ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: IgnorePointer(
                      ignoring: !showOsd,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.black87, Colors.black45, Colors.transparent, Colors.black54, Colors.black87],
                            stops: [0.0, 0.2, 0.5, 0.8, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            children: [
                              // BARRA SUPERIOR
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                child: Row(
                                  children: [
                                    TVIconButton(icon: Icons.arrow_back_ios_new_rounded, size: 24, onPressed: () => Navigator.pop(context)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(currentItem.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                          const SizedBox(height: 2),
                                          Text(currentItem.group, style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    buildQualityBadge(currentItem.qualityTag),
                                  ],
                                ),
                              ),

                              const Spacer(),

                              // CONTROLES CENTRAIS
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TVIconButton(
                                    icon: isVod ? Icons.replay_10_rounded : Icons.skip_previous_rounded,
                                    size: 46,
                                    onPressed: () { isVod ? _engine.seekRelative(-10) : _stepChannel(-1); _resetOsdTimer(); },
                                  ),
                                  const SizedBox(width: 48),
                                  TVFocusableItem(
                                    focusNode: _playPauseNode,
                                    autofocus: true,
                                    onSelect: () { _engine.togglePlayPause(); _resetOsdTimer(); },
                                    builder: (c, f) => AnimatedScale(
                                      scale: f ? 1.1 : 1.0,
                                      duration: const Duration(milliseconds: 150),
                                      child: Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(color: f ? const Color(0xFF00E5FF) : Colors.black54, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF00E5FF), width: 2.5)),
                                        child: Icon(isReady && ctrl!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 58, color: f ? Colors.black : Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 48),
                                  TVIconButton(
                                    icon: isVod ? Icons.forward_10_rounded : Icons.skip_next_rounded,
                                    size: 46,
                                    onPressed: () { isVod ? _engine.seekRelative(10) : _stepChannel(1); _resetOsdTimer(); },
                                  ),
                                ],
                              ),

                              const Spacer(),

                              // BARRA INFERIOR (LINHA DO TEMPO E MENU)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: isVod && isReady
                                          ? Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(_formatDuration(ctrl!.value.position), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                    Text(_formatDuration(ctrl.value.duration), style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                VideoProgressIndicator(ctrl, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: Color(0xFF00E5FF), bufferedColor: Colors.white24, backgroundColor: Colors.white10)),
                                              ],
                                            )
                                          : Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.circle, color: Colors.redAccent, size: 10),
                                                    const SizedBox(width: 6),
                                                    const Text('AO VIVO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                                    if (_engine.currentEpg != null) ...[
                                                      const SizedBox(width: 12),
                                                      Expanded(child: Text('• ${_engine.currentEpg!.nowTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white))),
                                                    ]
                                                  ],
                                                ),
                                              ],
                                            ),
                                    ),
                                    const SizedBox(width: 24),
                                    TVFocusableItem(
                                      onSelect: () { setState(() => showDrawer = true); _resetOsdTimer(); },
                                      builder: (c, f) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(color: f ? const Color(0xFF00E5FF) : Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2)),
                                        child: Row(
                                          children: [
                                            Icon(Icons.format_list_bulleted_rounded, size: 20, color: f ? Colors.black : Colors.white),
                                            const SizedBox(width: 8),
                                            Text(isVod ? 'Episódios' : 'Canais', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: f ? Colors.black : Colors.white)),
                                          ],
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
                    ),
                  ),

                  // CAMADA 4: MENU LATERAL (GAVETA)
                  _buildSideDrawer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
