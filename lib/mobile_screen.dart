import 'package:flutter/material.dart';
import 'core.dart';
import 'widgets.dart';

class MobileDashboardView extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final MainSection activeSection;
  final String sectionTitle;
  final String selectedCategory;
  final List<String> sectionCategories;
  final Map<String, int> categoryCounts;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final List<VodProgressEntry> continueWatchingEntries;
  final Map<String, VodProgressEntry> vodProgressMap;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final EpgProgramInfo? activeEpg;
  final Widget miniVideoWidget;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<MainSection> onSelectSection;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<StreamItem> onStartPreview;
  final ValueChanged<StreamItem> onOpenFullScreen;
  final ValueChanged<SeriesGroup> onSelectSeriesGroup;
  final ValueChanged<StreamItem> onToggleFavorite;

  const MobileDashboardView({
    super.key, required this.scaffoldKey, required this.activeSection,
    required this.sectionTitle, required this.selectedCategory,
    required this.sectionCategories, required this.categoryCounts,
    required this.displayedItems, required this.displayedSeries,
    required this.continueWatchingEntries, required this.vodProgressMap,
    required this.favoriteIds, required this.activeItem, required this.activeEpg,
    required this.miniVideoWidget, required this.searchController,
    required this.searchQuery, required this.onSelectSection,
    required this.onSelectCategory, required this.onSearchChanged,
    required this.onClearSearch, required this.onStartPreview,
    required this.onOpenFullScreen, required this.onSelectSeriesGroup,
    required this.onToggleFavorite,
  });

  Widget buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF090B10),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('UNEX VISION', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF), letterSpacing: 1.5)),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                children: [
                  _buildDrawerItem(context, 'TV ao Vivo', MainSection.live, Icons.live_tv_rounded),
                  _buildDrawerItem(context, 'Filmes', MainSection.movie, Icons.movie_creation_rounded),
                  _buildDrawerItem(context, 'Séries', MainSection.series, Icons.video_library_rounded),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10)),
                  _buildDrawerItem(context, 'Continuar a Ver', MainSection.continueWatching, Icons.play_circle_filled_rounded),
                  _buildDrawerItem(context, 'Os Meus Favoritos', MainSection.favorites, Icons.star_rounded),
                  _buildDrawerItem(context, 'Recentes', MainSection.recents, Icons.history_rounded),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, String title, MainSection section, IconData icon) {
    final sel = activeSection == section;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFF00E5FF).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sel ? const Color(0xFF00E5FF).withOpacity(0.5) : Colors.transparent),
      ),
      child: ListTile(
        leading: Icon(icon, color: sel ? const Color(0xFF00E5FF) : Colors.white70),
        title: Text(title, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.w900 : FontWeight.bold, fontSize: 14)),
        onTap: () { Navigator.pop(context); onSelectSection(section); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSeries = activeSection == MainSection.series;
    final isMovie = activeSection == MainSection.movie || activeSection == MainSection.continueWatching;

    return Column(
      children: [
        // 1. BARRA SUPERIOR
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: const Color(0xFF0D1018),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.menu_rounded, color: Color(0xFF00E5FF)), onPressed: () => scaffoldKey.currentState?.openDrawer()),
              Expanded(child: Text(sectionTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            ],
          ),
        ),

        // 2. PRÉ-VISUALIZAÇÃO DE VÍDEO NO TOPO
        if (activeItem != null && !isSeries)
          GestureDetector(
            onTap: () => onOpenFullScreen(activeItem!),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black, child: miniVideoWidget),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(activeItem!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                if (activeEpg != null && activeItem!.type == ContentType.live)
                                  Text('Agora: ${activeEpg!.nowTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(8)),
                            child: const Row(
                              children: [
                                Icon(Icons.fullscreen_rounded, color: Colors.black, size: 18),
                                SizedBox(width: 4),
                                Text('Tela Cheia', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),

        // 3. BARRA DE PESQUISA
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 46, padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: const Color(0xFF12151F), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
                  child: TextField(
                    controller: searchController, onChanged: onSearchChanged,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar em $sectionTitle...', 
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.normal), 
                      border: InputBorder.none, 
                      icon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 20), 
                      suffixIcon: searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClearSearch) : null
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 4. CARROSSEL HORIZONTAL DE GÉNEROS
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: sectionCategories.length,
            itemBuilder: (context, idx) {
              final cat = sectionCategories[idx];
              final isSel = cat == selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat), selected: isSel, onSelected: (_) => onSelectCategory(cat),
                  selectedColor: const Color(0xFF00E5FF), backgroundColor: const Color(0xFF12151F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70, fontWeight: isSel ? FontWeight.w900 : FontWeight.bold, fontSize: 12),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // 5. GRELHA DE CONTEÚDO (MÓVEL)
        Expanded(
          child: isSeries
              ? GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
                  itemCount: displayedSeries.length,
                  itemBuilder: (ctx, idx) {
                    final s = displayedSeries[idx];
                    return GestureDetector(
                      onTap: () => onSelectSeriesGroup(s),
                      child: buildStreamingPosterCard(title: s.title, subtitle: '${s.totalSeasons} Temp', logoUrl: s.logo, badgeText: s.qualityTag, onTap: () => onSelectSeriesGroup(s)),
                    );
                  },
                )
              : isMovie
                  ? GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      itemCount: displayedItems.length,
                      itemBuilder: (ctx, idx) {
                        final i = displayedItems[idx];
                        final isFav = favoriteIds.contains(i.id);
                        final isPlaying = activeItem?.id == i.id;
                        final prog = vodProgressMap[i.id];
                        return GestureDetector(
                          onTap: () => onStartPreview(i),
                          child: buildStreamingPosterCard(title: i.name, subtitle: isPlaying ? 'A assistir' : i.group, logoUrl: i.logo, badgeText: i.qualityTag, isPlaying: isPlaying, isFavorite: isFav, progress: prog?.progress, onFavoriteTap: () => onToggleFavorite(i), onTap: () => onStartPreview(i)),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: displayedItems.length,
                      itemBuilder: (ctx, idx) {
                        final i = displayedItems[idx];
                        final isPlaying = activeItem?.id == i.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isPlaying ? const Color(0xFF00E5FF).withOpacity(0.15) : const Color(0xFF12151F), 
                            borderRadius: BorderRadius.circular(12), 
                            border: Border.all(color: isPlaying ? const Color(0xFF00E5FF) : Colors.white10)
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            onTap: () => onStartPreview(i),
                            leading: buildChannelLogo(i.logo, size: 48),
                            title: Text(i.name, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: isPlaying ? FontWeight.w900 : FontWeight.bold, color: isPlaying ? const Color(0xFF00E5FF) : Colors.white)),
                            subtitle: Text(isPlaying ? 'A reproduzir' : i.group, maxLines: 1, style: TextStyle(fontSize: 11, color: isPlaying ? const Color(0xFF00E5FF) : Colors.white54)),
                            trailing: IconButton(icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFF00E5FF)), onPressed: () => onOpenFullScreen(i)),
                          ),
                        );
                      },
                    ),
        )
      ],
    );
  }
}
