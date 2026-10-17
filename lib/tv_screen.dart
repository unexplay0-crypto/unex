import 'dart:ui';
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

  const TVDashboardView({
    super.key, required this.isSideMenuOpen, required this.onOpenSideMenu, required this.onCloseSideMenu,
    required this.activeSection, required this.sectionTitle, required this.selectedCategory,
    required this.sectionCategories, required this.categoryCounts, required this.displayedItems,
    required this.displayedSeries, required this.vodProgressMap, required this.favoriteIds,
    required this.activeItem, required this.miniVideoWidget, required this.onSelectSection,
    required this.onSelectCategory, required this.onStartPreview, required this.onOpenFullScreen,
    required this.onSelectSeriesGroup, required this.onToggleFavorite,
  });

  @override
  State<TVDashboardView> createState() => _TVDashboardViewState();
}

class _TVDashboardViewState extends State<TVDashboardView> {
  final FocusNode _sideMenuFocus = FocusNode();
  StreamItem? _focusedVodItem;
  SeriesGroup? _focusedSeriesGroup;

  // Paleta estilo Vertu Play
  final Color _bgColor = const Color(0xFF0B0914);
  final Color _panelColor = const Color(0xFF151124);
  final Color _accentColor = const Color(0xFF00E5FF);

  void _focusSideMenuNow() {
    if (!widget.isSideMenuOpen) widget.onOpenSideMenu();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _sideMenuFocus.requestFocus(); });
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

  @override
  Widget build(BuildContext context) {
    final isLive = widget.activeSection == MainSection.live;
    
    return Row(
      children: [
        // 1. MENU LATERAL DE SECÇÕES (FICA RECOLHIDO COMO SENSOR)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.isSideMenuOpen ? 220 : 18,
          decoration: BoxDecoration(color: _bgColor, border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05)))),
          child: widget.isSideMenuOpen ? _buildMenu() : _buildEdgeSensor(),
        ),

        // 2. ÁREA DE CONTEÚDO (MUDANÇA DINÂMICA ENTRE 3 COLUNAS OU IMERSIVO)
        Expanded(
          child: isLive ? _buildLiveTVLayout() : _buildImmersiveVodLayout(),
        )
      ],
    );
  }

  // ===========================================================================
  // LAYOUT 3 COLUNAS: TV AO VIVO (VERTU PLAY STYLE)
  // ===========================================================================
  Widget _buildLiveTVLayout() {
    return Row(
      children: [
        // COLUNA 1: CATEGORIAS
        Container(
          width: 220,
          color: _panelColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Text('CATEGORIAS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5), letterSpacing: 1.2)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.sectionCategories.length,
                  itemBuilder: (context, idx) {
                    final cat = widget.sectionCategories[idx];
                    final isSel = cat == widget.selectedCategory;
                    return TVFocusableItem(
                      autofocus: !widget.isSideMenuOpen && isSel,
                      onMoveLeft: _focusSideMenuNow,
                      onSelect: () => widget.onSelectCategory(cat),
                      builder: (c, f) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSel ? _accentColor.withOpacity(0.15) : f ? Colors.white.withOpacity(0.05) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: f ? _accentColor : Colors.transparent, width: f ? 2 : 1),
                        ),
                        child: Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isSel ? _accentColor : Colors.white, fontWeight: isSel || f ? FontWeight.bold : FontWeight.normal)),
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
            color: _bgColor,
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisExtent: 80, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: widget.displayedItems.length,
              itemBuilder: (context, idx) {
                final item = widget.displayedItems[idx];
                final isPlaying = widget.activeItem?.id == item.id;
                
                return TVFocusableItem(
                  onSelect: () => widget.onStartPreview(item),
                  builder: (c, f) {
                    if (f && widget.activeItem?.id != item.id) {
                      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) widget.onStartPreview(item); });
                    }
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPlaying ? _accentColor.withOpacity(0.1) : _panelColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: f ? _accentColor : isPlaying ? _accentColor.withOpacity(0.5) : Colors.white.withOpacity(0.05), width: f ? 2 : 1),
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
                                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(isPlaying ? 'A reproduzir' : item.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isPlaying ? _accentColor : Colors.white54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),

        // COLUNA 3: PRÉ-VISUALIZAÇÃO E EPG
        Container(
          width: 320,
          decoration: BoxDecoration(color: _panelColor, border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05)))),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PRÉ-VISUALIZAÇÃO', style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16/9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(color: Colors.black, child: widget.miniVideoWidget),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.activeItem != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildChannelLogo(widget.activeItem!.logo, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.activeItem!.name, maxLines: 2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(widget.activeItem!.group, style: TextStyle(fontSize: 12, color: _accentColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    onSelect: () => widget.onOpenFullScreen(widget.activeItem!),
                    builder: (c, f) => AnimatedScale(
                      scale: f ? 1.05 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: f ? Colors.white : _accentColor, borderRadius: BorderRadius.circular(12), boxShadow: f ? [BoxShadow(color: _accentColor.withOpacity(0.4), blurRadius: 12)] : null),
                        child: const Center(child: Text('TELA CHEIA', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.2))),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    onSelect: () => widget.onToggleFavorite(widget.activeItem!),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: f ? _accentColor : Colors.white24)),
                      child: Center(child: Text(widget.favoriteIds.contains(widget.activeItem!.id) ? '★ Remover Favorito' : '☆ Adicionar Favorito', style: const TextStyle(fontSize: 12))),
                    ),
                  ),
                ),
              ]
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // LAYOUT IMERSIVO: FILMES E SÉRIES (VERTU PLAY STYLE)
  // ===========================================================================
  Widget _buildImmersiveVodLayout() {
    final isSeries = widget.activeSection == MainSection.series;
    final bgUrl = isSeries ? _focusedSeriesGroup?.logo : _focusedVodItem?.logo;
    final title = isSeries ? _focusedSeriesGroup?.title : _focusedVodItem?.name;
    final synopsis = isSeries ? 'Selecione para explorar as temporadas e episódios desta série.' : _focusedVodItem?.synopsis;
    final badge = isSeries ? _focusedSeriesGroup?.qualityTag : _focusedVodItem?.qualityTag;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. BACKGROUND COM EFEITO BLUR E GRADIENTE
        if (bgUrl != null && bgUrl.isNotEmpty)
          Image.network(bgUrl, fit: BoxFit.cover, cacheWidth: 600, errorBuilder: (_,__,___) => Container(color: _bgColor)),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [_bgColor.withOpacity(0.6), _bgColor.withOpacity(0.9), _bgColor],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),

        // 2. CONTEÚDO (METADADOS NO TOPO + CARROSSEL NA BASE)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (badge != null) buildQualityBadge(badge),
                    const SizedBox(height: 12),
                    Text(title ?? 'A carregar...', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, height: 1.1)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 600,
                      child: Text(synopsis ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.7), height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),

            // 3. LISTA HORIZONTAL (CARROSSEL)
            SizedBox(
              height: 280,
              child: isSeries
                  ? ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                      itemCount: widget.displayedSeries.length,
                      itemBuilder: (context, idx) {
                        final s = widget.displayedSeries[idx];
                        return TVFocusableItem(
                          onMoveLeft: widget.isSideMenuOpen && idx == 0 ? _focusSideMenuNow : null,
                          onSelect: () => widget.onSelectSeriesGroup(s),
                          builder: (c, f) {
                            if (f) _updateFocusedSeries(s);
                            return Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: AspectRatio(
                                aspectRatio: 0.68,
                                child: buildStreamingPosterCard(title: s.title, subtitle: '${s.totalSeasons} Temporadas', logoUrl: s.logo, badgeText: s.qualityTag, isFocused: f, onTap: () => widget.onSelectSeriesGroup(s)),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                      itemCount: widget.displayedItems.length,
                      itemBuilder: (context, idx) {
                        final item = widget.displayedItems[idx];
                        final isFav = widget.favoriteIds.contains(item.id);
                        final prog = widget.vodProgressMap[item.id];
                        return TVFocusableItem(
                          onMoveLeft: widget.isSideMenuOpen && idx == 0 ? _focusSideMenuNow : null,
                          onSelect: () => widget.onStartPreview(item),
                          builder: (c, f) {
                            if (f) _updateFocusedVod(item);
                            return Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: AspectRatio(
                                aspectRatio: 0.68,
                                child: buildStreamingPosterCard(title: item.name, subtitle: item.group, logoUrl: item.logo, badgeText: item.qualityTag, isFocused: f, isFavorite: isFav, progress: prog?.progress, onTap: () => widget.onStartPreview(item)),
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
  // MENU PRINCIPAL (SIDEBAR)
  // ===========================================================================
  Widget _buildMenu() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('UNEX VISION', style: TextStyle(fontWeight: FontWeight.w900, color: _accentColor, fontSize: 16, letterSpacing: 1.5))),
        const SizedBox(height: 10),
        _buildNav('TV ao Vivo', MainSection.live, Icons.tv_rounded),
        _buildNav('Filmes', MainSection.movie, Icons.movie_creation_rounded),
        _buildNav('Séries', MainSection.series, Icons.video_library_rounded),
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white10)),
        _buildNav('Continuar a Ver', MainSection.continueWatching, Icons.play_circle_filled_rounded),
        _buildNav('Os Meus Favoritos', MainSection.favorites, Icons.star_rounded),
      ],
    );
  }

  Widget _buildNav(String label, MainSection section, IconData icon) {
    final sel = widget.activeSection == section;
    return TVFocusableItem(
      focusNode: sel ? _sideMenuFocus : null, autofocus: sel,
      onMoveRight: widget.onCloseSideMenu, onSelect: () => widget.onSelectSection(section),
      builder: (c, f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: sel ? _accentColor : f ? Colors.white.withOpacity(0.05) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [ Icon(icon, size: 20, color: sel ? Colors.black : Colors.white70), const SizedBox(width: 12), Text(label, style: TextStyle(fontSize: 13, color: sel ? Colors.black : Colors.white, fontWeight: sel ? FontWeight.bold : FontWeight.normal)) ]),
      ),
    );
  }

  Widget _buildEdgeSensor() => TVFocusableItem(
    onSelect: _focusSideMenuNow, 
    builder: (c, f) { 
      if(f) WidgetsBinding.instance.addPostFrameCallback((_) => _focusSideMenuNow()); 
      return Center(child: Container(width: 4, height: 80, decoration: BoxDecoration(color: _accentColor.withOpacity(0.6), borderRadius: BorderRadius.circular(4)))); 
    }
  );
}
