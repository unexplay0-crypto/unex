import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'codec_support.dart';
import 'core.dart';

/// ============================================================================
/// MOTOR DE REPRODUÇÃO — REESCRITO (v1.2.0)
///
/// O que mudou em relação à versão que travava ao abrir canal/filme/série:
///
///  * TODA tentativa de conexão tem TEMPO LIMITE. Sem tela de carregamento
///    infinita: se o fluxo não abriu em poucos segundos, o player descarta
///    aquele controller e passa para o formato seguinte;
///  * cada conteúdo ganha uma lista ordenada de URLs candidatas (o mesmo
///    stream em .ts / .m3u8 / .mp4) e o formato que funcionou é MEMORIZADO por
///    painel — o próximo canal daquele servidor já entra pelo formato certo;
///  * token de GERAÇÃO elimina corridas: trocar de canal rapidamente não deixa
///    mais um fluxo antigo mandando no estado nem descarta (dispose) um
///    controller que a interface ainda está usando;
///  * travamento no meio da transmissão RECONECTA de verdade (reabre o fluxo,
///    preservando a posição em filmes/séries) em vez de só pausar e retomar;
///  * pausa automática quando o app vai para segundo plano e retomada ao
///    voltar, gravando o progresso do VOD na hora;
///  * erro com detalhe técnico curto (HTTP/latência) no rodapé da mensagem,
///    para diagnosticar direto no aparelho, sem precisar de log.
///
/// A API pública é a mesma da versão anterior, então o dashboard, o
/// mini-player, a TV e o celular continuam funcionando sem alteração.
/// ============================================================================
class SharedStreamEngine extends ChangeNotifier with WidgetsBindingObserver {
  static final SharedStreamEngine instance = SharedStreamEngine._internal();

  SharedStreamEngine._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  // ---------------------------------------------------------------------
  // Estado observável (API idêntica à versão anterior)
  // ---------------------------------------------------------------------
  VideoPlayerController? controller;
  StreamItem? currentItem;
  StreamItem? previousChannelItem; // último canal para troca rápida (Recall)
  EpgProgramInfo? currentEpg;

  bool isReady = false;
  bool hasError = false;
  bool isRecovering = false;
  bool usingHlsFallback = false;
  int activeVariantIndex = 0;

  /// Motivo da última falha (codec de áudio/vídeo, rede...) para a mensagem.
  PlaybackFailure lastFailure = PlaybackFailure.none;

  /// Aviso temporário enquanto o fallback automático tenta outro formato.
  String? codecNotice;

  /// Detalhe curto da última falha (ex.: "Servidor respondeu HTTP 403").
  String lastTechnicalDetail = '';

  String get failureMessage => CodecSupport.messageFor(lastFailure);

  String serverDns = '';
  String username = '';
  String password = '';
  double measuredSpeedMbps = 18.5;

  void Function(VodProgressEntry entry)? onVodProgressSaved;
  VoidCallback? onVodEpisodeEnded;

  // ---------------------------------------------------------------------
  // Configuração interna
  // ---------------------------------------------------------------------
  static const Duration _firstAttemptTimeout = Duration(seconds: 10);
  static const Duration _nextAttemptTimeout = Duration(seconds: 7);
  static const Duration _probeTimeout = Duration(seconds: 6);
  static const Duration _tickInterval = Duration(seconds: 2);
  static const int _maxReconnects = 3;

  /// Cabeçalhos entregues ao player: o MESMO User-Agent que já carrega a lista
  /// (vários painéis recusam requisição sem UA de player) e nenhum cabeçalho
  /// hop-by-hop (ex.: Connection), que alguns servidores rejeitam.
  static final Map<String, String> _playerHeaders = <String, String>{
    'User-Agent': kIptvHeaders['User-Agent'] ?? 'IPTVSmartersPlayer/1.0',
    'Accept': '*/*',
  };

  int _generation = 0;
  Timer? _watchdog;
  Duration _lastPosition = Duration.zero;
  int _stallTicks = 0;
  int _reconnects = 0;
  DateTime? _lastReconnectAt;
  int _vodSaveTick = 0;
  bool _episodeEndNotified = false;
  bool _pausedByLifecycle = false;
  String _lastRawError = '';

