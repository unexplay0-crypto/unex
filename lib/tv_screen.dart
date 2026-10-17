import 'dart:async';
import 'package:flutter/material.dart';
import 'core.dart';
import 'widgets.dart';

class TVDashboardView extends StatefulWidget {
  final bool isSideMenuOpen;
  final VoidCallback onOpenSideMenu;
  final VoidCallback onCloseSideMenu;
  final MainSection activeSection;
  final String sectionTitle;
  final String selectedCategory;
  final List<String> sectionCategories;
  final Map<String, int> categoryCounts;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final Map<String, VodProgressEntry> vodProgressMap;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final Widget miniVideoWidget;
  final ValueChanged<MainSection> onSelectSection;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<StreamItem> onStartPreview;
  final ValueChanged<StreamItem> onOpenFullScreen;
  final ValueChanged<SeriesGroup> onSelectSeriesGroup;
  final ValueChanged<StreamItem> onToggleFavorite;
  final TextEditingController? searchController;
  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onClearSearch;
  final VoidCallback? onRefreshPlaylist;
  final VoidCallback? onLogout;

  const TVDashboardView({
    super.key,
    required this.isSideMenuOpen,
    required this.onOpenSideMenu,
    required this.onCloseSideMenu,
    required this.activeSection,
    required this.sectionTitle,
    required this.selectedCategory,
    required this.sectionCategories,
    required this.categoryCounts,
    required this.displayedItems,
    required this.displayedSeries,
    required this.vodProgressMap,
    required this.favoriteIds,
    required this.activeItem,
    required this.miniVideoWidget,
    required this.onSelectSection,
    required this.onSelectCategory,
    required this.onStartPreview,
    required this.onOpenFullScreen,
    required this.onSelectSeriesGroup,
    required this.onToggleFavorite,
    this.searchController,
    this.searchQuery = '',
    this.onSearchChanged,
    this.onClearSearch,
    this.onRefreshPlaylist,
    this.onLogout,
  });

  @override
  State<TVDashboardView> createState() => _TVDashboardViewState();
}

class _TVDashboardViewState extends State<TVDashboardView> {
  final FocusNode _sideMenuFocus = FocusNode();
  StreamItem? _focusedVodItem;
  SeriesGroup? _focusedSeriesGroup;
  bool _adultUnlocked = false;
  Timer? _previewDebounce;

