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

  void _focusSideMenuNow() {
    if (!widget.isSideMenuOpen) widget.onOpenSideMenu();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _sideMenuFocus.requestFocus(); });
  }

  @override
  Widget build(BuildContext context) {
    final isSeries = widget.activeSection == MainSection.series;
    
    return Row(
      children: [
        // MENU LATERAL ANIMADO
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.isSideMenuOpen ? 215 : 18,
          decoration: const BoxDecoration(color: Color(0xFF0A0C12), border: Border(right: BorderSide(color: Colors.white10))),
          child: widget.isSideMenuOpen ? _buildMenu() : _buildEdgeSensor(),
        ),

        // COLUNA DE GÊNEROS
        Container(
          width: 215,
          decoration: const BoxDecoration(color: Color(0xFF0D0F17), border: Border(right: BorderSide(color: Colors.white10))),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: widget.sectionCategories.length,
            itemBuilder: (context, idx) {
              final cat = widget.sectionCategories[idx];
              final isSel = cat == widget.selectedCategory;
              return TVFocusableItem(
                autofocus: !widget.isSideMenuOpen && isSel,
                onMoveLeft: _focusSideMenuNow,
                onSelect: () => widget.onSelectCategory(cat),
                builder: (c, f) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 2), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFF00E5FF).withOpacity(0.2) : f ? Colors.white10 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.transparent),
                  ),
                  child: Text(cat, style: TextStyle(fontSize: 12, fontWeight: isSel || f ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            },
          ),
        ),

        // ÁREA CENTRAL + PREVIEW
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: isSeries ? _buildSeriesGrid() : _buildContentGrid(),
              ),
              if (!isSeries)
                Container(
                  width: 290,
                  decoration: const BoxDecoration(color: Color(0xFF0A0C12), border: Border(left: BorderSide(color: Colors.white10))),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PRÉ-VISUALIZAÇÃO', style: TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      AspectRatio(aspectRatio: 16/9, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Container(color: Colors.black, child: widget.miniVideoWidget))),
                      const SizedBox(height: 12),
                      if (widget.activeItem != null) ...[
                        Text(widget.activeItem!.name, maxLines: 2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(widget.activeItem!.group, style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          child: TVFocusableItem(
                            onSelect: () => widget.onOpenFullScreen(widget.activeItem!),
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]), borderRadius: BorderRadius.circular(10), border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2)),
                              child: const Center(child: Text('TELA CHEIA', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                            ),
                          ),
                        )
                      ]
                    ],
                  ),
                ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSeriesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 165, mainAxisExtent: 245, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: widget.displayedSeries.length,
      itemBuilder: (context, idx) {
        final s = widget.displayedSeries[idx];
        return TVFocusableItem(
          onMoveLeft: widget.isSideMenuOpen && idx == 0 ? _focusSideMenuNow : null,
          onSelect: () => widget.onSelectSeriesGroup(s),
          builder: (c, f) => buildStreamingPosterCard(title: s.title, subtitle: '${s.totalSeasons} Temp', logoUrl: s.logo, badgeText: s.qualityTag, isFocused: f, onTap: () => widget.onSelectSeriesGroup(s)),
        );
      },
    );
  }

    Widget _buildContentGrid() {
    final isMovie = widget.activeSection == MainSection.movie || widget.activeSection == MainSection.continueWatching;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: isMovie ? 165 : 245, mainAxisExtent: isMovie ? 245 : 88, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: widget.displayedItems.length,
      itemBuilder: (context, idx) {
        final item = widget.displayedItems[idx];
        final isPlaying = widget.activeItem?.id == item.id;
        final isFav = widget.favoriteIds.contains(item.id);
        
        return TVFocusableItem(
          onMoveLeft: widget.isSideMenuOpen && idx == 0 ? _focusSideMenuNow : null,
          // Garante que ao focar ou selecionar na TV, o stream da pré-visualização seja acionado
          onSelect: () => widget.onStartPreview(item),
          builder: (c, f) {
            // Se o item ganhou foco na TV, atualiza a pré-visualização automaticamente em tempo real!
            if (f && widget.activeItem?.id != item.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onStartPreview(item);
              });
            }
            return isMovie 
              ? buildStreamingPosterCard(title: item.name, subtitle: isPlaying ? 'Assistindo' : item.group, logoUrl: item.logo, badgeText: item.qualityTag, isFocused: f, isPlaying: isPlaying, isFavorite: isFav, onTap: () => widget.onStartPreview(item))
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 150), padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: isPlaying ? const Color(0xFF172238) : const Color(0xFF12151F), borderRadius: BorderRadius.circular(12), border: Border.all(color: f ? const Color(0xFF00E5FF) : isPlaying ? const Color(0xFF2979FF) : Colors.white10, width: f ? 2 : 1)),
                  child: Row(children: [ buildChannelLogo(item.logo, size: 44), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [ Text(item.name, maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), Text(item.group, maxLines: 1, style: const TextStyle(fontSize: 10, color: Colors.white54)) ])) ]),
                );
          },
        );
      },
    );
    }
  

  Widget _buildMenu() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('UNEX VISION', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)))),
        const Divider(color: Colors.white10),
        _buildNav('TV ao Vivo', MainSection.live, Icons.tv),
        _buildNav('Filmes', MainSection.movie, Icons.movie),
        _buildNav('Séries', MainSection.series, Icons.video_library),
        const Divider(color: Colors.white10),
        _buildNav('Continuar', MainSection.continueWatching, Icons.play_circle),
        _buildNav('Favoritos', MainSection.favorites, Icons.star),
      ],
    );
  }

  Widget _buildNav(String label, MainSection section, IconData icon) {
    final sel = widget.activeSection == section;
    return TVFocusableItem(
      focusNode: sel ? _sideMenuFocus : null, autofocus: sel,
      onMoveRight: widget.onCloseSideMenu, onSelect: () => widget.onSelectSection(section),
      builder: (c, f) => Container(
        padding: const EdgeInsets.all(10), margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(color: sel ? const Color(0xFF00E5FF) : f ? Colors.white10 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [ Icon(icon, size: 18, color: sel ? Colors.black : Colors.white), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 12, color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.bold)) ]),
      ),
    );
  }

  Widget _buildEdgeSensor() => TVFocusableItem(onSelect: _focusSideMenuNow, builder: (c, f) { if(f) WidgetsBinding.instance.addPostFrameCallback((_) => _focusSideMenuNow()); return Center(child: Container(width: 4, height: 70, color: const Color(0xFF00E5FF).withOpacity(0.5))); });
}