  /// Formato (extensão) que funcionou, por painel + tipo de conteúdo.
  final Map<String, String> _workingFormat = <String, String>{};

  void configureCredentials({
    required String dns,
    required String user,
    required String pass,
    required double speedMbps,
  }) {
    serverDns = dns;
    username = user;
    password = pass;
    measuredSpeedMbps = speedMbps;
  }

  // =====================================================================
  // ABERTURA DE FLUXO
  // =====================================================================
  Future<void> openStream(
    StreamItem item, {
    Duration? startPosition,
    bool forceReload = false,
    bool tryHlsFallback = false,
    int variantIndex = 0,
    bool isRetry = false,
  }) async {
    // Mesmo fluxo já pronto: só posiciona/retoma, sem reiniciar o buffer.
    if (!forceReload &&
        currentItem?.url == item.url &&
        controller != null &&
        isReady &&
        !hasError) {
      final ctrl = controller!;
      if (startPosition != null &&
          item.type != ContentType.live &&
          startPosition.inSeconds > 5) {
        await _safe(() => ctrl.seekTo(startPosition));
      }
      if (!ctrl.value.isPlaying) {
        await _safe(ctrl.play);
      }
      notifyListeners();
      return;
    }

    _saveCurrentVodProgressImmediately();

    // Registra o último canal ao vivo para o botão Recall
    if (currentItem != null &&
        currentItem!.id != item.id &&
        currentItem!.type == ContentType.live &&
        item.type == ContentType.live) {
      previousChannelItem = currentItem;
    }

    final candidates = _buildCandidates(item);
    var startIdx = variantIndex;
    if (tryHlsFallback && startIdx == 0 && candidates.length > 1) startIdx = 1;
    if (startIdx < 0 || startIdx >= candidates.length) startIdx = 0;

    final generation = ++_generation; // invalida qualquer tentativa anterior
    _watchdog?.cancel();

    currentItem = item;
    activeVariantIndex = startIdx;
    usingHlsFallback = startIdx > 0;
    isReady = false;
    hasError = false;

    if (!isRetry) {
      isRecovering = false;
      _reconnects = 0;
      _lastReconnectAt = null;
      _episodeEndNotified = false;
      _stallTicks = 0;
      _lastPosition = Duration.zero;
      _vodSaveTick = 0;
      _lastRawError = '';
      lastFailure = PlaybackFailure.none;
      codecNotice = null;
      lastTechnicalDetail = '';
      // Memoriza o último canal ao vivo: reabre sozinho no próximo boot
      if (item.type == ContentType.live) AppStorage.saveLastChannel(item);
    }
    notifyListeners();

    _loadEpg(item);

    await _runCandidates(candidates, startIdx, startPosition, generation);
  }