  final Color _bgColor = const Color(0xFF090B10);
  final Color _panelColor = const Color(0xFF12151F);
  final Color _accentColor = const Color(0xFF00E5FF);

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _sideMenuFocus.dispose();
    super.dispose();
  }

  void _focusSideMenuNow() {
    if (!widget.isSideMenuOpen) widget.onOpenSideMenu();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sideMenuFocus.requestFocus();
    });
  }

  void _schedulePreviewOnFocus(StreamItem item) {
    _previewDebounce?.cancel();
    if (widget.activeItem?.id == item.id) return;
    if (item.isAdult && !_adultUnlocked) return;

    // Aguarda 650ms com o foco parado sobre o canal antes de sintonizar (evita travar a TV ao rolar a lista)
    _previewDebounce = Timer(const Duration(milliseconds: 650), () {
      if (mounted && widget.activeItem?.id != item.id) {
        widget.onStartPreview(item);
      }
    });
  }

  void _updateFocusedVod(StreamItem item) {
    if (_focusedVodItem?.id != item.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _focusedVodItem = item);
      });
    }
  }

  void _updateFocusedSeries(SeriesGroup series) {
    if (_focusedSeriesGroup?.id != series.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _focusedSeriesGroup = series);
      });
    }
  }

  // ===========================================================================
  // INTERCEPTADORES DE CONTROLE PARENTAL (+18) E SELEÇÃO
  // ===========================================================================
  Future<void> _handleChannelSelect(StreamItem item) async {
    _previewDebounce?.cancel();
    if (item.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }

    // Se já está sintonizado no preview, o OK abre a Tela Cheia; senão, sintoniza imediatamente
    if (widget.activeItem?.id == item.id) {
      widget.onOpenFullScreen(item);
    } else {
      widget.onStartPreview(item);
    }
  }

  Future<void> _handleFullScreen(StreamItem item) async {
    _previewDebounce?.cancel();
    if (item.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context);
      if (unlocked && mounted) {
        setState(() => _adultUnlocked = true);
        widget.onOpenFullScreen(item);
      }
    } else {
      widget.onOpenFullScreen(item);
    }
  }

  Future<void> _handleSeriesSelect(SeriesGroup series) async {
    if (series.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context);
      if (unlocked && mounted) {
        setState(() => _adultUnlocked = true);
        widget.onSelectSeriesGroup(series);
      }
    } else {
      widget.onSelectSeriesGroup(series);
    }
  }

  void _openSearchKeyboard() {
    if (widget.searchController == null) return;
    showTVVirtualKeyboard(
      context,
      widget.searchController!,
      'Pesquisar em ${widget.sectionTitle}',
      onChanged: widget.onSearchChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLive = widget.activeSection == MainSection.live;

    return Scaffold(
      backgroundColor: _bgColor,
      body: Row(
        children: [
          // 1. MENU LATERAL (NAVIGATION RAIL FIXO E RECOLHÍVEL)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: widget.isSideMenuOpen ? 225 : 58,
            decoration: BoxDecoration(
              color: _panelColor,
              border: Border(right: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            child: widget.isSideMenuOpen ? _buildExpandedMenu() : _buildCollapsedRail(),
          ),

          // 2. CONTEÚDO DINÂMICO (TV AO VIVO 3 COLUNAS vs VOD IMERSIVO)
          Expanded(
            child: isLive ? _buildLiveTVLayout() : _buildImmersiveVodLayout(),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LAYOUT 3 COLUNAS: TV AO VIVO (ESTILO VERTU PLAY / TIVIMATE)
  // ===========================================================================
  Widget _buildLiveTVLayout() {
    return Row(
      children: [
        // COLUNA 1: CATEGORIAS
        Container(
          width: 230,
          color: _bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CATEGORIAS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.5),
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (widget.searchController != null)
                      TVIconButton(
                        icon: Icons.search_rounded,
                        color: _accentColor,
                        size: 18,
                        onPressed: _openSearchKeyboard,
                      ),
                  ],
                ),
              ),
              if (widget.searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => widget.onClearSearch?.call(),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: f ? Colors.white : Colors.redAccent),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Busca: "${widget.searchQuery}"',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white),
                            ),
                          ),
                          const Icon(Icons.close, size: 14, color: Colors.redAccent),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: widget.sectionCategories.length,
                  itemBuilder: (context, idx) {
                    final cat = widget.sectionCategories[idx];
                    final count = widget.categoryCounts[cat] ?? 0;
                    final isSel = cat == widget.selectedCategory;
                    return TVFocusableItem(
                      autofocus: !widget.isSideMenuOpen && isSel,
                      onMoveLeft: _focusSideMenuNow,
                      onSelect: () {
                        final lower = cat.toLowerCase();
                        final isAdultCat = lower.contains('adult') || lower.contains('+18') || lower.contains('xxx');
                        if (isAdultCat && !_adultUnlocked) {
                          showParentalPinPrompt(context).then((unlocked) {
                            if (unlocked && mounted) {
                              setState(() => _adultUnlocked = true);
                              widget.onSelectCategory(cat);
                            }
                          });
                        } else {
                          widget.onSelectCategory(cat);
                        }
                      },
                      builder: (c, f) => AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSel
                              ? _accentColor.withOpacity(0.16)
                              : f
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: f ? _accentColor : (isSel ? _accentColor.withOpacity(0.4) : Colors.transparent),
                            width: f ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isSel ? _accentColor : Colors.white,
                                  fontWeight: isSel || f ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSel ? _accentColor : Colors.white38,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // COLUNA 2: GRELHA DE CANAIS
        Expanded(
          child: Container(
            color: _panelColor.withOpacity(0.4),
            child: widget.displayedItems.isEmpty
                ? const Center(
                    child: Text('Nenhum canal encontrado nesta categoria.', style: TextStyle(color: Colors.white54)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 280,
                      mainAxisExtent: 82,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: widget.displayedItems.length,
                    itemBuilder: (context, idx) {
                      final item = widget.displayedItems[idx];
                      final isPlaying = widget.activeItem?.id == item.id;

                      return TVFocusableItem(
                        onSelect: () => _handleChannelSelect(item),
                        builder: (c, f) {
                          if (f) _schedulePreviewOnFocus(item);
                          return AnimatedScale(
                            scale: f ? 1.04 : 1.0,
                            duration: const Duration(milliseconds: 120),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isPlaying ? _accentColor.withOpacity(0.16) : _panelColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: f
                                      ? _accentColor
                                      : isPlaying
                                          ? _accentColor.withOpacity(0.5)
                                          : Colors.white.withOpacity(0.05),
                                  width: f ? 2.5 : 1.2,
                                ),
                                boxShadow: f
                                    ? [BoxShadow(color: _accentColor.withOpacity(0.22), blurRadius: 10)]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  buildChannelLogo(item.logo, size: 48),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            buildQualityBadge(item.qualityTag),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                isPlaying ? '▶ OK p/ Tela Cheia' : item.group,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isPlaying ? _accentColor : Colors.white54,
                                                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),

        // COLUNA 3: DOCK DE PRÉ-VISUALIZAÇÃO (EPG + TELA CHEIA)
        Container(
          width: 310,
          decoration: BoxDecoration(
            color: _bgColor,
            border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRÉ-VISUALIZAÇÃO AO VIVO',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black,
                    child: widget.activeItem != null && widget.activeItem!.isAdult && !_adultUnlocked
                        ? const Center(child: Icon(Icons.lock_rounded, color: Colors.redAccent, size: 40))
                        : widget.miniVideoWidget,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.activeItem != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildChannelLogo(widget.activeItem!.logo, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.activeItem!.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.activeItem!.group,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _accentColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => _handleFullScreen(widget.activeItem!),
                    builder: (c, f) => AnimatedScale(
                      scale: f ? 1.04 : 1.0,
                      duration: const Duration(milliseconds: 140),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: f ? Colors.white : _accentColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: f ? [BoxShadow(color: _accentColor.withOpacity(0.4), blurRadius: 12)] : null,
                        ),
                        child: const Center(
                          child: Text(
                            'TELA CHEIA',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => widget.onToggleFavorite(widget.activeItem!),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: f ? Colors.white.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: f ? Colors.white : Colors.white24),
                      ),
                      child: Center(
                        child: Text(
                          widget.favoriteIds.contains(widget.activeItem!.id)
                              ? '★ Remover Favorito'
                              : '☆ Adicionar Favorito',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: f ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // LAYOUT IMERSIVO: FILMES E SÉRIES (ESTILO NETFLIX / MAX A 60 FPS)
  // ===========================================================================
  Widget _buildImmersiveVodLayout() {
    final isSeries = widget.activeSection == MainSection.series;
    final bgUrl = isSeries ? _focusedSeriesGroup?.logo : _focusedVodItem?.logo;
    final title = isSeries
        ? (_focusedSeriesGroup?.title ?? widget.sectionTitle)
        : (_focusedVodItem?.name ?? widget.sectionTitle);
    final synopsis = isSeries
        ? (_focusedSeriesGroup?.synopsis ?? 'Selecione uma série abaixo para ver as temporadas e episódios.')
        : (_focusedVodItem?.synopsis ?? 'Navegue pelos pôsteres abaixo para explorar o catálogo.');
    final badge = isSeries ? _focusedSeriesGroup?.qualityTag : _focusedVodItem?.qualityTag;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. BACKGROUND OTIMIZADO DE ALTA PERFORMANCE
        if (bgUrl != null && bgUrl.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.72,
            child: Image.network(
              bgUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: 600,
              errorBuilder: (_, __, ___) => Container(color: _bgColor),
            ),
          ),

        // Gradiente Escuro (Vignette) para leitura cristalina a 3 metros
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgColor.withOpacity(0.25), _bgColor.withOpacity(0.85), _bgColor],
              stops: const [0.0, 0.45, 0.82],
            ),
          ),
        ),

        // 2. CONTEÚDO (FILTRO DE GÊNEROS + HERO BANNER + CARROSSEL)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Barra Superior de Gêneros e Pesquisa
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              child: SizedBox(
                height: 38,
                child: Row(
                  children: [
                    if (widget.searchController != null) ...[
                      TVFocusableItem(
                        autoScroll: false,
                        onMoveLeft: _focusSideMenuNow,
                        onSelect: _openSearchKeyboard,
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: f ? _accentColor : _panelColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: f ? Colors.white : Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 16, color: f ? Colors.black : _accentColor),
                              const SizedBox(width: 6),
                              Text(
                                widget.searchQuery.isEmpty ? 'Pesquisar' : '"${widget.searchQuery}"',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: f ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.sectionCategories.length,
                        itemBuilder: (context, idx) {
                          final cat = widget.sectionCategories[idx];
                          final isSel = cat == widget.selectedCategory;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TVFocusableItem(
                              autoScroll: false,
                              onSelect: () => widget.onSelectCategory(cat),
                              builder: (c, f) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? _accentColor
                                      : f
                                          ? Colors.white24
                                          : _panelColor.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: f ? Colors.white : Colors.white12),
                                ),
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSel ? Colors.black : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hero Banner Central
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 16, 36, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (badge != null) buildQualityBadge(badge),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 650,
                      child: Text(
                        synopsis,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.75),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),

            // 3. CARROSSEL DE PÔSTERES
            SizedBox(
              height: 265,
              child: isSeries
                  ? ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
                      itemCount: widget.displayedSeries.length,
                      itemBuilder: (context, idx) {
                        final s = widget.displayedSeries[idx];
                        return TVFocusableItem(
                          autofocus: idx == 0 && !widget.isSideMenuOpen,
                          onMoveLeft: idx == 0 ? _focusSideMenuNow : null,
                          onSelect: () => _handleSeriesSelect(s),
                          builder: (c, f) {
                            if (f) _updateFocusedSeries(s);
                            return Padding(
                              padding: const EdgeInsets.only(right: 18),
                              child: AspectRatio(
                                aspectRatio: 0.68,
                                child: buildStreamingPosterCard(
                                  title: s.title,
                                  subtitle: s.group,
                                  logoUrl: s.logo,
                                  badgeText: s.qualityTag,
                                  isFocused: f,
                                  onTap: () => _handleSeriesSelect(s),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
                      itemCount: widget.displayedItems.length,
                      itemBuilder: (context, idx) {
                        final item = widget.displayedItems[idx];
                        final isFav = widget.favoriteIds.contains(item.id);
                        final prog = widget.vodProgressMap[item.id];
                        return TVFocusableItem(
                          autofocus: idx == 0 && !widget.isSideMenuOpen,
                          onMoveLeft: idx == 0 ? _focusSideMenuNow : null,
                          onSelect: () => _handleFullScreen(item),
                          builder: (c, f) {
                            if (f) _updateFocusedVod(item);
                            return Padding(
                              padding: const EdgeInsets.only(right: 18),
                              child: AspectRatio(
                                aspectRatio: 0.68,
                                child: buildStreamingPosterCard(
                                  title: item.name,
                                  subtitle: item.group,
                                  logoUrl: item.logo,
                                  badgeText: item.qualityTag,
                                  isFocused: f,
                                  isFavorite: isFav,
                                  progress: prog?.progress,
                                  onTap: () => _handleFullScreen(item),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // MENU PRINCIPAL LATERAL (RECOLHIDO vs EXPANDIDO)
  // ===========================================================================
  Widget _buildCollapsedRail() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.play_circle_fill_rounded, color: _accentColor, size: 28),
        const SizedBox(height: 24),
        _buildRailIcon(Icons.live_tv_rounded, MainSection.live),
        _buildRailIcon(Icons.movie_creation_rounded, MainSection.movie),
        _buildRailIcon(Icons.video_library_rounded, MainSection.series),
        _buildRailIcon(Icons.history_toggle_off_rounded, MainSection.continueWatching),
        _buildRailIcon(Icons.star_rounded, MainSection.favorites),
      ],
    );
  }

  Widget _buildRailIcon(IconData icon, MainSection sec) {
    final sel = widget.activeSection == sec;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TVFocusableItem(
        autoScroll: false,
        onSelect: _focusSideMenuNow,
        builder: (c, f) {
          if (f) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _focusSideMenuNow());
          }
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sel ? _accentColor.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: sel ? _accentColor : Colors.white54),
          );
        },
      ),
    );
  }

  Widget _buildExpandedMenu() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 20),
          child: Text(
            'UNEX VISION',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _accentColor,
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _buildNav('TV ao Vivo', MainSection.live, Icons.live_tv_rounded),
        _buildNav('Filmes', MainSection.movie, Icons.movie_creation_rounded),
        _buildNav('Séries', MainSection.series, Icons.video_library_rounded),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(color: Colors.white10),
        ),
        _buildNav('Continuar a Ver', MainSection.continueWatching, Icons.play_circle_filled_rounded),
        _buildNav('Os Meus Favoritos', MainSection.favorites, Icons.star_rounded),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(color: Colors.white10),
        ),
        if (widget.onRefreshPlaylist != null)
          TVFocusableItem(
            onMoveRight: widget.onCloseSideMenu,
            onSelect: () {
              widget.onCloseSideMenu();
              widget.onRefreshPlaylist!();
            },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: f ? Colors.white.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.refresh_rounded, size: 20, color: Colors.white70),
                  SizedBox(width: 14),
                  Text('Atualizar Lista', style: TextStyle(fontSize: 13, color: Colors.white)),
                ],
              ),
            ),
          ),
        if (widget.onLogout != null)
          TVFocusableItem(
            onMoveRight: widget.onCloseSideMenu,
            onSelect: widget.onLogout!,
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: f ? Colors.redAccent.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
                  SizedBox(width: 14),
                  Text('Trocar Conta', style: TextStyle(fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNav(String label, MainSection section, IconData icon) {
    final sel = widget.activeSection == section;
    return TVFocusableItem(
      focusNode: sel ? _sideMenuFocus : null,
      autofocus: sel,
      onMoveRight: widget.onCloseSideMenu,
      onSelect: () => widget.onSelectSection(section),
      builder: (c, f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: sel ? _accentColor : (f ? Colors.white.withOpacity(0.08) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: sel ? Colors.black : Colors.white70),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: sel ? Colors.black : Colors.white,
                  fontWeight: sel ? FontWeight.w900 : FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
