import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

const Map<String, String> kIptvHeaders = {
  'User-Agent': 'IPTVSmartersPlayer/1.0 (Linux; Android 11)',
  'Accept': '*/*',
  'Connection': 'keep-alive',
};

// Canal de comunicação nativa (Para Auto-Detecção de TV, Brilho, Volume e OTA)
const MethodChannel nativeChannel = MethodChannel('unex.vision/native');

enum DeviceMode { mobile, tv }
enum ContentType { live, movie, series }
enum MainSection { live, movie, series, continueWatching, favorites, recents }

// =============================================================================
// MODELOS DE DADOS E VOD (COM METADADOS EXPANDIDOS)
// =============================================================================
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
  
  // Novos Metadados VOD
  final String synopsis;
  final String rating;
  final String year;
  final String cast;

  StreamItem({
    required this.id, required this.streamId, required this.tvgId,
    required this.name, required this.cleanName, required this.seriesName,
    required this.seasonNumber, required this.episodeNumber, required this.qualityTag,
    required this.group, required this.logo, required this.url,
    required this.type, required this.isAdult,
    this.synopsis = 'Nenhuma sinopse disponível.',
    this.rating = 'N/A', this.year = '', this.cast = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'streamId': streamId, 'tvgId': tvgId, 'name': name,
    'cleanName': cleanName, 'seriesName': seriesName, 'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber, 'qualityTag': qualityTag, 'group': group,
    'logo': logo, 'url': url, 'type': type.index, 'isAdult': isAdult,
    'synopsis': synopsis, 'rating': rating, 'year': year, 'cast': cast,
  };

  factory StreamItem.fromJson(Map<String, dynamic> json) {
    return StreamItem(
      id: json['id']?.toString() ?? '', streamId: json['streamId']?.toString() ?? '',
      tvgId: json['tvgId']?.toString() ?? '', name: json['name']?.toString() ?? 'Conteúdo',
      cleanName: json['cleanName']?.toString() ?? '', seriesName: json['seriesName']?.toString() ?? '',
      seasonNumber: (json['seasonNumber'] as int?) ?? 1, episodeNumber: (json['episodeNumber'] as int?) ?? 1,
      qualityTag: json['qualityTag']?.toString() ?? 'HD', group: json['group']?.toString() ?? 'Geral',
      logo: json['logo']?.toString() ?? '', url: json['url']?.toString() ?? '',
      type: ContentType.values[(json['type'] as int?)?.clamp(0, 2) ?? 0],
      isAdult: json['isAdult'] == true,
      synopsis: json['synopsis']?.toString() ?? 'Nenhuma sinopse disponível.',
      rating: json['rating']?.toString() ?? 'N/A', year: json['year']?.toString() ?? '',
      cast: json['cast']?.toString() ?? '',
    );
  }
}

class VodProgressEntry {
  final StreamItem item;
  final int positionSeconds;
  final int durationSeconds;
  final int updatedAtMs;