  /// Percorre os formatos candidatos até um abrir. Cada tentativa tem tempo
  /// limite e a que falha é descartada antes de passar para a próxima.
  Future<void> _runCandidates(
    List<String> candidates,
    int startIdx,
    Duration? startPosition,
    int generation,
  ) async {
    final item = currentItem;
    if (item == null) return;

    var lastError = _lastRawError;

    for (var i = startIdx; i < candidates.length; i++) {
      if (generation != _generation) return;

      if (i > startIdx) {
        usingHlsFallback = true;
        codecNotice = _noticeFor(lastError);
        notifyListeners();
      }

      final attemptTimeout =
          i == 0 ? _firstAttemptTimeout : _nextAttemptTimeout;

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(candidates[i]),
        httpHeaders: _playerHeaders,
      );
      final init = ctrl.initialize();
      // Se esta inicialização falhar DEPOIS de desistirmos dela, o erro é
      // engolido aqui e o controller descartado em _discard: nunca vira crash.
      init.catchError((Object _) {});

      var ok = false;
      try {
        await init.timeout(attemptTimeout);
        ok = true;
      } on TimeoutException {
        lastError = 'tempo esgotado ao abrir o fluxo';
        _lastRawError = lastError;
        lastTechnicalDetail = 'Sem resposta em ${attemptTimeout.inSeconds}s';
      } catch (e) {
        lastError = '${ctrl.value.errorDescription ?? ''} $e'.trim();
        _lastRawError = lastError;
        lastTechnicalDetail = _short('$e');
      }

      if (generation != _generation) {
        _retire(ctrl);
        return;
      }

      if (!ok) {
        _discard(init, ctrl);
        continue;
      }

      // ------------------------- SUCESSO -------------------------
      final old = controller;
      controller = ctrl;
      activeVariantIndex = i;
      usingHlsFallback = i > 0;

      final ext = _extOf(candidates[i]);
      if (ext.isNotEmpty) _workingFormat[_formatKey(item)] = ext;

      isReady = true;
      hasError = false;
      isRecovering = false;
      lastFailure = PlaybackFailure.none;
      codecNotice = null;
      lastTechnicalDetail = '';
      _lastRawError = '';
      _stallTicks = 0;
      _lastPosition = Duration.zero;
      notifyListeners();
      _retire(old);

      if (item.type != ContentType.live &&
          startPosition != null &&
          startPosition.inSeconds > 5) {
        await _safe(() => ctrl.seekTo(startPosition));
      }
      await _safe(ctrl.play);
      _startWatchdog();
      notifyListeners();
      return;
    }

    if (generation != _generation) return;

