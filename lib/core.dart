import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

const Map<String, String> kIptvHeaders = {
  'User-Agent': 'IPTVSmartersPlayer',
  'Accept': '*/*',
};

const MethodChannel nativeChannel = MethodChannel('unex.vision/native');

enum DeviceMode { mobile, tv }
enum ContentType { live, movie, series }
enum MainSection { live, movie, series, continueWatching, favorites, recents }

class StreamItem {
  final String id;
  final String streamId;
  final String tvgId;
  final String name;
  final String cleanName;
  final String seriesName;
  final int seasonNumber;
  final int episodeNumber;
  final String qualityTag;
  final String group;
  final String logo;
  final String url;
  final ContentType type;
  final bool isAdult;
  final String synopsis;
  final String rating;
  final String year;
  final String cast;

  StreamItem({
    required this.id,
    required this.streamId,
    required this.tvgId,
    required this.name,
    required this.cleanName,
    required this.seriesName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.qualityTag,
    required this.group,
    required this.logo,
    required this.url,
    required this.type,
    required this.isAdult,
    this.synopsis = 'Nenhuma sinopse disponível.',
    this.rating = 'N/A',
    this.year = '',
    this.cast = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'streamId': streamId,
        'tvgId': tvgId,
        'name': name,
        'cleanName': cleanName,
        'seriesName': seriesName,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'qualityTag': qualityTag,
        'group': group,
        'logo': logo,
        'url': url,
        'type': type.index,
        'isAdult': isAdult,
        'synopsis': synopsis,
        'rating': rating,
        'year': year,
        'cast': cast,
      };

  factory StreamItem.fromJson(Map<String, dynamic> json) {
    return StreamItem(
      id: json['id']?.toString() ?? '',
      streamId: json['streamId']?.toString() ?? '',
      tvgId: json['tvgId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Conteúdo',
      cleanName: json['cleanName']?.toString() ?? '',
      seriesName: json['seriesName']?.toString() ?? '',
      seasonNumber: (json['seasonNumber'] as int?) ?? 1,
      episodeNumber: (json['episodeNumber'] as int?) ?? 1,
      qualityTag: json['qualityTag']?.toString() ?? 'HD',
      group: json['group']?.toString() ?? 'Geral',
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: ContentType.values[(json['type'] as int?)?.clamp(0, 2) ?? 0],
      isAdult: json['isAdult'] == true,
      synopsis: json['synopsis']?.toString() ?? 'Nenhuma sinopse disponível.',
      rating: json['rating']?.toString() ?? 'N/A',
      year: json['year']?.toString() ?? '',
      cast: json['cast']?.toString() ?? '',
    );
  }
}

class VodProgressEntry {
  final StreamItem item;
  final int positionSeconds;
  final int durationSeconds;
  final int updatedAtMs;

  VodProgressEntry({
    required this.item,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAtMs,
  });

  double get progress =>
      durationSeconds > 0 ? (positionSeconds / durationSeconds).clamp(0.0, 1.0) : 0.0;

  String get formattedRemaining {
    final rem = (durationSeconds - positionSeconds).clamp(0, 86400);
    return 'Faltam ${(rem / 60).ceil()} min';
  }

  String get formattedPosition {
    final m = (positionSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (positionSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'updatedAtMs': updatedAtMs,
      };

  factory VodProgressEntry.fromJson(Map<String, dynamic> json) => VodProgressEntry(
        item: StreamItem.fromJson((json['item'] as Map?)?.cast<String, dynamic>() ?? {}),
        positionSeconds: (json['positionSeconds'] as int?) ?? 0,
        durationSeconds: (json['durationSeconds'] as int?) ?? 1,
        updatedAtMs: (json['updatedAtMs'] as int?) ?? 0,
      );
}

class EpgProgramInfo {
  final String nowTitle;
  final String nextTitle;
  final double progress;
  const EpgProgramInfo({
    required this.nowTitle,
    required this.nextTitle,
    this.progress = 0.45,
  });
}

class SeriesGroup {
  final String id;
  final String seriesId;
  final String title;
  final String group;
  final String logo;
  final String synopsis;
  final String qualityTag;
  final bool isAdult;
  final Map<int, List<StreamItem>> seasons;

  SeriesGroup({
    required this.id,
    this.seriesId = '',
    required this.title,
    required this.group,
    required this.logo,
    this.synopsis = 'Selecione para explorar as temporadas e episódios desta série.',
    required this.qualityTag,
    required this.isAdult,
    required this.seasons,
  });

  int get totalSeasons => seasons.isEmpty ? 1 : seasons.length;
  int get totalEpisodes => seasons.values.fold(0, (sum, list) => sum + list.length);
  List<StreamItem> get allEpisodesFlat {
    final sortedKeys = seasons.keys.toList()..sort();
    return sortedKeys.expand((k) => seasons[k]!).toList();
  }
}

// =============================================================================
// ARMAZENAMENTO OFFLINE-FIRST E PERSISTÊNCIA NO DISCO
// =============================================================================
class AppStorage {
  static String get _tmp => Directory.systemTemp.path;
  static File get _sessionFile => File('$_tmp/unex_verified_session_v10.json');
  static File get _deviceFile => File('$_tmp/unex_device_mode_v10.json');
  static File get _vodProgressFile => File('$_tmp/unex_vod_progress_v10.json');
  static File get _favoritesFile => File('$_tmp/unex_favorites_v10.json');
  static File get _recentsFile => File('$_tmp/unex_recents_v10.json');
  static File get _offlinePlaylistFile => File('$_tmp/unex_offline_playlist_v10.json');
  static File get _parentalPinFile => File('$_tmp/unex_parental_pin_v10.txt');

  static Future<DeviceMode> getOrDetectDeviceMode() async {
    try {
      if (await _deviceFile.exists()) {
        final data = jsonDecode(await _deviceFile.readAsString());
        if (data['mode'] == 'tv') return DeviceMode.tv;
        if (data['mode'] == 'mobile') return DeviceMode.mobile;
      }
      final bool isTV = await nativeChannel.invokeMethod('isAndroidTV') ?? false;
      return isTV ? DeviceMode.tv : DeviceMode.mobile;
    } catch (_) {
      return DeviceMode.tv;
    }
  }

  static Future<void> saveDeviceMode(DeviceMode mode) async {
    try {
      await _deviceFile.writeAsString(jsonEncode({'mode': mode == DeviceMode.tv ? 'tv' : 'mobile'}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadVerifiedSession() async {
    try {
      if (await _sessionFile.exists()) return jsonDecode(await _sessionFile.readAsString());
    } catch (_) {}
    return null;
  }

  static Future<void> saveVerifiedSession(Map<String, dynamic> data) async {
    try {
      data['verified'] = true;
      await _sessionFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> clearAllData() async {
    try {
      for (var f in [
        _sessionFile,
        _vodProgressFile,
        _favoritesFile,
        _recentsFile,
        _offlinePlaylistFile
      ]) {
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  static Future<String> loadParentalPin() async {
    try {
      if (await _parentalPinFile.exists()) return (await _parentalPinFile.readAsString()).trim();
    } catch (_) {}
    return '0000';
  }

  static Future<void> saveParentalPin(String pin) async {
    try {
      await _parentalPinFile.writeAsString(pin.trim());
    } catch (_) {}
  }

  static Future<List<StreamItem>> loadOfflinePlaylist() async {
    try {
      if (await _offlinePlaylistFile.exists()) {
        final raw = await _offlinePlaylistFile.readAsString();
        final list = await compute(_decodePlaylistIsolate, raw);
        return list;
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveOfflinePlaylist(List<StreamItem> items) async {
    try {
      // Limita o cache local em 18.000 itens e serializa em background para nunca travar a TV
      final capped = items.length > 18000 ? items.sublist(0, 18000) : items;
      final encoded = await compute(_encodePlaylistIsolate, capped);
      await _offlinePlaylistFile.writeAsString(encoded);
    } catch (_) {}
  }

  static Future<Set<String>> loadFavorites() async {
    try {
      if (await _favoritesFile.exists()) {
        final list = jsonDecode(await _favoritesFile.readAsString()) as List;
        return list.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveFavorites(Set<String> favs) async {
    try {
      await _favoritesFile.writeAsString(jsonEncode(favs.toList()));
    } catch (_) {}
  }

  static Future<List<StreamItem>> loadRecents() async {
    try {
      if (await _recentsFile.exists()) {
        final list = jsonDecode(await _recentsFile.readAsString()) as List;
        return list.map((e) => StreamItem.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveRecents(List<StreamItem> recents) async {
    try {
      await _recentsFile.writeAsString(
          jsonEncode(recents.take(40).map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<Map<String, VodProgressEntry>> loadVodProgressMap() async {
    try {
      if (await _vodProgressFile.exists()) {
        final raw = jsonDecode(await _vodProgressFile.readAsString()) as Map<String, dynamic>;
        return raw.map((k, v) => MapEntry(k, VodProgressEntry.fromJson(v.cast<String, dynamic>())));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveVodProgressEntry(VodProgressEntry entry) async {
    try {
      final map = await loadVodProgressMap();
      if (entry.progress >= 0.96) {
        map.remove(entry.item.id);
      } else {
        map[entry.item.id] = entry;
      }
      await _vodProgressFile
          .writeAsString(jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {}
  }
}

String _encodePlaylistIsolate(List<StreamItem> items) =>
    jsonEncode(items.map((e) => e.toJson()).toList());

List<StreamItem> _decodePlaylistIsolate(String raw) =>
    (jsonDecode(raw) as List).map((e) => StreamItem.fromJson(e)).toList();

// =============================================================================
// MOTOR DE VÍDEO COMPARTILHADO (COM TRAVA _opId E RESOLUÇÃO DE REDIRECIONAMENTO 302)
// =============================================================================
class SharedStreamEngine extends ChangeNotifier {
  static final SharedStreamEngine instance = SharedStreamEngine._internal();
  SharedStreamEngine._internal();

  VideoPlayerController? controller;
  StreamItem? currentItem;
  EpgProgramInfo? currentEpg;

  bool isReady = false;
  bool hasError = false;
  bool isRecovering = false;

  int _opId = 0; // Trava de operação sequencial: impede que trocas rápidas congelem o player na TV
  Timer? _watchdogTimer;
  Duration _lastPosition = Duration.zero;
  int _stallCounter = 0;

  void Function(VodProgressEntry entry)? onVodProgressSaved;

  /// Resolve redirecionamentos HTTP 301/302 (muito comuns em servidores IPTV)
  Future<String> _resolveRedirectUrl(String rawUrl) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      client.userAgent = kIptvHeaders['User-Agent'];
      Uri currentUri = Uri.parse(rawUrl);

      for (int hop = 0; hop < 3; hop++) {
        final req = await client.getUrl(currentUri).timeout(const Duration(seconds: 4));
        req.followRedirects = false;
        final res = await req.close().timeout(const Duration(seconds: 4));
        if (res.isRedirect ||
            res.statusCode == 301 ||
            res.statusCode == 302 ||
            res.statusCode == 307 ||
            res.statusCode == 308) {
          final loc = res.headers.value(HttpHeaders.locationHeader);
          await res.drain().catchError((_) {});
          if (loc != null && loc.isNotEmpty) {
            currentUri = currentUri.resolve(loc);
            continue;
          }
        }
        break;
      }
      return currentUri.toString();
    } catch (_) {
      return rawUrl;
    } finally {
      client?.close(force: true);
    }
  }

  List<String> _buildCandidateUrls(StreamItem item) {
    final original = item.url.trim();
    final List<String> candidates = [];

    if (item.type == ContentType.live) {
      // Na Android TV, o ExoPlayer tem compatibilidade muito superior com HLS (.m3u8) ou stream direto
      if (original.endsWith('.ts')) {
        final hlsUrl = '${original.substring(0, original.length - 3)}.m3u8';
        candidates.add(original);
        candidates.add(hlsUrl);
      } else if (original.endsWith('.m3u8')) {
        final tsUrl = '${original.substring(0, original.length - 5)}.ts';
        candidates.add(original);
        candidates.add(tsUrl);
      } else {
        candidates.add(original);
        candidates.add('$original.ts');
        candidates.add('$original.m3u8');
      }
    } else {
      candidates.add(original);
    }
    return candidates;
  }

  Future<void> openStream(
    StreamItem item, {
    Duration? startPosition,
    bool forceReload = false,
    bool tryHlsFallback = false,
  }) async {
    if (!forceReload &&
        currentItem?.id == item.id &&
        controller != null &&
        isReady &&
        !hasError) {
      if (startPosition != null && item.type != ContentType.live) {
        await controller!.seekTo(startPosition);
      }
      if (!controller!.value.isPlaying) {
        await controller!.play();
      }
      notifyListeners();
      return;
    }

    final int myOp = ++_opId;

    _saveCurrentVodProgressImmediately();
    currentItem = item;
    isReady = false;
    hasError = false;
    isRecovering = false;

    final oldController = controller;
    controller = null;
    notifyListeners();

    _fetchMockEpg(item);

    // Destrói completamente o decoder anterior antes de alocar um novo na TV
    if (oldController != null) {
      try {
        await oldController.pause();
      } catch (_) {}
      try {
        await oldController.dispose();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 180));
    }

    // Se o usuário mudou de canal enquanto o decoder antigo fechava, aborta com segurança!
    if (myOp != _opId) return;

    final candidates = _buildCandidateUrls(item);
    if (tryHlsFallback && candidates.length > 1) {
      final first = candidates.removeAt(0);
      candidates.add(first);
    }

    for (final candidate in candidates) {
      if (myOp != _opId) return;

      final resolvedUrl = await _resolveRedirectUrl(candidate);
      if (myOp != _opId) return;

      final isHls = resolvedUrl.toLowerCase().contains('.m3u8');
      final testCtrl = VideoPlayerController.networkUrl(
        Uri.parse(resolvedUrl),
        httpHeaders: kIptvHeaders,
        formatHint: isHls ? VideoFormat.hls : null,
      );

      try {
        await testCtrl.initialize().timeout(const Duration(seconds: 9));
        if (myOp != _opId) {
          await testCtrl.dispose().catchError((_) {});
          return;
        }

        controller = testCtrl;
        if (item.type != ContentType.live &&
            startPosition != null &&
            startPosition.inSeconds > 5) {
          await testCtrl.seekTo(startPosition);
        }

        isReady = true;
        hasError = false;
        isRecovering = false;
        await testCtrl.play();
        _startWatchdog();
        notifyListeners();
        return; // Sucesso!
      } catch (_) {
        await testCtrl.dispose().catchError((_) {});
      }
    }

    if (myOp == _opId) {
      hasError = true;
      isReady = false;
      notifyListeners();
    }
  }

  void _fetchMockEpg(StreamItem item) {
    if (item.type != ContentType.live) return;
    final now = DateTime.now();
    final nextHourStr = '${((now.hour + 1) % 24).toString().padLeft(2, '0')}:00';
    currentEpg = EpgProgramInfo(
      nowTitle: '${item.cleanName} • Ao Vivo',
      nextTitle: 'A Seguir ($nextHourStr)',
      progress: (now.minute / 60.0).clamp(0.05, 0.95),
    );
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _stallCounter = 0;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final ctrl = controller;
      final item = currentItem;
      if (ctrl == null || item == null || !isReady || !ctrl.value.isPlaying) return;

      if (item.type != ContentType.live && timer.tick % 3 == 0) {
        _saveCurrentVodProgressImmediately();
      }

      if (ctrl.value.position == _lastPosition && ctrl.value.isBuffering) {
        _stallCounter++;
        if (_stallCounter >= 3 && !isRecovering) {
          isRecovering = true;
          notifyListeners();
          if (item.type == ContentType.live && ctrl.value.buffered.isNotEmpty) {
            final liveEdge = ctrl.value.buffered.last.end;
            if (liveEdge > ctrl.value.position + const Duration(seconds: 2)) {
              await ctrl.seekTo(liveEdge);
            }
            await ctrl.play();
          } else {
            await ctrl.pause();
            await Future.delayed(const Duration(milliseconds: 600));
            await ctrl.play();
          }
          isRecovering = false;
          _stallCounter = 0;
          notifyListeners();
        }
      } else {
        _stallCounter = 0;
      }
      _lastPosition = ctrl.value.position;
    });
  }

  void _saveCurrentVodProgressImmediately() {
    final ctrl = controller;
    final item = currentItem;
    if (ctrl == null || item == null || !isReady || item.type == ContentType.live) return;
    final pos = ctrl.value.position.inSeconds;
    final dur = ctrl.value.duration.inSeconds;
    if (pos >= 10 && dur > 30) {
      final entry = VodProgressEntry(
        item: item,
        positionSeconds: pos,
        durationSeconds: dur,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      AppStorage.saveVodProgressEntry(entry);
      onVodProgressSaved?.call(entry);
    }
  }

  void togglePlayPause() {
    if (controller == null || !isReady) return;
    if (controller!.value.isPlaying) {
      controller!.pause();
      _saveCurrentVodProgressImmediately();
    } else {
      controller!.play();
    }
    notifyListeners();
  }

  Future<void> seekRelative(int seconds) async {
    if (controller == null || !isReady) return;
    final target = controller!.value.position + Duration(seconds: seconds);

    Duration finalTarget = target;
    if (finalTarget < Duration.zero) {
      finalTarget = Duration.zero;
    } else if (finalTarget > controller!.value.duration) {
      finalTarget = controller!.value.duration;
    }

    await controller!.seekTo(finalTarget);
    _saveCurrentVodProgressImmediately();
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    _opId++;
    _saveCurrentVodProgressImmediately();
    _watchdogTimer?.cancel();
    final old = controller;
    controller = null;
    currentItem = null;
    isReady = false;
    hasError = false;
    notifyListeners();
    if (old != null) {
      await old.pause().catchError((_) {});
      await old.dispose().catchError((_) {});
    }
  }
}

// =============================================================================
// CARREGADOR ULTRA-RÁPIDO XTREAM CODES API + PARSER M3U FALLBACK
// =============================================================================
class CatalogBundle {
  final List<StreamItem> allItems;
  final List<SeriesGroup> seriesGroups;
  CatalogBundle({required this.allItems, required this.seriesGroups});
}

class XtreamCatalogService {
  static String cleanInputUrl(String raw) {
    String s = raw.replaceAll(RegExp(r'\s+'), '').trim();
    while (s.toLowerCase().startsWith('http://http://')) {
      s = s.substring(7);
    }
    while (s.toLowerCase().startsWith('https://https://')) {
      s = s.substring(8);
    }
    if (!s.toLowerCase().startsWith('http://') && !s.toLowerCase().startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/') || s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static Map<String, String>? extractXtreamCredentials({
    required String serverDns,
    required String username,
    required String password,
    String? directM3uUrl,
  }) {
    if (serverDns.trim().isNotEmpty &&
        username.trim().isNotEmpty &&
        password.trim().isNotEmpty) {
      return {
        'dns': cleanInputUrl(serverDns),
        'user': username.trim(),
        'pass': password.trim(),
      };
    }
    if (directM3uUrl != null && directM3uUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(cleanInputUrl(directM3uUrl));
        final u = uri.queryParameters['username'] ?? '';
        final p = uri.queryParameters['password'] ?? '';
        if (u.isNotEmpty && p.isNotEmpty) {
          final portPart = uri.hasPort ? ':${uri.port}' : '';
          return {
            'dns': '${uri.scheme}://${uri.host}$portPart',
            'user': u,
            'pass': p,
          };
        }
      } catch (_) {}
    }
    return null;
  }

  /// Carrega Canais, Filmes e Séries em poucos segundos via API JSON (como Vertu Play / TiviMate)
  static Future<CatalogBundle?> fetchViaXtreamApi({
    required String dns,
    required String user,
    required String pass,
  }) async {
    try {
      final baseApi = '$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';

      // 1. Busca categorias e canais ao vivo
      final liveCatFuture = http.get(Uri.parse('$baseApi&action=get_live_categories'), headers: kIptvHeaders).timeout(const Duration(seconds: 12));
      final liveStreamsFuture = http.get(Uri.parse('$baseApi&action=get_live_streams'), headers: kIptvHeaders).timeout(const Duration(seconds: 18));

      final liveCatRes = await liveCatFuture;
      final liveStreamsRes = await liveStreamsFuture;

      if (liveStreamsRes.statusCode != 200) return null;

      // 2. Busca filmes e séries (tolerante a falhas parciais)
      final vodCatFuture = http.get(Uri.parse('$baseApi&action=get_vod_categories'), headers: kIptvHeaders).timeout(const Duration(seconds: 12)).catchError((_) => http.Response('[]', 200));
      final vodStreamsFuture = http.get(Uri.parse('$baseApi&action=get_vod_streams'), headers: kIptvHeaders).timeout(const Duration(seconds: 18)).catchError((_) => http.Response('[]', 200));
      final seriesCatFuture = http.get(Uri.parse('$baseApi&action=get_series_categories'), headers: kIptvHeaders).timeout(const Duration(seconds: 12)).catchError((_) => http.Response('[]', 200));
      final seriesListFuture = http.get(Uri.parse('$baseApi&action=get_series'), headers: kIptvHeaders).timeout(const Duration(seconds: 18)).catchError((_) => http.Response('[]', 200));

      final results = await Future.wait([vodCatFuture, vodStreamsFuture, seriesCatFuture, seriesListFuture]);

      return await compute(_parseXtreamJsonIsolate, {
        'dns': dns,
        'user': user,
        'pass': pass,
        'liveCats': utf8.decode(liveCatRes.bodyBytes, allowMalformed: true),
        'liveStreams': utf8.decode(liveStreamsRes.bodyBytes, allowMalformed: true),
        'vodCats': utf8.decode(results[0].bodyBytes, allowMalformed: true),
        'vodStreams': utf8.decode(results[1].bodyBytes, allowMalformed: true),
        'seriesCats': utf8.decode(results[2].bodyBytes, allowMalformed: true),
        'seriesList': utf8.decode(results[3].bodyBytes, allowMalformed: true),
      });
    } catch (_) {
      return null;
    }
  }

  /// Carrega os episódios de uma Série sob demanda quando ela foi carregada via API Xtream
  static Future<Map<int, List<StreamItem>>> fetchSeriesEpisodes({
    required SeriesGroup series,
    required String dns,
    required String user,
    required String pass,
  }) async {
    if (series.seasons.isNotEmpty) return series.seasons;
    if (series.seriesId.isEmpty || dns.isEmpty) return {};

    try {
      final url = '$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=get_series_info&series_id=${series.seriesId}';
      final res = await http.get(Uri.parse(url), headers: kIptvHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final episodesMap = data['episodes'];
        final Map<int, List<StreamItem>> parsedSeasons = {};

        if (episodesMap is Map) {
          episodesMap.forEach((seasonKey, epList) {
            final sNum = int.tryParse(seasonKey.toString()) ?? 1;
            if (epList is List) {
              for (final ep in epList) {
                final epId = ep['id']?.toString() ?? '';
                final ext = ep['container_extension']?.toString() ?? 'mp4';
                final epNum = int.tryParse(ep['episode_num']?.toString() ?? '1') ?? 1;
                final epTitle = ep['title']?.toString() ?? 'Episódio $epNum';
                if (epId.isNotEmpty) {
                  parsedSeasons.putIfAbsent(sNum, () => []).add(StreamItem(
                    id: 'ep_$epId',
                    streamId: epId,
                    tvgId: '',
                    name: epTitle,
                    cleanName: epTitle,
                    seriesName: series.title,
                    seasonNumber: sNum,
                    episodeNumber: epNum,
                    qualityTag: series.qualityTag,
                    group: series.group,
                    logo: series.logo,
                    url: '$dns/series/$user/$pass/$epId.$ext',
                    type: ContentType.series,
                    isAdult: series.isAdult,
                  ));
                }
              }
            }
          });
        }
        return parsedSeasons;
      }
    } catch (_) {}
    return {};
  }
}

CatalogBundle _parseXtreamJsonIsolate(Map<String, String> payload) {
  final dns = payload['dns']!;
  final user = payload['user']!;
  final pass = payload['pass']!;

  Map<String, String> parseCatMap(String raw) {
    final map = <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final c in decoded) {
          final id = c['category_id']?.toString() ?? '';
          final name = c['category_name']?.toString() ?? 'Geral';
          if (id.isNotEmpty) map[id] = name;
        }
      }
    } catch (_) {}
    return map;
  }

  final liveCatMap = parseCatMap(payload['liveCats'] ?? '[]');
  final vodCatMap = parseCatMap(payload['vodCats'] ?? '[]');
  final seriesCatMap = parseCatMap(payload['seriesCats'] ?? '[]');

  final qualityRegex = RegExp(r'\b(4K|UHD|FHD|1080P|HD|720P|SD)\b', caseSensitive: false);
  bool checkAdult(String group, String name, dynamic isAdultFlag) {
    if (isAdultFlag?.toString() == '1') return true;
    final g = group.toLowerCase();
    final n = name.toLowerCase();
    return g.contains('adult') || g.contains('+18') || g.contains('xxx') || n.contains('xxx');
  }

  String extractQuality(String name) {
    final m = qualityRegex.firstMatch(name);
    if (m == null) return 'HD';
    return m.group(1)!.toUpperCase().replaceAll('UHD', '4K').replaceAll('1080P', 'FHD').replaceAll('720P', 'HD');
  }

  final List<StreamItem> allItems = [];
  final List<SeriesGroup> seriesGroups = [];

  // 1. Live Streams
  try {
    final liveList = jsonDecode(payload['liveStreams'] ?? '[]');
    if (liveList is List) {
      for (final s in liveList) {
        final sid = s['stream_id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final name = s['name']?.toString() ?? 'Canal $sid';
        final catId = s['category_id']?.toString() ?? '';
        final group = liveCatMap[catId] ?? 'Canais';
        final logo = s['stream_icon']?.toString() ?? '';
        final q = extractQuality(name);
        allItems.add(StreamItem(
          id: 'live_$sid',
          streamId: sid,
          tvgId: s['epg_channel_id']?.toString() ?? '',
          name: name,
          cleanName: name.replaceAll(qualityRegex, '').trim(),
          seriesName: '',
          seasonNumber: 1,
          episodeNumber: 1,
          qualityTag: q,
          group: group,
          logo: logo,
          // Usa formato .m3u8 por padrão na TV para máxima compatibilidade com ExoPlayer (com fallback automático p/ .ts)
          url: '$dns/live/$user/$pass/$sid.m3u8',
          type: ContentType.live,
          isAdult: checkAdult(group, name, s['is_adult']),
        ));
      }
    }
  } catch (_) {}

  // 2. VOD Movies
  try {
    final vodList = jsonDecode(payload['vodStreams'] ?? '[]');
    if (vodList is List) {
      for (final v in vodList) {
        final sid = v['stream_id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final name = v['name']?.toString() ?? 'Filme $sid';
        final catId = v['category_id']?.toString() ?? '';
        final group = vodCatMap[catId] ?? 'Filmes';
        final logo = v['stream_icon']?.toString() ?? '';
        final ext = v['container_extension']?.toString() ?? 'mp4';
        final rating = v['rating']?.toString() ?? '8.2';
        final q = extractQuality(name);
        allItems.add(StreamItem(
          id: 'vod_$sid',
          streamId: sid,
          tvgId: '',
          name: name,
          cleanName: name,
          seriesName: '',
          seasonNumber: 1,
          episodeNumber: 1,
          qualityTag: q,
          group: group,
          logo: logo,
          url: '$dns/movie/$user/$pass/$sid.$ext',
          type: ContentType.movie,
          isAdult: checkAdult(group, name, v['is_adult']),
          rating: rating.isNotEmpty ? rating : '8.2',
        ));
      }
    }
  } catch (_) {}

  // 3. Series
  try {
    final sList = jsonDecode(payload['seriesList'] ?? '[]');
    if (sList is List) {
      for (final sr in sList) {
        final sid = sr['series_id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final title = sr['name']?.toString() ?? 'Série $sid';
        final catId = sr['category_id']?.toString() ?? '';
        final group = seriesCatMap[catId] ?? 'Séries';
        final cover = sr['cover']?.toString() ?? '';
        final plot = sr['plot']?.toString() ?? '';
        seriesGroups.add(SeriesGroup(
          id: 'series_$sid',
          seriesId: sid,
          title: title,
          group: group,
          logo: cover,
          synopsis: plot.isNotEmpty ? plot : 'Selecione para explorar as temporadas e episódios desta série.',
          qualityTag: extractQuality(title),
          isAdult: checkAdult(group, title, null),
          seasons: {},
        ));
      }
    }
  } catch (_) {}

  return CatalogBundle(allItems: allItems, seriesGroups: seriesGroups);
}

// =============================================================================
// PARSER M3U OTIMIZADO (FALLBACK PARA LISTAS M3U ESTÁTICAS)
// =============================================================================
List<StreamItem> parseM3UAdvanced(String raw) {
  final List<StreamItem> result = [];
  final lines = const LineSplitter().convert(raw);
  String name = '', group = 'Canais', logo = '', tvgId = '';
  int counter = 0;

  final groupRegex = RegExp(r'group-title="([^"]*)"', caseSensitive: false);
  final logoRegex = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);
  final qualityRegex = RegExp(r'\b(4K|UHD|FHD|1080P|HD|720P|SD)\b', caseSensitive: false);
  final sePattern = RegExp(r'[sS](\d{1,2})\s*[eE](\d{1,3})', caseSensitive: false);

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#EXTINF:')) {
      group = groupRegex.firstMatch(trimmed)?.group(1)?.trim() ?? 'Geral';
      if (group.isEmpty) group = 'Geral';
      logo = logoRegex.firstMatch(trimmed)?.group(1)?.trim() ?? '';
      name = trimmed.contains(',')
          ? trimmed.substring(trimmed.lastIndexOf(',') + 1).trim()
          : 'Canal ${counter + 1}';
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      counter++;
      final lowerUrl = trimmed.toLowerCase();
      final lowerGroup = group.toLowerCase();

      ContentType type = ContentType.live;
      final seMatch = sePattern.firstMatch(name);
      if (lowerUrl.contains('/series/') || lowerGroup.contains('série') || seMatch != null) {
        type = ContentType.series;
      } else if (lowerUrl.contains('/movie/') ||
          lowerGroup.contains('filme') ||
          lowerUrl.endsWith('.mp4') ||
          lowerUrl.endsWith('.mkv')) {
        type = ContentType.movie;
      }

      String quality = 'HD';
      final qMatch = qualityRegex.firstMatch(name);
      if (qMatch != null) {
        quality = qMatch
            .group(1)!
            .toUpperCase()
            .replaceAll('UHD', '4K')
            .replaceAll('1080P', 'FHD')
            .replaceAll('720P', 'HD');
      }

      final cleanName = name
          .replaceAll(qualityRegex, '')
          .replaceAll(RegExp(r'[\[\]\(\)\-\|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      int seasonNum = 1, episodeNum = 1;
      String extractedSeriesName = cleanName;

      if (type == ContentType.series && seMatch != null) {
        seasonNum = int.tryParse(seMatch.group(1) ?? '1') ?? 1;
        episodeNum = int.tryParse(seMatch.group(2) ?? '1') ?? 1;
        extractedSeriesName =
            name.substring(0, seMatch.start).replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
      }

      final isAdult = lowerGroup.contains('adult') ||
          lowerGroup.contains('+18') ||
          lowerGroup.contains('xxx') ||
          name.toLowerCase().contains('xxx') ||
          lowerGroup.contains('for adult');

      result.add(StreamItem(
        id: '${counter}_${trimmed.hashCode}',
        streamId: '',
        tvgId: tvgId,
        name: name,
        cleanName: cleanName,
        seriesName: extractedSeriesName,
        seasonNumber: seasonNum,
        episodeNumber: episodeNum,
        qualityTag: quality,
        group: group,
        logo: logo,
        url: trimmed,
        type: type,
        isAdult: isAdult,
      ));
      name = '';
      group = 'Geral';
      logo = '';
      tvgId = '';
    }
  }
  return result;
}

List<SeriesGroup> groupSeriesItems(List<StreamItem> items) {
  final Map<String, Map<int, List<StreamItem>>> map = {};
  final Map<String, StreamItem> firstMap = {};
  for (final i in items) {
    final key = i.seriesName.toLowerCase();
    firstMap.putIfAbsent(key, () => i);
    map.putIfAbsent(key, () => {}).putIfAbsent(i.seasonNumber, () => []).add(i);
  }
  return map.entries.map((e) {
    final ref = firstMap[e.key]!;
    final seasons = e.value.map((k, v) {
      v.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return MapEntry(k, v);
    });
    return SeriesGroup(
      id: 's_${e.key.hashCode}',
      title: ref.seriesName,
      group: ref.group,
      logo: ref.logo,
      qualityTag: ref.qualityTag,
      isAdult: ref.isAdult,
      seasons: seasons,
    );
  }).toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}

Future<void> applyDeviceOrientation(DeviceMode mode) async {
  if (mode == DeviceMode.tv) {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight
    ]);
  }
}

Route<T> createSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
