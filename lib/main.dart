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

const String kAppVersion = '2.1.0';
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
        scaffoldBackgroundColor: const Color(0xFF090B10),
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
// BOOT AUTOMÁTICO
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
// LOGIN INTELIGENTE (SEM TECLADO NATIVO DA TV)
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
    FocusScope.of(context).unfocus();
    setState(() {
      _validating = true;
      _errorMsg = null;
    });

    if (_directM3u) {
      final rawUrl = _m3uCtrl.text.trim();
      if (rawUrl.isEmpty) {
        setState(() {
          _validating = false;
          _errorMsg = 'Insira o link M3U completo.';
        });
        return;
      }
      final cleanedUrl = XtreamCatalogService.cleanInputUrl(rawUrl);
      _proceed(directM3uUrl: cleanedUrl);
      return;
    }

    final rawDns = _dnsCtrl.text.trim();
    final user = _userCtrl.text.replaceAll(RegExp(r'\s+'), '').trim();
    final pass = _passCtrl.text.replaceAll(RegExp(r'\s+'), '').trim();
    if (rawDns.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() {
        _validating = false;
        _errorMsg = 'Preencha DNS, Utilizador e Senha.';
      });
      return;
    }

    final dns = XtreamCatalogService.cleanInputUrl(rawDns);

    try {
      final uri = Uri.parse('$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}');
      final res = await http.get(uri, headers: kIptvHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final info = data['user_info'];
        if (info != null) {
          final auth = info['auth']?.toString() ?? '1';
          if (auth == '0') {
            setState(() {
              _validating = false;
              _errorMsg = 'Utilizador ou senha incorretos.';
            });
            return;
          }
          final status = info['status']?.toString().toLowerCase() ?? '';
          final expRaw = int.tryParse(info['exp_date']?.toString() ?? '');
          final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (status == 'expired' || status == 'banned' || (expRaw != null && expRaw > 0 && expRaw < nowSec)) {
            setState(() {
              _validating = false;
              _errorMsg = 'A sua subscrição expirou. Entre em contacto com o seu fornecedor.';
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
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [Color(0xFF132238), Color(0xFF090B10)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Container(
                  padding: const EdgeInsets.all(24),
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
                          Text(
                            isTV ? '📺 Modo TV Android' : '📱 Modo Telemóvel',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TVFocusableItem(
                            autoScroll: false,
                            onSelect: _toggleDeviceMode,
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: f ? const Color(0xFF00E5FF) : Colors.white12,
                                ),
                              ),
                              child: const Text(
                                'Alternar Modo',
                                style: TextStyle(fontSize: 10, color: Colors.white70),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'UNEX VISION',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.8),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _directM3u
                            ? 'Insira o link M3U Plus da lista'
                            : 'Insira os dados de acesso da sua conta',
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            _errorMsg!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: Colors.white),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (!_directM3u) ...[
                        _buildInput('URL / DNS do Servidor', 'Ex: http://servidor.club', _dnsCtrl, Icons.dns_rounded),
                        _buildInput('Utilizador', 'O seu utilizador', _userCtrl, Icons.person_outline),
                        _buildInput('Senha', 'A sua senha', _passCtrl, Icons.lock_outline, obscure: true),
                      ] else ...[
                        _buildInput('Link M3U Completo', 'http://.../get.php?...', _m3uCtrl, Icons.link_rounded),
                      ],
                      const SizedBox(height: 12),
                      if (_validating)
                        const CircularProgressIndicator(color: Color(0xFF00E5FF))
                      else
                        SizedBox(
                          width: double.infinity,
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: _submitLogin,
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: f ? Colors.white : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'LIGAR AGORA',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => setState(() => _directM3u = !_directM3u),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: f ? const Color(0xFF00E5FF) : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            _directM3u ? 'Usar DNS, Utilizador e Senha' : 'Usar Link M3U Direto',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF00E5FF)),
            filled: true,
            fillColor: const Color(0xFF080A10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: ctrl,
      builder: (context, val, _) {
        final txt = val.text.isEmpty ? hint : (obscure ? '•' * val.text.length : val.text);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TVFocusableItem(
            autoScroll: false,
            onSelect: () => showTVVirtualKeyboard(context, ctrl, label, isPassword: obscure),
            builder: (c, f) => AnimatedScale(
              scale: f ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF080A10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: f ? const Color(0xFF00E5FF) : Colors.white12,
                    width: f ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: f ? Colors.white : const Color(0xFF00E5FF), size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            txt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: val.text.isEmpty ? Colors.white38 : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'OK',
                      style: TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// PAINEL PRINCIPAL (DASHBOARD)
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

class _MainDashboardState extends State<MainDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  late DeviceMode _mode;
  bool isTVSideMenuOpen = false;
  bool isLoading = true;
  String loadingStatus = 'A conectar ao servidor...';
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

  String get _cleanDns => XtreamCatalogService.cleanInputUrl(widget.serverDns);

  String get _m3uUrl {
    if (widget.directM3uUrl != null && widget.directM3uUrl!.isNotEmpty) {
      return XtreamCatalogService.cleanInputUrl(widget.directM3uUrl!);
    }
    final u = Uri.encodeComponent(widget.username.trim());
    final p = Uri.encodeComponent(widget.password.trim());
    return '$_cleanDns/get.php?username=$u&password=$p&type=m3u_plus&output=ts';
  }

  List<VodProgressEntry> get _sortedContinue =>
      vodProgressMap.values.toList()..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

  @override
  void initState() {
    super.initState();
    _mode = widget.deviceMode;
    PaintingBinding.instance.imageCache.maximumSize = 120;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 35 << 20;

    _engine.addListener(_onEngineChange);
    _engine.onVodProgressSaved = (entry) {
      if (!mounted) return;
      setState(() {
        if (entry.progress >= 0.96) {
          vodProgressMap.remove(entry.item.id);
        } else {
          vodProgressMap[entry.item.id] = entry;
        }
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

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  Future<void> _bootOfflineFirstAndSync() async {
    setState(() {
      isLoading = allItems.isEmpty;
      errorMessage = '';
      loadingStatus = 'A sincronizar canais e catálogo...';
    });

    favoriteIds = await AppStorage.loadFavorites();
    recentItems = await AppStorage.loadRecents();
    vodProgressMap = await AppStorage.loadVodProgressMap();

    final cached = await AppStorage.loadOfflinePlaylist();
    if (cached.isNotEmpty && mounted) {
      await _applyCatalog(cached, null, startFirstChannel: true);
    }

    final creds = XtreamCatalogService.extractXtreamCredentials(
      serverDns: widget.serverDns,
      username: widget.username,
      password: widget.password,
      directM3uUrl: widget.directM3uUrl,
    );

    if (creds != null) {
      final bundle = await XtreamCatalogService.fetchViaXtreamApi(
        dns: creds['dns']!,
        user: creds['user']!,
        pass: creds['pass']!,
      );

      if (bundle != null && bundle.allItems.isNotEmpty) {
        await AppStorage.saveVerifiedSession({
          'dns': creds['dns'],
          'user': creds['user'],
          'pass': creds['pass'],
          'm3uUrl': widget.directM3uUrl,
        });
        if (mounted) {
          await _applyCatalog(bundle.allItems, bundle.seriesGroups, startFirstChannel: cached.isEmpty);
        }
        Future.delayed(const Duration(seconds: 4), () {
          AppStorage.saveOfflinePlaylist(bundle.allItems);
        });
        return;
      }
    }

    try {
      if (mounted && cached.isEmpty) {
        setState(() => loadingStatus = 'A transferir lista M3U completa...');
      }
      final res = await http.get(Uri.parse(_m3uUrl), headers: kIptvHeaders).timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final parsed = await compute(parseM3UAdvanced, body);
        if (parsed.isNotEmpty) {
          await AppStorage.saveVerifiedSession({
            'dns': widget.serverDns,
            'user': widget.username,
            'pass': widget.password,
            'm3uUrl': widget.directM3uUrl,
          });
          if (mounted) await _applyCatalog(parsed, null, startFirstChannel: cached.isEmpty);
          Future.delayed(const Duration(seconds: 4), () {
            AppStorage.saveOfflinePlaylist(parsed);
          });
          return;
        }
      }
      if (cached.isEmpty && mounted) {
        setState(() {
          isLoading = false;
          errorMessage = 'Servidor respondeu sem canais ativos. Verifique o Utilizador e a Senha.';
        });
      }
    } catch (_) {
      if (cached.isEmpty && mounted) {
        setState(() {
          isLoading = false;
          errorMessage = 'Não foi possível conectar ao servidor.\nVerifique se o endereço DNS (${widget.serverDns.isNotEmpty ? widget.serverDns : "M3U"}) está correto.';
        });
      }
    }
  }

  Future<void> _applyCatalog(
    List<StreamItem> items,
    List<SeriesGroup>? preGroupedSeries, {
    required bool startFirstChannel,
  }) async {
    final live = <StreamItem>[], movies = <StreamItem>[], series = <StreamItem>[];
    for (final i in items) {
      if (i.type == ContentType.live) {
        live.add(i);
      } else if (i.type == ContentType.movie) {
        movies.add(i);
      } else {
        series.add(i);
      }
    }
    final List<SeriesGroup> grouped = preGroupedSeries ?? await compute(groupSeriesItems, series);
    if (!mounted) return;
    setState(() {
      allItems = items;
      liveItems = live;
      movieItems = movies;
      seriesItems = series;
      allSeriesGroups = grouped;
      isLoading = false;
      errorMessage = '';
      _rebuildCategories();
    });

    if (startFirstChannel && _engine.currentItem == null) {
      final safeLive = live.where((c) => !c.isAdult).toList();
      final initial = safeLive.isNotEmpty
          ? safeLive.first
          : (live.isNotEmpty ? live.first : items.first);
      _engine.openStream(initial);
    }
  }

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
              content: Text(data['notes']?.toString() ?? 'Uma nova atualização otimizada está pronta para transferência.'),
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
                  builder: (c, f) => const Padding(padding: EdgeInsets.all(10), child: Text('Mais tarde')),
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
      case MainSection.continueWatching: return 'Continuar a Ver';
      case MainSection.favorites: return 'Os Meus Favoritos';
      case MainSection.recents: return 'Vistos Recentemente';
    }
  }

  void _rebuildCategories() {
    if (activeSection == MainSection.series) {
      final counts = <String, int>{'Todas': allSeriesGroups.length};
      for (final s in allSeriesGroups) {
        counts[s.group] = (counts[s.group] ?? 0) + 1;
      }
      categoryCounts = counts;
      sectionCategories = counts.keys.toList();
    } else {
      final base = _baseList(activeSection);
      final counts = <String, int>{'Todas': base.length};
      for (final i in base) {
        counts[i.group] = (counts[i.group] ?? 0) + 1;
      }
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

  Future<void> _openFullScreen(StreamItem item) async {
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
        playlist: displayedItems.isNotEmpty ? displayedItems : liveItems,
        deviceMode: _mode,
        initialStartPosition: startPos,
      )),
    );
  }

  Widget _buildMiniVideo() {
    if (_engine.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering_error_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(height: 6),
            const Text('Sinal indisponível', style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 6),
            if (_engine.currentItem != null)
              TVFocusableItem(
                autoScroll: false,
                onSelect: () => _engine.openStream(_engine.currentItem!, forceReload: true, tryHlsFallback: true),
                builder: (c, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: f ? Colors.white : const Color(0xFF00E5FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Reconectar',
                    style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final c = _engine.controller;
    if (!_engine.isReady || c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    }
    final ratio = c.value.aspectRatio > 0 ? c.value.aspectRatio : (16 / 9);
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: VideoPlayer(c),
      ),
    );
  }

  Future<void> _logoutToLogin() async {
    await _engine.stopAndClear();
    await AppStorage.clearAllData();
    if (!mounted) return;
    Navigator.pushReplacement(context, createSmoothRoute(LoginGatewayScreen(deviceMode: _mode)));
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
      onSelectSection: (s) => setState(() {
        activeSection = s;
        selectedCategory = 'Todas';
        _rebuildCategories();
      }),
      onSelectCategory: (c) => setState(() {
        selectedCategory = c;
        _filterContent();
      }),
      onSearchChanged: (v) {
        searchQuery = v;
        _filterContent();
      },
      onClearSearch: () {
        _searchCtrl.clear();
        searchQuery = '';
        _filterContent();
      },
      onStartPreview: (item) {
        if (_engine.currentItem?.id == item.id) {
          _openFullScreen(item);
        } else {
          _engine.openStream(item);
        }
      },
      onOpenFullScreen: _openFullScreen,
      onSelectSeriesGroup: (s) {},
      onToggleFavorite: _toggleFavorite,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isTV ? null : mobileView.buildDrawer(context),
      body: SafeArea(
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                    const SizedBox(height: 16),
                    Text(loadingStatus, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
              )
            : errorMessage.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.tv_off_rounded, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 14),
                          Text(
                            errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TVFocusableItem(
                                autofocus: true,
                                autoScroll: false,
                                onSelect: _bootOfflineFirstAndSync,
                                builder: (c, f) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: f ? Colors.white : const Color(0xFF00E5FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Tentar Novamente',
                                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              TVFocusableItem(
                                autoScroll: false,
                                onSelect: _logoutToLogin,
                                builder: (c, f) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: f ? Colors.white : Colors.white24),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('Corrigir Login', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                        searchController: _searchCtrl,
                        searchQuery: searchQuery,
                        onSearchChanged: (v) {
                          searchQuery = v;
                          _filterContent();
                        },
                        onClearSearch: () {
                          setState(() {
                            _searchCtrl.clear();
                            searchQuery = '';
                            _filterContent();
                          });
                        },
                        onRefreshPlaylist: _bootOfflineFirstAndSync,
                        onLogout: _logoutToLogin,
                        onSelectSection: (s) => setState(() {
                          activeSection = s;
                          selectedCategory = 'Todas';
                          isTVSideMenuOpen = false;
                          _rebuildCategories();
                        }),
                        onSelectCategory: (c) => setState(() {
                          selectedCategory = c;
                          isTVSideMenuOpen = false;
                          _filterContent();
                        }),
                        onStartPreview: (item) {
                          if (_engine.currentItem?.id == item.id) {
                            _openFullScreen(item);
                          } else {
                            _engine.openStream(item);
                          }
                        },
                        onOpenFullScreen: _openFullScreen,
                        onSelectSeriesGroup: (s) {},
                        onToggleFavorite: _toggleFavorite,
                      )
                    : mobileView,
      ),
    );
  }
}