    // ------------------ ESGOTOU TODAS AS TENTATIVAS ------------------
    _watchdog?.cancel();
    codecNotice = null;
    isReady = false;
    isRecovering = false;
    hasError = true;
    lastFailure = CodecSupport.classify(lastError);
    notifyListeners();
    unawaited(_probeServer(item));
  }

  /// Sonda HTTP independente do player: mostra se o SERVIDOR respondeu.
  /// HTTP 200 com o player falhando aponta formato/decoder; sem resposta aponta
  /// rede, porta ou servidor fora do ar.
  Future<void> _probeServer(StreamItem item) async {
    final generation = _generation;
    String detail;
    try {
      final res = await http
          .head(Uri.parse(item.url), headers: _playerHeaders)
          .timeout(_probeTimeout);
      final type = res.headers['content-type'];
      detail = 'Servidor respondeu HTTP ${res.statusCode}'
          '${type == null ? '' : ' ($type)'}';
    } catch (e) {
      detail = 'Servidor não respondeu (${_short('$e')})';
    }
    if (generation != _generation || !hasError) return;
    lastTechnicalDetail = detail;
    notifyListeners();
  }

  Future<void> _loadEpg(StreamItem item) async {
    try {
      final epg = await EpgService.fetchEpgForChannel(
        item: item,
        serverDns: serverDns,
        username: username,
        password: password,
      );
      if (currentItem?.id != item.id) return;
      currentEpg = epg;
      notifyListeners();
    } catch (_) {
      // EPG é informação secundária: nunca derruba a reprodução.
    }
  }

  // =====================================================================
  // URLs CANDIDATAS (o mesmo conteúdo em outro contêiner)
  // =====================================================================
  List<String> _buildCandidates(StreamItem item) {
    final out = <String>[];
    void add(String u) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    final url = item.url.trim();
    add(url);
    if (url.isEmpty) return out;

    final qIdx = url.indexOf('?');
    final path = qIdx == -1 ? url : url.substring(0, qIdx);
    final query = qIdx == -1 ? '' : url.substring(qIdx);
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    final hasExt = dot > slash;
    final base = hasExt ? path.substring(0, dot) : path;
    final ext = hasExt ? path.substring(dot + 1).toLowerCase() : '';

    if (item.type == ContentType.live) {
      final order = ext == 'ts'
          ? <String>['m3u8']
          : ext == 'm3u8'
              ? <String>['ts']
              : <String>['ts', 'm3u8'];
      for (final e in order) {
        add('$base.$e$query');
      }
    } else {
      if (ext != 'm3u8') add('$base.m3u8$query');
      if (ext != 'mp4') add('$base.mp4$query');
    }

    // Otimização: se já sabemos qual formato abre neste painel, ele sobe para a
    // segunda posição (a URL original segue sendo a primeira tentativa).
    final preferred = _workingFormat[_formatKey(item)];
    if (preferred != null && preferred.isNotEmpty) {
      final idx = out.indexWhere((u) => _extOf(u) == preferred);
      if (idx > 1) {
        final u = out.removeAt(idx);
        out.insert(1, u);
      }
    }
    return out;
  }

  static String _extOf(String url) {
    final q = url.indexOf('?');
    final path = q == -1 ? url : url.substring(0, q);
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot <= path.lastIndexOf('/')) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  String _formatKey(StreamItem item) {
    var host = '';
    try {
      final uri = Uri.parse(item.url);
      host = '${uri.host}:${uri.port}';
    } catch (_) {}
    return '${item.type.index}|$host';
  }

  String? _noticeFor(String rawError) {
    switch (CodecSupport.classify(rawError)) {
      case PlaybackFailure.audioCodec:
        return 'Áudio não suportado pelo aparelho — tentando formato alternativo...';
      case PlaybackFailure.videoCodec:
        return 'Vídeo não suportado — tentando formato alternativo...';
      default:
        return 'Tentando formato alternativo para este canal...';
    }
  }

  // =====================================================================
  // VIGIA DA TRANSMISSÃO (travamento / erro tardio / fim do episódio)
  // =====================================================================
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(_tickInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (!isReady) return;
    final ctrl = controller;
    final item = currentItem;
    if (ctrl == null || item == null) return;
    if (!ctrl.value.isInitialized) return;

    final val = ctrl.value;

    // Erro que só apareceu depois do início (ex.: decoder de áudio falhou)
    if (val.hasError) {
      await _reconnect(_short(val.errorDescription ?? 'erro de decodificação'));
      return;
    }

    // Fim do episódio em Séries → Próximo Episódio Automático (1x por item)
    if (item.type == ContentType.series &&
        val.duration.inSeconds > 60 &&
        val.position.inSeconds >= val.duration.inSeconds - 2) {
      if (!_episodeEndNotified) {
        _episodeEndNotified = true;
        _saveCurrentVodProgressImmediately();
        onVodEpisodeEnded?.call();
      }
      return;
    }

    if (item.type != ContentType.live) {
      _vodSaveTick++;
      if (_vodSaveTick >= 3) {
        _vodSaveTick = 0;
        _saveCurrentVodProgressImmediately();
      }
    }

    // Sem avanço de posição em duas leituras seguidas = transmissão travada
    if (val.isPlaying && val.position == _lastPosition) {
      _stallTicks++;
      if (_stallTicks >= 2) {
        _stallTicks = 0;
        await _reconnect('transmissão travada');
        return;
      }
    } else {
      _stallTicks = 0;
    }
    _lastPosition = val.position;
  }

  /// Reabre o fluxo preservando a posição (VOD) e limitando as reconexões
  /// seguidas, para não entrar em laço infinito.
  Future<void> _reconnect(String reason) async {
    if (isRecovering || hasError) return;
    final item = currentItem;
    final ctrl = controller;
    if (item == null || ctrl == null) return;

    final now = DateTime.now();
    if (_lastReconnectAt != null &&
        now.difference(_lastReconnectAt!).inSeconds < 5) {
      return;
    }
    _lastReconnectAt = now;

    if (_reconnects >= _maxReconnects) {
      _watchdog?.cancel();
      isReady = false;
      isRecovering = false;
      hasError = true;
      lastFailure = PlaybackFailure.network;
      lastTechnicalDetail = 'A transmissão parou de responder ($reason).';
      notifyListeners();
      return;
    }
    _reconnects++;

    isRecovering = true;
    notifyListeners();

    final pos = item.type == ContentType.live ? null : ctrl.value.position;
    _watchdog?.cancel();
    await openStream(
      item,
      startPosition: pos,
      forceReload: true,
      variantIndex: activeVariantIndex,
      isRetry: true,
    );
    if (!hasError) {
      isRecovering = false;
      notifyListeners();
    }
  }

  // =====================================================================
  // CICLO DE VIDA / UTILITÁRIOS
  // =====================================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = controller;
    if (ctrl == null || !isReady) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedByLifecycle = ctrl.value.isPlaying;
      if (_pausedByLifecycle) {
        unawaited(_safe(ctrl.pause));
        _saveCurrentVodProgressImmediately();
      }
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      unawaited(_safe(ctrl.play));
    }
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Controller descartado por uma troca de fluxo: apenas ignorar.
    }
  }

  /// Descarta um controller que nunca chegou a entrar em uso.
  void _discard(Future<void> settled, VideoPlayerController ctrl) {
    final done = settled.then<void>((_) {}, onError: (Object _) {});
    unawaited(done.whenComplete(() => _disposeSafely(ctrl)));
  }

  /// Descarta o controller antigo DEPOIS que a interface já trocou para o novo
  /// (dispose imediato dispara "used after being disposed" em frame pendente).
  void _retire(VideoPlayerController? old) {
    if (old == null) return;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!identical(old, controller)) _disposeSafely(old);
    }));
  }

  Future<void> _disposeSafely(VideoPlayerController ctrl) async {
    try {
      await ctrl.dispose();
    } catch (_) {}
  }

  static String _short(String raw) {
    var s = raw.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    if (s.startsWith('Exception: ')) s = s.substring(11);
    if (s.length > 110) s = '${s.substring(0, 110)}...';
    return s;
  }

  void _saveCurrentVodProgressImmediately() {
    final ctrl = controller;
    final item = currentItem;
    if (ctrl == null || item == null || !isReady) return;
    if (item.type == ContentType.live) return;

    final posSec = ctrl.value.position.inSeconds;
    final durSec = ctrl.value.duration.inSeconds;
    if (posSec >= 10 && durSec > 30) {
      final entry = VodProgressEntry(
        item: item,
        positionSeconds: posSec,
        durationSeconds: durSec,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      AppStorage.saveVodProgressEntry(entry);
      onVodProgressSaved?.call(entry);
    }
  }

  /// Pausa apenas o áudio/vídeo em segundo plano sem destruir o buffer quando
  /// vai ao catálogo de séries.
  void pausePreviewSilently() {
    final ctrl = controller;
    if (ctrl != null && isReady && ctrl.value.isPlaying) {
      unawaited(_safe(ctrl.pause));
      notifyListeners();
    }
  }

  void resumePreviewSilently() {
    final ctrl = controller;
    if (ctrl != null && isReady && !ctrl.value.isPlaying) {
      unawaited(_safe(ctrl.play));
      notifyListeners();
    }
  }

  void togglePlayPause() {
    final ctrl = controller;
    if (ctrl == null || !isReady) return;
    if (ctrl.value.isPlaying) {
      unawaited(_safe(ctrl.pause));
      _saveCurrentVodProgressImmediately();
    } else {
      unawaited(_safe(ctrl.play));
      _reconnects = 0;
    }
    notifyListeners();
  }

  Future<void> seekRelative(int seconds) async {
    final ctrl = controller;
    if (ctrl == null || !isReady) return;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    final target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) {
      await _safe(() => ctrl.seekTo(Duration.zero));
    } else if (dur > Duration.zero && target > dur) {
      await _safe(() => ctrl.seekTo(dur));
    } else {
      await _safe(() => ctrl.seekTo(target));
    }
    _saveCurrentVodProgressImmediately();
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    _saveCurrentVodProgressImmediately();
    _watchdog?.cancel();
    _generation++;
    final old = controller;
    controller = null;
    currentItem = null;
    previousChannelItem = null;
    currentEpg = null;
    isReady = false;
    hasError = false;
    isRecovering = false;
    codecNotice = null;
    lastTechnicalDetail = '';
    _pausedByLifecycle = false;
    notifyListeners();
    if (old != null) await _disposeSafely(old);
  }
}
