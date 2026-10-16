import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'core.dart';
import 'widgets.dart';
import 'mobile_screen.dart';
import 'tv_screen.dart';
import 'player_screen.dart';

const String kAppVersion = '2.0.0';
const String kOtaCheckUrl = 'https://raw.githubusercontent.com/unexvision/ota/main/version.json';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const SizedBox.shrink();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const UnexVisionApp());
}

class UnexVisionApp extends StatelessWidget {
  const UnexVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNEX Vision',
      debugShowCheckedModeBanner: false,
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08090E),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF12151F),
        ),
      ),
      home: const BootRouterScreen(),
    );
  }
}

// =============================================================================
// 1. BOOTg AUTOMÁTICO (AUTO-DETECÇÃO DE APARELHO + ESSÃO SALVA)
// =============================================================================
class BootRouterScreen extends StatefulWidget {
  const BootRouterScreen({super.key});
  @override
  State<BootRouterScreen> createState() => _BootRouterScreenState();
}

class _BootRouterScreenState extends State<BootRouterScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final mode = await AppStorage.getOrDetectDeviceMode();
    await AppStorage.saveDeviceMode(mode);
    await applyDeviceOrientation(mode);
    final session = await AppStorage.loadVerifiedSession();
    if (!mounted) return;

    if (session != null && session['verified'] == true) {
      Navigator.pushReplacement(
        context,
        createSmoothRoute(MainDashboard(
          deviceMode: mode,
          serverDns: session['dns']?.toString() ?? '',
          username: session['user']?.toString() ?? '',
          password: session['pass']?.toString() ?? '',
          directM3uUrl: session['m3uUrl']?.toString(),
        )),
      );
    } else {
      Navigator.pushReplacement(
        context,
        createSmoothRoute(LoginGatewayScreen(deviceMode: mode)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
}

// =============================================================================
// 2. LOGIN INTELIGENTE + BLOQUEIO DE VENCIMENTO + TECLADO DE TV COMPACTO
// =============================================================================
class LoginGatewayScreen extends StatefulWidget {
  final DeviceMode deviceMode;
  final String? errorBanner;
  const LoginGatewayScreen({super.key, required this.deviceMode, this.errorBanner});

  @override
  State<LoginGatewayScreen> createState() => _LoginGatewayScreenState();
}

class _LoginGatewayScreenState extends State<LoginGatewayScreen> {
  final _dnsCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _m3uCtrl = TextEditingController();

  late DeviceMode _mode;
  bool _directM3u = false;
  bool _validating = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _mode = widget.deviceMode;
    _errorMsg = widget.errorBanner;
  }

  @override
  void dispose() {
    _dnsCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _m3uCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleDeviceMode() async {
    final next = _mode == DeviceMode.tv ? DeviceMode.mobile : DeviceMode.tv;
    await AppStorage.saveDeviceMode(next);
    await applyDeviceOrientation(next);
    if (mounted) setState(() => _mode = next);
  }

  Future<void> _submitLogin() async {
    setState(() { _validating = true; _errorMsg = null; });

    if (_directM3u) {
      String url = _m3uCtrl.text.trim();
      if (url.isEmpty) {
        setState(() { _validating = false; _errorMsg = 'Informe o link M3U completo.'; });
        return;
      }
      if (!url.startsWith('http')) url = 'http://$url';
      _proceed(directM3uUrl: url);
      return;
    }

    String dns = _dnsCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (dns.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() { _validating = false; _errorMsg = 'Preencha DNS, Usuário e Senha.'; });
      return;
    }
    if (!dns.startsWith('http')) dns = 'http://$dns';
    while (dns.endsWith('/')) dns = dns.substring(0, dns.length - 1);

    // Regra de Negócio: Verifica se a assinatura Xtream está vencida
    try {
      final uri = Uri.parse('$dns/player_api.php?username=$user&password=$pass');
      final res = await http.get(uri, headers: kIptvHeaders).timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final info = data['user_info'];
        if (info != null) {
          final status = info['status']?.toString().toLowerCase() ?? '';
          final expRaw = int.tryParse(info['exp_date']?.toString() ?? '');
          final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (status == 'expired' || status == 'banned' || (expRaw != null && expRaw > 0 && expRaw < nowSec)) {
            setState(() {
              _validating = false;
              _errorMsg = 'Sua assinatura está vencida. Entre em contato com seu provedor para renovar.';
            });
            return;
          }
        }
      }
    } catch (_) {}

    _proceed(dns: dns, user: user, pass: pass);
  }

  void _proceed({String dns = '', String user = '', String pass = '', String? directM3uUrl}) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      createSmoothRoute(MainDashboard(
        deviceMode: _mode,
        serverDns: dns,
        username: user,
        password: pass,
        directM3uUrl: directM3uUrl,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _mode == DeviceMode.tv;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment.topRight, radius: 1.4, colors: [Color(0xFF132238), Color(0xFF08090E)]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12151F).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isTV ? '📺 Modo TV Android' : '📱 Modo Celular',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                          TVFocusableItem(
                            autoScroll: false,
                            onSelect: _toggleDeviceMode,
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white12),
                              ),
                              child: const Text('Alternar Modo', style: TextStyle(fontSize: 10, color: Colors.white70)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('UNEX VISION', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                      const SizedBox(height: 4),
                      Text(_directM3u ? 'Insira o link M3U Plus da lista' : 'Informe os dados de acesso da sua conta',
                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(_errorMsg!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (!_directM3u) ...[
                        _buildInput('URL / DNS do Servidor', 'http://servidor.club', _dnsCtrl, Icons.dns_rounded),
                        const SizedBox(height: 10),
                        _buildInput('Usuário', 'Seu usuário', _userCtrl, Icons.person_outline),
                        const SizedBox(height: 10),
                        _buildInput('Senha', 'Sua senha', _passCtrl, Icons.lock_outline, obscure: true),
                      ] else ...[
                        _buildInput('Link M3U Completo', 'http://.../get.php?...', _m3uCtrl, Icons.link_rounded),
                      ],
                      const SizedBox(height: 18),
                      if (_validating)
                        const CircularProgressIndicator(color: Color(0xFF00E5FF))
                      else
                        SizedBox(
                          width: double.infinity,
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: _submitLogin,
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2),
                              ),
                              child: const Center(
                                child: Text('CONECTAR AGORA', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => setState(() => _directM3u = !_directM3u),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.transparent),
                          ),
                          child: Text(
                            _directM3u ? 'Usar DNS, Usuário e Senha' : 'Usar Link M3U Direto',
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(String label, String hint, TextEditingController ctrl, IconData icon, {bool obscure = false}) {
    if (_mode == DeviceMode.mobile) {
      return TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label, hintText: hint, prefixIcon: Icon(icon, color: const Color(0xFF00E5FF)),
          filled: true, fillColor: const Color(0xFF08090E),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: ctrl,
      builder: (context, val, _) {
        final txt = val.text.isEmpty ? hint : (obscure ? '•' * val.text.length : val.text);
        return TVFocusableItem(
          autoScroll: false,
          onSelect: () => _openCompactTVKeyboard(context, ctrl, label),
          builder: (c, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF08090E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white12, width: f ? 2 : 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF00E5FF), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                    Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: val.text.isEmpty ? Colors.white38 : Colors.white)),
                  ]),
                ),
                const Text('OK', style: TextStyle(fontSize: 10, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// 3. PAINEL PRINCIPAL OFFLINE-FIRST (<1s) + SINCRONIZAÇÃO EM SEGUNDO PLANO + OTA
// =============================================================================
class MainDashboard extends StatefulWidget {
  final DeviceMode deviceMode;
  final String serverDns;
  final String username;
  final String password;
  final String? directM3uUrl;

  const MainDashboard({
    super.key,
    required this.deviceMode,
    required this.serverDns,
    required this.username,
    required this.password,
    this.directM3uUrl,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

  Future<void> _openFullScreen(StreamItem item, {List<StreamItem>? customList}) async {
    _recordRecent(item);
    Duration? startPos;
    final saved = vodProgressMap[item.id];
    if (item.type != ContentType.live && saved != null && _engine.currentItem?.id != item.id) {
      startPos = await showVodResumePrompt(context: context, entry: saved);
      if (startPos == null) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      createSmoothRoute(SmartAdaptivePlayerScreen(
        initialItem: item,
        playlist: customList ?? (displayedItems.isNotEmpty ? displayedItems : liveItems),
        deviceMode: _mode,
        initialStartPosition: startPos,
      )),
    );
  }


  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  late DeviceMode _mode;
  bool isTVSideMenuOpen = false;
  bool isLoading = true;
  String errorMessage = '';

  List<StreamItem> allItems = [], liveItems = [], movieItems = [], seriesItems = [];
  List<SeriesGroup> allSeriesGroups = [], displayedSeries = [];
  List<StreamItem> displayedItems = [], recentItems = [];
  Set<String> favoriteIds = {};
  Map<String, VodProgressEntry> vodProgressMap = {};
  Map<String, int> categoryCounts = {};
  List<String> sectionCategories = ['Todas'];

  MainSection activeSection = MainSection.live;
  String selectedCategory = 'Todas';
  String searchQuery = '';

  String get _m3uUrl => (widget.directM3uUrl != null && widget.directM3uUrl!.isNotEmpty)
      ? widget.directM3uUrl!
      : '${widget.serverDns}/get.php?username=${widget.username}&password=${widget.password}&type=m3u_plus&output=ts';

  List<VodProgressEntry> get _sortedContinue =>
      vodProgressMap.values.toList()..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

  @override
  void initState() {
    super.initState();
    _mode = widget.deviceMode;
    // Controle Estrito de Memória de Imagens para TV Boxes de 1GB/2GB RAM
    PaintingBinding.instance.imageCache.maximumSize = 120;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 35 << 20; // Máx 35 MB

    _engine.addListener(_onEngineChange);
    _engine.onVodProgressSaved = (entry) {
      if (!mounted) return;
      setState(() {
        if (entry.progress >= 0.96) vodProgressMap.remove(entry.item.id);
        else vodProgressMap[entry.item.id] = entry;
      });
    };

    _bootOfflineFirstAndSync();
    _checkOtaUpdateSilently();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onEngineChange() { if (mounted) setState(() {}); }

    Future<void> _bootOfflineFirstAndSync() async {
    favoriteIds = await AppStorage.loadFavorites();
    recentItems = await AppStorage.loadRecents();
    vodProgressMap = await AppStorage.loadVodProgressMap();

    final cached = await AppStorage.loadOfflinePlaylist();
    if (cached.isNotEmpty && mounted) {
      await _applyCatalog(cached, startFirstChannel: true);
    }

    try {
      // Timeout estendido para TV Boxes com internet Wi-Fi instável
      final res = await http.get(Uri.parse(_m3uUrl), headers: kIptvHeaders).timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final parsed = await compute(parseM3UAdvanced, body);
        if (parsed.isNotEmpty) {
          await AppStorage.saveVerifiedSession({
            'dns': widget.serverDns, 'user': widget.username, 'pass': widget.password, 'm3uUrl': widget.directM3uUrl,
          });
          await AppStorage.saveOfflinePlaylist(parsed);
          if (mounted) await _applyCatalog(parsed, startFirstChannel: cached.isEmpty);
          return;
        }
      }
      if (cached.isEmpty && mounted) {
        setState(() { isLoading = false; errorMessage = 'Servidor retornou erro ou lista vazia.'; });
      }
    } catch (e) {
      if (cached.isEmpty && mounted) {
        setState(() { isLoading = false; errorMessage = 'Falha de conexão na TV: Verifique a internet e o DNS.'; });
      }
    }
    }
  

  Future<void> _applyCatalog(List<StreamItem> items, {required bool startFirstChannel}) async {
    final live = <StreamItem>[], movies = <StreamItem>[], series = <StreamItem>[];
    for (final i in items) {
      if (i.type == ContentType.live) live.add(i);
      else if (i.type == ContentType.movie) movies.add(i);
      else series.add(i);
    }
    final grouped = await compute(groupSeriesItems, series);
    if (!mounted) return;
    setState(() {
      allItems = items; liveItems = live; movieItems = movies; seriesItems = series; allSeriesGroups = grouped;
      isLoading = false; errorMessage = '';
      _rebuildCategories();
    });
    if (startFirstChannel && _engine.currentItem == null) {
      final initial = recentItems.isNotEmpty ? recentItems.first : (live.isNotEmpty ? live.first : items.first);
      _engine.openStream(initial);
    }
  }

  // CHECAGEM REMOTA DE ATUALIZAÇÃO (OTA CHECK)
  Future<void> _checkOtaUpdateSilently() async {
    try {
      final res = await http.get(Uri.parse(kOtaCheckUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final latest = data['version']?.toString() ?? kAppVersion;
        final apkUrl = data['apk_url']?.toString() ?? '';
        if (latest != kAppVersion && apkUrl.isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF121622),
              title: Text('Nova Versão Disponível ($latest)'),
              content: Text(data['notes']?.toString() ?? 'Uma nova atualização otimizada está pronta para download.'),
              actions: [
                TVFocusableItem(
                  autofocus: true,
                  onSelect: () {
                    Navigator.pop(ctx);
                    nativeChannel.invokeMethod('openExternalUrl', {'url': apkUrl});
                  },
                  builder: (c, f) => Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Atualizar Agora', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
                TVFocusableItem(
                  onSelect: () => Navigator.pop(ctx),
                  builder: (c, f) => const Padding(padding: EdgeInsets.all(10), child: Text('Depois')),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {}
  }

  List<StreamItem> _baseList(MainSection sec) {
    switch (sec) {
      case MainSection.live: return liveItems;
      case MainSection.movie: return movieItems;
      case MainSection.series: return seriesItems;
      case MainSection.continueWatching: return _sortedContinue.map((e) => e.item).toList();
      case MainSection.favorites: return allItems.where((i) => favoriteIds.contains(i.id)).toList();
      case MainSection.recents: return recentItems;
    }
  }

  String _secTitle(MainSection sec) {
    switch (sec) {
      case MainSection.live: return 'TV ao Vivo';
      case MainSection.movie: return 'Filmes';
      case MainSection.series: return 'Séries';
      case MainSection.continueWatching: return 'Continuar Assistindo';
      case MainSection.favorites: return 'Meus Favoritos';
      case MainSection.recents: return 'Assistidos Recentemente';
    }
  }

  void _rebuildCategories() {
    if (activeSection == MainSection.series) {
      final counts = <String, int>{'Todas': allSeriesGroups.length};
      for (final s in allSeriesGroups) counts[s.group] = (counts[s.group] ?? 0) + 1;
      categoryCounts = counts;
      sectionCategories = counts.keys.toList();
    } else {
      final base = _baseList(activeSection);
      final counts = <String, int>{'Todas': base.length};
      for (final i in base) counts[i.group] = (counts[i.group] ?? 0) + 1;
      categoryCounts = counts;
      sectionCategories = counts.keys.toList();
    }
    if (!sectionCategories.contains(selectedCategory)) selectedCategory = 'Todas';
    _filterContent();
  }

  void _filterContent() {
    final q = searchQuery.trim().toLowerCase();
    if (activeSection == MainSection.series) {
      var list = selectedCategory == 'Todas'
          ? allSeriesGroups
          : allSeriesGroups.where((s) => s.group == selectedCategory).toList();
      if (q.isNotEmpty) list = list.where((s) => s.title.toLowerCase().contains(q)).toList();
      setState(() => displayedSeries = list);
    } else {
      var list = selectedCategory == 'Todas'
          ? _baseList(activeSection)
          : _baseList(activeSection).where((i) => i.group == selectedCategory).toList();
      if (q.isNotEmpty) list = list.where((i) => i.name.toLowerCase().contains(q)).toList();
      setState(() => displayedItems = list);
    }
  }

  void _toggleFavorite(StreamItem item) {
    setState(() {
      if (favoriteIds.contains(item.id)) favoriteIds.remove(item.id);
      else favoriteIds.add(item.id);
      AppStorage.saveFavorites(favoriteIds);
      if (activeSection == MainSection.favorites) _rebuildCategories();
    });
  }

  void _recordRecent(StreamItem item) {
    recentItems.removeWhere((r) => r.id == item.id);
    recentItems.insert(0, item);
    if (recentItems.length > 40) recentItems.removeLast();
    AppStorage.saveRecents(recentItems);
  }

    void _handlePreviewOrPlay(StreamItem item) {
    _recordRecent(item);
    
    // Se o usuário apertar OK ou navegar para um item na TV, disparamos o stream imediatamente
    if (_engine.currentItem?.id == item.id && _engine.isReady) {
      if (item.type == ContentType.movie) {
        _showVodMetadataSheet(item);
      } else {
        _openFullScreen(item);
      }
      return;
    }

    // Dispara a abertura do stream na pré-visualização da TV ou Celular
    _engine.openStream(item);
  }


  // MODAL DE METADADOS EXPANDIDOS VOD (SINOPSE, AVALIAÇÃO, ANO E EPISÓDIOS)
  void _showVodMetadataSheet(StreamItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101420),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF00E5FF))),
        title: Row(children: [
          buildQualityBadge(item.qualityTag),
          const SizedBox(width: 8),
          Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Categoria: ${item.group} • Nota: ★ ${item.rating != "N/A" ? item.rating : "8.4"}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            item.synopsis != 'Nenhuma sinopse disponível.'
                ? item.synopsis
                : 'Conteúdo sob demanda otimizado em alta definição (${item.qualityTag}) do catálogo ${item.group}.',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ]),
        actions: [
          TVFocusableItem(
            autofocus: true,
            onSelect: () { Navigator.pop(ctx); _openFullScreen(item); },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2)),
              child: const Text('▶ Assistir Agora', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
          ),
          TVFocusableItem(
            onSelect: () { _toggleFavorite(item); Navigator.pop(ctx); },
            builder: (c, f) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24), borderRadius: BorderRadius.circular(8)),
              child: Text(favoriteIds.contains(item.id) ? '★ Remover Favorito' : '☆ Favoritar'),
            ),
          ),
        ],
      ),
    );
  }

  void _openSeriesEpisodesModal(SeriesGroup series) {
    final seasons = series.seasons.keys.toList()..sort();
    int selSeason = seasons.isNotEmpty ? seasons.first : 1;
    final flatList = series.allEpisodesFlat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          final eps = series.seasons[selSeason] ?? [];
          return Dialog(
            backgroundColor: const Color(0xFF0D111C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF00E5FF))),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    buildChannelLogo(series.logo, size: 54),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(series.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('${series.group} • ${series.totalSeasons} Temporada(s) • ${series.totalEpisodes} Episódios',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF))),
                    ])),
                    TVIconButton(icon: Icons.close, onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: seasons.length,
                      itemBuilder: (c, i) {
                        final s = seasons[i];
                        final active = s == selSeason;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: () => setModal(() => selSeason = s),
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: active ? const Color(0xFF00E5FF) : const Color(0xFF171C2B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: f ? Colors.white : Colors.transparent),
                              ),
                              child: Text('Temporada $s', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.black : Colors.white)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 18),
                  Expanded(
                    child: ListView.builder(
                      itemCount: eps.length,
                      itemBuilder: (c, idx) {
                        final ep = eps[idx];
                        final prog = vodProgressMap[ep.id];
                        return TVFocusableItem(
                          autofocus: idx == 0,
                          onSelect: () { Navigator.pop(ctx); _openFullScreen(ep, customList: flatList); },
                          builder: (c, f) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: f ? const Color(0xFF1A2842) : const Color(0xFF131724),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white10),
                            ),
                            child: Row(children: [
                              Text('E${ep.episodeNumber.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00E5FF))),
                              const SizedBox(width: 12),
                              Expanded(child: Text(ep.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                              if (prog != null) Text('${prog.formattedPosition} ', style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                              const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF), size: 22),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniVideo() {
    if (_engine.hasError) return const Center(child: Text('Sinal indisponível', style: TextStyle(fontSize: 11, color: Colors.white54)));
    if (!_engine.isReady || _engine.controller == null) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    final c = _engine.controller!;
    return FittedBox(fit: BoxFit.contain, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)));
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _mode == DeviceMode.tv;
    final mobileView = MobileDashboardView(
      scaffoldKey: _scaffoldKey,
      activeSection: activeSection,
      sectionTitle: _secTitle(activeSection),
      selectedCategory: selectedCategory,
      sectionCategories: sectionCategories,
      categoryCounts: categoryCounts,
      displayedItems: displayedItems,
      displayedSeries: displayedSeries,
      continueWatchingEntries: _sortedContinue,
      vodProgressMap: vodProgressMap,
      favoriteIds: favoriteIds,
      activeItem: _engine.currentItem,
      activeEpg: _engine.currentEpg,
      miniVideoWidget: _buildMiniVideo(),
      searchController: _searchCtrl,
      searchQuery: searchQuery,
      onSelectSection: (s) => setState(() { activeSection = s; selectedCategory = 'Todas'; _rebuildCategories(); }),
      onSelectCategory: (c) => setState(() { selectedCategory = c; _filterContent(); }),
      onSearchChanged: (v) { searchQuery = v; _filterContent(); },
      onClearSearch: () { _searchCtrl.clear(); searchQuery = ''; _filterContent(); },
      onStartPreview: _handlePreviewOrPlay,
      onOpenFullScreen: _openFullScreen,
      onSelectSeriesGroup: _openSeriesEpisodesModal,
      onToggleFavorite: _toggleFavorite,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isTV ? null : mobileView.buildDrawer(context),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
            : errorMessage.isNotEmpty
                ? Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(errorMessage, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () async {
                          await AppStorage.clearAllData();
                          if (!mounted) return;
                          Navigator.pushReplacement(context, createSmoothRoute(LoginGatewayScreen(deviceMode: _mode)));
                        },
                        child: const Text('Voltar ao Login'),
                      ),
                    ]),
                  )
                : isTV
                    ? TVDashboardView(
                        isSideMenuOpen: isTVSideMenuOpen,
                        onOpenSideMenu: () => setState(() => isTVSideMenuOpen = true),
                        onCloseSideMenu: () => setState(() => isTVSideMenuOpen = false),
                        activeSection: activeSection,
                        sectionTitle: _secTitle(activeSection),
                        selectedCategory: selectedCategory,
                        sectionCategories: sectionCategories,
                        categoryCounts: categoryCounts,
                        displayedItems: displayedItems,
                        displayedSeries: displayedSeries,
                        vodProgressMap: vodProgressMap,
                        favoriteIds: favoriteIds,
                        activeItem: _engine.currentItem,
                        miniVideoWidget: _buildMiniVideo(),
                        onSelectSection: (s) => setState(() { activeSection = s; selectedCategory = 'Todas'; isTVSideMenuOpen = false; _rebuildCategories(); }),
                        onSelectCategory: (c) => setState(() { selectedCategory = c; isTVSideMenuOpen = false; _filterContent(); }),
                        onStartPreview: _handlePreviewOrPlay,
                        onOpenFullScreen: _openFullScreen,
                        onSelectSeriesGroup: _openSeriesEpisodesModal,
                        onToggleFavorite: _toggleFavorite,
                      )
                    : mobileView,
      ),
    );
  }
}

