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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentItem = widget.initialItem;

    _engine.openStream(currentItem, startPosition: widget.initialStartPosition);
    _resetOsdTimer();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.deviceMode == DeviceMode.tv) {
        _playPauseNode.requestFocus();
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

  void _switchStream(StreamItem item) {
    setState(() { currentItem = item; showOsd = true; showDrawer = false; });
    _engine.openStream(item);
    _resetOsdTimer();
    if (widget.deviceMode == DeviceMode.tv) _playPauseNode.requestFocus();
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
      if (widget.deviceMode == DeviceMode.tv) _playPauseNode.requestFocus();
    }
  }

  // ===========================================================================
  // GAVETA DE CANAIS / EPISÓDIOS (MENU LATERAL)
  // ===========================================================================
  Widget _buildSideDrawer() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      top: 0, bottom: 0,
      right: showDrawer ? 0 : -320,
      width: 300,
      child: Container(
        color: const Color(0xFF0A0C12).withOpacity(0.95),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(currentItem.type == ContentType.live ? 'Canais' : 'Lista', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF), fontSize: 16)),
                  TVIconButton(icon: Icons.close_rounded, onPressed: () => setState(() => showDrawer = false)),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        color: isPlaying ? const Color(0xFF00E5FF).withOpacity(0.15) : isFocused ? Colors.white10 : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        leading: buildChannelLogo(item.logo, size: 36),
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal, color: isPlaying ? const Color(0xFF00E5FF) : Colors.white)),
                        trailing: isPlaying ? const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF), size: 20) : null,
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

  // ===========================================================================
  // INTERFACE PRINCIPAL DO PLAYER (ESTILO NETFLIX)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final ctrl = _engine.controller;
        final isReady = _engine.isReady && ctrl != null;
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
                    child: Center(
                      child: _engine.hasError
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
                              const SizedBox(height: 10),
                              const Text('Sinal Indisponível', style: TextStyle(color: Colors.white70)),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Tentar Novamente', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () => _engine.openStream(currentItem, forceReload: true, tryHlsFallback: true),
                              )
                            ],
                          )
                        : isReady ? AspectRatio(aspectRatio: ctrl.value.aspectRatio, child: VideoPlayer(ctrl)) : const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                    ),
                  ),

                  // CAMADA 2: OSD (CONTROLES ESTILO NETFLIX)
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
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    TVIconButton(icon: Icons.arrow_back_ios_new_rounded, size: 24, onPressed: () => Navigator.pop(context)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(currentItem.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
                                    size: 42,
                                    onPressed: () { isVod ? _engine.seekRelative(-10) : _stepChannel(-1); _resetOsdTimer(); },
                                  ),
                                  const SizedBox(width: 40),
                                  TVFocusableItem(
                                    focusNode: _playPauseNode,
                                    autofocus: true,
                                    onSelect: () { _engine.togglePlayPause(); _resetOsdTimer(); },
                                    builder: (c, f) => AnimatedScale(
                                      scale: f ? 1.1 : 1.0,
                                      duration: const Duration(milliseconds: 150),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(color: f ? const Color(0xFF00E5FF) : Colors.black54, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF00E5FF), width: 2)),
                                        child: Icon(isReady && ctrl!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 54, color: f ? Colors.black : Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 40),
                                  TVIconButton(
                                    icon: isVod ? Icons.forward_10_rounded : Icons.skip_next_rounded,
                                    size: 42,
                                    onPressed: () { isVod ? _engine.seekRelative(10) : _stepChannel(1); _resetOsdTimer(); },
                                  ),
                                ],
                              ),

                              const Spacer(),

                              // BARRA INFERIOR (LINHA DO TEMPO)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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
                                                const SizedBox(height: 6),
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
                                                    const Text('AO VIVO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                                    if (_engine.currentEpg != null) ...[
                                                      const SizedBox(width: 12),
                                                      Expanded(child: Text('• ${_engine.currentEpg!.nowTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white70))),
                                                    ]
                                                  ],
                                                ),
                                              ],
                                            ),
                                    ),
                                    const SizedBox(width: 20),
                                    TVFocusableItem(
                                      onSelect: () { setState(() => showDrawer = true); _resetOsdTimer(); },
                                      builder: (c, f) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(color: f ? const Color(0xFF00E5FF) : Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: f ? Colors.white : Colors.transparent)),
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

                  // CAMADA 3: MENU LATERAL (GAVETA DE CANAIS)
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