  VodProgressEntry({required this.item, required this.positionSeconds, required this.durationSeconds, required this.updatedAtMs});
  double get progress => durationSeconds > 0 ? (positionSeconds / durationSeconds).clamp(0.0, 1.0) : 0.0;
  String get formattedRemaining {
    final rem = (durationSeconds - positionSeconds).clamp(0, 86400);
    return 'Faltam ${(rem / 60).ceil()} min';
  }
  String get formattedPosition {
    final m = (positionSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (positionSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
  Map<String, dynamic> toJson() => {'item': item.toJson(), 'positionSeconds': positionSeconds, 'durationSeconds': durationSeconds, 'updatedAtMs': updatedAtMs};
  factory VodProgressEntry.fromJson(Map<String, dynamic> json) => VodProgressEntry(
    item: StreamItem.fromJson((json['item'] as Map?)?.cast<String, dynamic>() ?? {}),
    positionSeconds: (json['positionSeconds'] as int?) ?? 0, durationSeconds: (json['durationSeconds'] as int?) ?? 1, updatedAtMs: (json['updatedAtMs'] as int?) ?? 0,
  );
}

class EpgProgramInfo {
  final String nowTitle; final String nextTitle; final double progress;
  const EpgProgramInfo({required this.nowTitle, required this.nextTitle, this.progress = 0.45});
}

class SeriesGroup {
  final String id; final String title; final String group; final String logo;
  final String qualityTag; final bool isAdult; final Map<int, List<StreamItem>> seasons;
  SeriesGroup({required this.id, required this.title, required this.group, required this.logo, required this.qualityTag, required this.isAdult, required this.seasons});
  int get totalSeasons => seasons.length;
  int get totalEpisodes => seasons.values.fold(0, (sum, list) => sum + list.length);
  List<StreamItem> get allEpisodesFlat {
    final sortedKeys = seasons.keys.toList()..sort();
    return sortedKeys.expand((k) => seasons[k]!).toList();
  }
}

// =============================================================================
// ARMAZENAMENTO OFFLINE-FIRST (PERSISTÊNCIA DEFINITIVA NO DISCO)
// =============================================================================
class AppStorage {
  static String get _tmp => Directory.systemTemp.path;
  static File get _sessionFile => File('$_tmp/unex_verified_session_v8.json');
  static File get _deviceFile => File('$_tmp/unex_device_mode_v8.json');
  static File get _vodProgressFile => File('$_tmp/unex_vod_progress_v8.json');
  static File get _favoritesFile => File('$_tmp/unex_favorites_v8.json');
  static File get _recentsFile => File('$_tmp/unex_recents_v8.json');
  static File get _offlinePlaylistFile => File('$_tmp/unex_offline_playlist_v8.json');

  // Auto-Detecção nativa + Preferência salva
  static Future<DeviceMode> getOrDetectDeviceMode() async {
    try {
      if (await _deviceFile.exists()) {
        final data = jsonDecode(await _deviceFile.readAsString());
        if (data['mode'] == 'tv') return DeviceMode.tv;
        if (data['mode'] == 'mobile') return DeviceMode.mobile;
      }
      final bool isTV = await nativeChannel.invokeMethod('isAndroidTV') ?? false;
      return isTV ? DeviceMode.tv : DeviceMode.mobile;
    } catch (_) { return DeviceMode.tv; }
  }

  static Future<void> saveDeviceMode(DeviceMode mode) async {
    try { await _deviceFile.writeAsString(jsonEncode({'mode': mode == DeviceMode.tv ? 'tv' : 'mobile'})); } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadVerifiedSession() async {
    try {
      if (await _sessionFile.exists()) return jsonDecode(await _sessionFile.readAsString());
    } catch (_) {}
    return null;
  }

  static Future<void> saveVerifiedSession(Map<String, dynamic> data) async {
    try { data['verified'] = true; await _sessionFile.writeAsString(jsonEncode(data)); } catch (_) {}
  }

  static Future<void> clearAllData() async {
    try {
      for (var f in [_sessionFile, _vodProgressFile, _favoritesFile, _recentsFile, _offlinePlaylistFile]) {
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  // Cache Offline da Lista
  static Future<List<StreamItem>> loadOfflinePlaylist() async {
    try {
      if (await _offlinePlaylistFile.exists()) {
        final list = jsonDecode(await _offlinePlaylistFile.readAsString()) as List;
        return list.map((e) => StreamItem.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveOfflinePlaylist(List<StreamItem> items) async {
    try {
      final serialized = items.map((e) => e.toJson()).toList();
      await _offlinePlaylistFile.writeAsString(jsonEncode(serialized));
    } catch (_) {}
  }

  // Persistência de Favoritos e Recentes
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
    try { await _favoritesFile.writeAsString(jsonEncode(favs.toList())); } catch (_) {}
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
    try { await _recentsFile.writeAsString(jsonEncode(recents.take(40).map((e) => e.toJson()).toList())); } catch (_) {}
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
      if (entry.progress >= 0.96) map.remove(entry.item.id);
      else map[entry.item.id] = entry;
      await _vodProgressFile.writeAsString(jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {}
  }
}

// =============================================================================
// MOTOR DE VÍDEO COMPARTILHADO (COM FALLBACK E ANTI-TRAVAMENTO)
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
  double measuredSpeedMbps = 18.5;

  Timer? _watchdogTimer;
  Duration _lastPosition = Duration.zero;
  int _stallCounter = 0;
  int _recoveryAttempts = 0;
  
  void Function(VodProgressEntry entry)? onVodProgressSaved;

  Future<void> openStream(StreamItem item, {Duration? startPosition, bool forceReload = false, bool tryHlsFallback = false}) async {
    if (!forceReload && currentItem?.url == item.url && controller != null && isReady && !hasError) {
      if (startPosition != null && item.type != ContentType.live) await controller!.seekTo(startPosition);
      if (!controller!.value.isPlaying) await controller!.play();
      notifyListeners();
      return;
    }

    _saveCurrentVodProgressImmediately();
    currentItem = item; isReady = false; hasError = false; isRecovering = false;
    if (!tryHlsFallback) _recoveryAttempts = 0;
    notifyListeners();

    _fetchMockEpg(item); // EPG Simulado para manter leveza

    // Fallback de Codec: Se HLS Fallback falhar, tenta outra variante
    String targetUrl = item.url;
    if (tryHlsFallback && targetUrl.endsWith('.ts')) {
      targetUrl = '${targetUrl.substring(0, targetUrl.length - 3)}.m3u8';
    }

    final oldController = controller;
    final newController = VideoPlayerController.networkUrl(Uri.parse(targetUrl), httpHeaders: kIptvHeaders);
    controller = newController;
    await oldController?.dispose();

    try {
      await newController.initialize();
      if (currentItem?.id != item.id) return;

      if (item.type != ContentType.live && startPosition != null && startPosition.inSeconds > 5) {
        await newController.seekTo(startPosition);
      }
      isReady = true; isRecovering = false;
      await newController.play();
      _startWatchdog();
      notifyListeners();
    } catch (_) {
      if (currentItem?.id != item.id) return;
      if (_recoveryAttempts < 2) {
        _recoveryAttempts++;
        await openStream(item, startPosition: startPosition, forceReload: true, tryHlsFallback: !tryHlsFallback);
      } else {
        hasError = true; notifyListeners();
      }
    }
  }

  void _fetchMockEpg(StreamItem item) {
    if (item.type != ContentType.live) return;
    final now = DateTime.now();
    final hourStr = '${now.hour.toString().padLeft(2, '0')}:00';
    final nextHourStr = '${((now.hour + 1) % 24).toString().padLeft(2, '0')}:00';
    currentEpg = EpgProgramInfo(
      nowTitle: '${item.cleanName} • Ao Vivo', nextTitle: 'A Seguir ($nextHourStr)',
      progress: (now.minute / 60.0).clamp(0.05, 0.95),
    );
    notifyListeners();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _stallCounter = 0;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final ctrl = controller; final item = currentItem;
      if (ctrl == null || item == null || !isReady || !ctrl.value.isPlaying) return;

      if (item.type != ContentType.live && timer.tick % 3 == 0) _saveCurrentVodProgressImmediately();

      if (ctrl.value.position == _lastPosition && ctrl.value.isBuffering) {
        _stallCounter++;
        if (_stallCounter >= 2 && !isRecovering) {
          isRecovering = true; notifyListeners();
          if (item.type == ContentType.live && ctrl.value.buffered.isNotEmpty) {
            final liveEdge = ctrl.value.buffered.last.end;
            if (liveEdge > ctrl.value.position + const Duration(seconds: 2)) await ctrl.seekTo(liveEdge);
            await ctrl.play();
          } else {
            await ctrl.pause(); await Future.delayed(const Duration(milliseconds: 800)); await ctrl.play();
          }
          isRecovering = false; _stallCounter = 0; notifyListeners();
        }
      } else { _stallCounter = 0; }
      _lastPosition = ctrl.value.position;
    });
  }

  void _saveCurrentVodProgressImmediately() {
    final ctrl = controller; final item = currentItem;
    if (ctrl == null || item == null || !isReady || item.type == ContentType.live) return;
    final pos = ctrl.value.position.inSeconds; final dur = ctrl.value.duration.inSeconds;
    if (pos >= 10 && dur > 30) {
      final entry = VodProgressEntry(item: item, positionSeconds: pos, durationSeconds: dur, updatedAtMs: DateTime.now().millisecondsSinceEpoch);
      AppStorage.saveVodProgressEntry(entry);
      onVodProgressSaved?.call(entry);
    }
  }

  void togglePlayPause() {
    if (controller == null || !isReady) return;
    if (controller!.value.isPlaying) { controller!.pause(); _saveCurrentVodProgressImmediately(); } 
    else { controller!.play(); }
    notifyListeners();
  }

  Future<void> seekRelative(int seconds) async {
    if (controller == null || !isReady) return;
    final target = controller!.value.position + Duration(seconds: seconds);
    await controller!.seekTo(target.clamp(Duration.zero, controller!.value.duration));
    _saveCurrentVodProgressImmediately();
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    _saveCurrentVodProgressImmediately(); _watchdogTimer?.cancel();
    final old = controller; controller = null; currentItem = null; isReady = false; hasError = false;
    notifyListeners(); await old?.dispose();
  }
}

// =============================================================================
// PARSER M3U OTIMIZADO (COMPUTE BACKGROUND)
// =============================================================================
List<StreamItem> parseM3UAdvanced(String raw) {
  final List<StreamItem> result = [];
  final lines = const LineSplitter().convert(raw);
  String name = '', group = 'Canais', logo = '', tvgId = ''; int counter = 0;

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
      name = trimmed.contains(',') ? trimmed.substring(trimmed.lastIndexOf(',') + 1).trim() : 'Canal ${counter + 1}';
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      counter++;
      final lowerUrl = trimmed.toLowerCase();
      final lowerGroup = group.toLowerCase();

      ContentType type = ContentType.live;
      final seMatch = sePattern.firstMatch(name);
      if (lowerUrl.contains('/series/') || lowerGroup.contains('série') || seMatch != null) type = ContentType.series;
      else if (lowerUrl.contains('/movie/') || lowerGroup.contains('filme') || lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.mkv')) type = ContentType.movie;

      String quality = 'HD';
      final qMatch = qualityRegex.firstMatch(name);
      if (qMatch != null) quality = qMatch.group(1)!.toUpperCase().replaceAll('UHD', '4K').replaceAll('1080P', 'FHD').replaceAll('720P', 'HD');

      final cleanName = name.replaceAll(qualityRegex, '').replaceAll(RegExp(r'[\[\]\(\)\-\|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      int seasonNum = 1, episodeNum = 1; String extractedSeriesName = cleanName;

      if (type == ContentType.series && seMatch != null) {
        seasonNum = int.tryParse(seMatch.group(1) ?? '1') ?? 1;
        episodeNum = int.tryParse(seMatch.group(2) ?? '1') ?? 1;
        extractedSeriesName = name.substring(0, seMatch.start).replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
      }

      result.add(StreamItem(
        id: '${counter}_${trimmed.hashCode}', streamId: '', tvgId: tvgId,
        name: name, cleanName: cleanName, seriesName: extractedSeriesName,
        seasonNumber: seasonNum, episodeNumber: episodeNum, qualityTag: quality,
        group: group, logo: logo, url: trimmed, type: type,
        isAdult: lowerGroup.contains('adult') || lowerGroup.contains('+18'),
      ));
      name = ''; group = 'Geral'; logo = ''; tvgId = '';
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
    final seasons = e.value.map((k, v) { v.sort((a,b) => a.episodeNumber.compareTo(b.episodeNumber)); return MapEntry(k, v); });
    return SeriesGroup(id: 's_${e.key.hashCode}', title: ref.seriesName, group: ref.group, logo: ref.logo, qualityTag: ref.qualityTag, isAdult: ref.isAdult, seasons: seasons);
  }).toList()..sort((a,b) => a.title.compareTo(b.title));
}

Future<void> applyDeviceOrientation(DeviceMode mode) async {
  if (mode == DeviceMode.tv) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  } else {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }
}

Route<T> createSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved), child: child));
    },
  );
}