// Teclado Virtual Compacto em Dock para o Login da TV
Future<void> _openCompactTVKeyboard(BuildContext context, TextEditingController ctrl, String title) async {
  const rows = ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  const webKeys = ['http://', 'https://', '.club', '.com', '.net', ':8080', '/', ':', '.', '-', '_', '?', '=', '&'];
  bool showWeb = false;

  await showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 680,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E17).withOpacity(0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF00E5FF)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text('$title: ', style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                Expanded(child: Text('${ctrl.text}▌', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                TVFocusableItem(
                  autoScroll: false,
                  onSelect: () => Navigator.pop(ctx),
                  builder: (c, f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(6)),
                    child: const Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (showWeb)
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: webKeys.map((k) => _keyBtn(k, () => setModal(() => ctrl.text += k))).toList(),
                )
              else
                ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(spacing: 5, children: r.split('').map((ch) => _keyBtn(ch, () => setModal(() => ctrl.text += ch), w: 42)).toList()),
                )),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                _keyBtn(showWeb ? '⌨ QWERTY' : '🌐 Atalhos Web', () => setModal(() => showWeb = !showWeb)),
                _keyBtn('ESPAÇO', () => setModal(() => ctrl.text += ' '), w: 95),
                _keyBtn('⌫ Apagar', () => setModal(() { if (ctrl.text.isNotEmpty) ctrl.text = ctrl.text.substring(0, ctrl.text.length - 1); })),
                _keyBtn('Limpar', () => setModal(() => ctrl.clear())),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

Widget _keyBtn(String label, VoidCallback onTap, {double? w}) {
  return TVFocusableItem(
    autoScroll: false,
    onSelect: onTap,
    builder: (c, f) => Container(
      width: w,
      padding: EdgeInsets.symmetric(horizontal: w == null ? 10 : 0, vertical: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: f ? const Color(0xFF00E5FF) : const Color(0xFF181C28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: f ? Colors.white : Colors.white12),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: f ? Colors.black : Colors.white)),
    ),
  );
}
