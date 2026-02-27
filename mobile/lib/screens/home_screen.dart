import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/hero_slider.dart';
import '../widgets/content_section.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/movie_detail_modal.dart';
import '../widgets/series_detail_modal.dart';
import '../providers/providers.dart';
import '../services/proxy_server.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  List<HeroItem> _heroItems = [];
  List<Contenido> _catalog = [];
  bool _isLoading = true;
  double _appBarOpacity = 0.0;
  
  // Navigation State
  String _currentSection = 'Inicio';

  // Favorites State
  Set<String> _favorites = {};

  // Search State
  bool _isSearchActive = false;
  String _searchQuery = '';
  List<Contenido> _searchResults = [];

  // Drawer status
  bool _isDrawerOpen = false;

  // Scroll-to-top visibility
  bool _showScrollToTop = false;

  // Grid scroll controller for non-home sections
  final ScrollController _gridScrollController = ScrollController();

  // Debouncer class
  final Debouncer _debouncer = Debouncer(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _loadData();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.username != null) {
        LocalProxyServer.start(authProvider.username!);
      }
    });

    _scrollController.addListener(_onScroll);
    _gridScrollController.addListener(_onGridScroll);
    _searchController.addListener(_onSearchChanged);
  }

  void _onScroll() {
    double offset = _scrollController.offset;
    double newOpacity = (offset / 200).clamp(0.0, 1.0);
    bool shouldShowScrollTop = offset > 300;
    if (newOpacity != _appBarOpacity || shouldShowScrollTop != _showScrollToTop) {
      setState(() {
        _appBarOpacity = newOpacity;
        _showScrollToTop = shouldShowScrollTop;
      });
    }
  }

  void _onGridScroll() {
    bool shouldShow = _gridScrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
  }

  void _onSearchChanged() {
    _debouncer.run(() {
      final query = _searchController.text;
      if (query != _searchQuery) {
        setState(() {
          _searchQuery = query;
          if (query.isNotEmpty) {
             // Filter catalog
             _searchResults = _catalog.where((item) => 
               item.titulo.toLowerCase().contains(query.toLowerCase()) || 
               item.genero.any((g) => g.toLowerCase().contains(query.toLowerCase()))
             ).toList().reversed.toList();
          } else {
            _searchResults = [];
          }
        });
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (!_isSearchActive) {
        _searchController.clear(); // Clear closes search results and resumes Hero
        FocusScope.of(context).unfocus();
        setState(() {
          _searchQuery = '';
          _searchResults = [];
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _gridScrollController.dispose();
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final heroData = await ApiService().fetchHeroData();
      final catalogData = await ApiService().fetchCatalog();
      _loadFavorites(); // Start loading favorites
      
      if (mounted) {
        Provider.of<NotificationProvider>(context, listen: false).fetchNotifications();
      }

      if (mounted) {
        setState(() {
          _heroItems = heroData;
          _catalog = catalogData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading home data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFavorites() async {
    final token = await ApiService().getToken();
    if (token != null) {
      final favs = await ApiService().getFavorites(token);
      if (mounted) {
        setState(() {
          _favorites = favs.map((e) => e['movie_tmdb_id'].toString()).toSet();
        });
      }
    }
  }

  Future<void> _toggleFavorite(Contenido item) async {
    final token = await ApiService().getToken();
    if (token == null) return;

    final id = item.tmdbId.toString();
    final isFav = _favorites.contains(id);

    // Optimistic Update
    setState(() {
      if (isFav) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
    });

    final success = isFav 
        ? await ApiService().removeFavorite(token, item.tmdbId)
        : await ApiService().addFavorite(token, item);

    if (!success && mounted) {
      // Revert if failed
      setState(() {
        if (isFav) {
          _favorites.add(id);
        } else {
          _favorites.remove(id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar favoritos')),
      );
    }
  }

  void _onMenuChange(String section) {
    setState(() {
      _currentSection = section;
      _isSearchActive = false;
      _searchQuery = '';
      _searchResults = [];
      _showScrollToTop = false;
    });
    // Reset scroll positions
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_gridScrollController.hasClients) {
      _gridScrollController.jumpTo(0);
    }
  }

  List<Contenido> _filterByGenre(String genre) {
    if (genre == 'Recién agregadas') {
      return _catalog.reversed.take(8).toList();
    }
    final key = genre.toLowerCase();
    return _catalog
        .where((item) => item.genero.any((g) => g.toLowerCase() == key))
        .toList()
        .reversed
        .take(8)
        .toList();
  }

  List<Contenido> _getAllByGenre(String genre) {
    final key = genre.toLowerCase();
    return _catalog
        .where((item) => item.genero.any((g) => g.toLowerCase() == key))
        .toList()
        .reversed
        .toList();
  }

  // Filter helper for Grid
  List<Contenido> _getSectionItems(String section) {
    if (section == 'Series') {
      return _catalog.where((item) => item.tipo == 'Serie').toList().reversed.toList();
    } else if (section == 'Películas') {
      return _catalog.where((item) => item.tipo == 'Película').toList().reversed.toList();
    }
    return [];
  }

  void _openDetailModal(Contenido item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        if (item.esSerie) {
          return SeriesDetailModal(
            item: item,
            isFavorite: _favorites.contains(item.tmdbId.toString()),
            onToggleFavorite: () => _toggleFavorite(item),
            similarItems: _catalog,
          );
        } else {
          return MovieDetailModal(
            item: item,
            onPlay: () {}, // Handled directly inside modal now
            isFavorite: _favorites.contains(item.tmdbId.toString()),
            onToggleFavorite: () => _toggleFavorite(item),
            similarItems: _catalog,
          );
        }
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    // ... (rest of build method remains same, no changes needed here actually)
    // If search has text, show results. Else show current section content.
    final bool showSearchResults = _searchQuery.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Color(0xFF0E0E0E),
      drawer: CustomDrawer(),
      onDrawerChanged: (isOpened) => setState(() => _isDrawerOpen = isOpened),
      floatingActionButton: _showScrollToTop && !_isDrawerOpen
        ? FloatingActionButton(
            mini: true,
            backgroundColor: Color(0xFFD30000),
            onPressed: () {
              if (_currentSection == 'Inicio') {
                _scrollController.animateTo(0, duration: Duration(milliseconds: 500), curve: Curves.easeInOut);
              } else {
                _gridScrollController.animateTo(0, duration: Duration(milliseconds: 500), curve: Curves.easeInOut);
              }
              setState(() => _showScrollToTop = false);
            },
            child: Icon(Icons.keyboard_arrow_up, color: Colors.white),
          )
        : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFFD30000)))
          : Stack(
              children: [
                // Content Layer
                if (showSearchResults)
                  _buildSearchResults()
                else
                  _buildSectionContent(),

                // Custom Sticky AppBar Layer
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Color(0xFF0E0E0E).withOpacity(
                        (showSearchResults || _currentSection != 'Inicio') ? 1.0 : _appBarOpacity),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Bar: Logo, Search, Menu
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                            child: SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  Image.asset('assets/images/logo.png', height: 24),
                                  Spacer(),
                                  // Animated Search Bar
                                  AnimatedContainer(
                                    duration: Duration(milliseconds: 300),
                                    width: _isSearchActive ? 240 : 56,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: _isSearchActive ? Colors.black.withOpacity(0.8) : Colors.transparent,
                                      border: _isSearchActive ? Border.all(color: Colors.white24) : null,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      children: [
                                        if (_isSearchActive)
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
                                              child: TextField(
                                                controller: _searchController,
                                                autofocus: true,
                                                style: TextStyle(color: Colors.white, fontSize: 16),
                                                decoration: InputDecoration(
                                                  hintText: 'Títulos, géneros...',
                                                  hintStyle: TextStyle(color: Colors.grey),
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.zero,
                                                ),
                                                cursorColor: Color(0xFFD30000),
                                              ),
                                            ),
                                          ),
                                        IconButton(
                                          icon: Icon(_isSearchActive ? Icons.close : Icons.search, color: Colors.white, size: 24),
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                          onPressed: _toggleSearch,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Animated Menu Icon (SVG)
                                  _AnimatedMenuIcon(
                                    isOpened: _isDrawerOpen,
                                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          // Horizontal Menu Categories
                          if (!showSearchResults) ...[
                             Container(
                              height: 32,
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildMenuChip('Inicio', _currentSection == 'Inicio'),
                                  _buildMenuChip('Series', _currentSection == 'Series'),
                                  _buildMenuChip('Películas', _currentSection == 'Películas'),
                                  _buildMenuChip('Favoritos', _currentSection == 'Favoritos'),
                                  _buildMenuChip('Planes', _currentSection == 'Planes'),
                                ],
                              ),
                            ),
                            SizedBox(height: 4),
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionContent() {
    if (_currentSection.startsWith('Genre: ')) {
      final genreName = _currentSection.split(': ')[1];
      return _buildGridSection(genreName, _getAllByGenre(genreName));
    }

    switch (_currentSection) {
      case 'Series':
        return _buildGridSection('Series', _getSectionItems('Series'));
      case 'Películas':
        return _buildGridSection('Películas', _getSectionItems('Películas'));
      case 'Favoritos':
        return _buildFavoritesSection();
      case 'Planes':
        return _buildPlansSection();
      case 'Inicio':
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          HeroSlider(
          heroItems: _heroItems,
          catalog: _catalog,
          onPlayPressed: (title) {
            final lowerTitle = title.toLowerCase();
            try {
              final item = _catalog.firstWhere((c) => c.titulo.toLowerCase() == lowerTitle);
              _openDetailModal(item);
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Contenido no encontrado en el catálogo ($title)')),
              );
            }
          },
        ),
          _buildContinueWatchingSection(),
          ContentSection(title: 'Recién agregadas', items: _filterByGenre('Recién agregadas'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Terror', items: _filterByGenre('Terror'), onExploreAll: () => _onMenuChange('Genre: Terror'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Acción', items: _filterByGenre('Acción'), onExploreAll: () => _onMenuChange('Genre: Acción'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Romance', items: _filterByGenre('Romance'), onExploreAll: () => _onMenuChange('Genre: Romance'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Comedia', items: _filterByGenre('Comedia'), onExploreAll: () => _onMenuChange('Genre: Comedia'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Drama', items: _filterByGenre('Drama'), onExploreAll: () => _onMenuChange('Genre: Drama'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Animación', items: _filterByGenre('Animación'), onExploreAll: () => _onMenuChange('Genre: Animación'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          ContentSection(title: 'Suspenso', items: _filterByGenre('Suspenso'), onExploreAll: () => _onMenuChange('Genre: Suspenso'), fullCatalog: _catalog, favorites: _favorites, onToggleFavorite: _toggleFavorite),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingSection() {
    return Consumer<ProgressProvider>(
      builder: (context, progressProvider, child) {
        final progressData = progressProvider.progressData;
        if (progressData.isEmpty) return SizedBox.shrink();

        // Sort by timestamp descending
        final List<MapEntry<String, Map<String, dynamic>>> sortedEntries = progressData.entries.toList()
          ..sort((a, b) {
            final int timeA = a.value['timestamp'] ?? 0;
            final int timeB = b.value['timestamp'] ?? 0;
            return timeB.compareTo(timeA);
          });
        
        // Take top 5
        final top5 = sortedEntries.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Continuar viendo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24, // Matching web size
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              height: 190, // Height for backdrop card
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: top5.length,
                itemBuilder: (context, index) {
                  final entry = top5[index];
                  final String id = entry.key;
                  final Map<String, dynamic> data = entry.value;

                  // Extract data
                  final String titulo = data['titulo'] ?? '';
                  final String subtitulo = data['subtitulo'] ?? '';
                  final String continueUrl = data['continue_watching'] ?? data['backdrop'] ?? data['portada'] ?? '';
                  final double time = (data['time'] as num?)?.toDouble() ?? 0;
                  final double duration = (data['duration'] as num?)?.toDouble() ?? 1; // avoid /0
                  final double progressPct = (time / duration).clamp(0.0, 1.0);
                  
                  return Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // Try to lookup Contenido in catalog
                          final tmdbId = data['tmdbId'];
                          Contenido? item;
                          try {
                            item = _catalog.firstWhere((c) => c.tmdbId == tmdbId);
                          } catch (_) {
                            try {
                              item = _catalog.firstWhere((c) => c.titulo == titulo);
                            } catch (_) {}
                          }

                          if (item != null) {
                            _openDetailModal(item);
                          }
                        },
                        child: Container(
                          width: 240,
                          margin: EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Image Part (120px)
                              Expanded(
                                child: CachedNetworkImage(
                                  imageUrl: continueUrl.startsWith('http') 
                                      ? continueUrl 
                                      : '${ApiService.baseUrl}/${continueUrl}',
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[900]),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[900],
                                    child: Icon(Icons.error, color: Colors.white),
                                  ),
                                ),
                              ),
                              // Progress Bar
                              Container(
                                height: 4,
                                width: double.infinity,
                                color: Colors.grey[800],
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: progressPct,
                                  child: Container(color: Color(0xFFE50914)),
                                ),
                              ),
                              // Text Info
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      titulo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (subtitulo.isNotEmpty) ...[
                                      SizedBox(height: 4),
                                      Text(
                                        subtitulo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Top Right Delete button
                      Positioned(
                        top: 6,
                        right: 18,
                        child: GestureDetector(
                          onTap: () {
                             progressProvider.removeVideoProgress(id);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 0.5),
                            ),
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(Icons.search_off, size: 64, color: Colors.grey[800]),
             SizedBox(height: 16),
             Text(
               "No se encontraron resultados para\n'$_searchQuery'", 
               textAlign: TextAlign.center,
               style: TextStyle(color: Colors.grey, fontSize: 16),
             ),
          ],
        ),
      );
    }
    
    return Container(
      color: Color(0xFF0E0E0E),
      padding: EdgeInsets.fromLTRB(16, 140, 16, 0), // Top padding for AppBar + Header
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Resultados para "$_searchQuery"',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              AnimatedCount(count: _searchResults.length),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.only(bottom: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, 
                childAspectRatio: 0.48, 
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                return ContentCard(
                  item: item,
                  isFavorite: _favorites.contains(item.tmdbId.toString()),
                  onToggleFavorite: () => _toggleFavorite(item),
                  similarItems: _catalog,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridSection(String title, List<Contenido> items) {
    return Container(
      color: Color(0xFF0E0E0E),
      padding: EdgeInsets.fromLTRB(16, 140, 16, 0), // Adjusted top padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              SizedBox(width: 8),
              AnimatedCount(count: items.length),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              controller: _gridScrollController,
              padding: EdgeInsets.only(bottom: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, 
                childAspectRatio: 0.48, 
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ContentCard(
                  item: item,
                  isFavorite: _favorites.contains(item.tmdbId.toString()),
                  onToggleFavorite: () => _toggleFavorite(item),
                  similarItems: _catalog,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesSection() {
    // 1. Get favorite items (based on current _favorites set)
    final favoriteItems = _catalog.where((item) => _favorites.contains(item.tmdbId.toString())).toList();
    
    // 2. Sort by "Newest Marked" -> This requires preserving the insertion order of `_favorites`.
    // Since `_favorites` is a Set (which preserves insertion order in Dart), converting to List puts oldest first.
    // So we reverse it to get newest first.
    final orderedFavorites = _favorites.toList().reversed
        .map((id) => favoriteItems.firstWhere((item) => item.tmdbId.toString() == id, orElse: () => Contenido(tmdbId: -1, titulo: '', genero: [], portada: '', tipo: '', sinopsis: '', backdrop: '')))
        .where((item) => item.tmdbId != -1)
        .toList();

    if (orderedFavorites.isEmpty) {
      return Container(
          color: Color(0xFF0E0E0E),
          width: double.infinity,
          padding: EdgeInsets.only(top: 140),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_movies, size: 64, color: Colors.grey[700]), 
              SizedBox(height: 16),
              Text('Tu lista está vacía', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              SizedBox(height: 8),
              Text(
                'Aún no has guardado películas o series.\n¡Explora el catálogo y marca tus\nfavoritas!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Spacer(flex: 2),
            ],
          ),
      );
    }

    return _buildGridSection('Mi Lista', orderedFavorites);
  }

  Widget _buildPlansSection() {
    return Container(
      color: Color(0xFF0E0E0E),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 140, 24, 0), // Adjusted top padding
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // FREE Plan
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Text('FREE', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(text: '\$0', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
                        TextSpan(text: '/mes', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  Text('Acceso a 5 películas en streaming', style: TextStyle(color: Colors.grey[300])),
                  SizedBox(height: 8),
                  Text('Acceso a 2 series en streaming', style: TextStyle(color: Colors.grey[300])),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.grey,
                      minimumSize: Size(double.infinity, 44),
                    ),
                    child: Text('Ya lo tienes'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            // PREMIUM Plan
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFF0E0E0E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFD30000), width: 2),
              ),
              child: Column(
                children: [
                  Text('PREMIUM', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD30000))),
                  SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(text: '\$49', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
                        TextSpan(text: 'MXN/mes', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  Text('Acceso a contenido nuevo en FHD', style: TextStyle(color: Colors.grey[300])),
                  SizedBox(height: 8),
                  Text('Acceso ILIMITADO al contenido', style: TextStyle(color: Colors.grey[300])),
                  SizedBox(height: 8),
                  Text('Prioridad en pedidos y subidas', style: TextStyle(color: Colors.grey[300])),
                  SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final authProv = Provider.of<AuthProvider>(context, listen: false);
                      final role = authProv.userRole.toLowerCase();
                      final isPremiumOrAdmin = role == 'premium' || role == 'admin';
                      return ElevatedButton(
                        onPressed: isPremiumOrAdmin ? null : () async {
                          final username = authProv.username ?? 'Usuario';
                          final message = Uri.encodeComponent('¡Hola! soy el usuario $username, quisiera mejorar mi plan de Vanacue, espero más información.');
                          final url = Uri.parse('https://t.me/llzkxrll?text=$message');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                           backgroundColor: isPremiumOrAdmin ? Colors.white10 : Color(0xFF1A1A1A),
                           foregroundColor: isPremiumOrAdmin ? Colors.grey : Colors.white,
                           side: BorderSide(color: isPremiumOrAdmin ? Colors.grey : Color(0xFFD30000)),
                           minimumSize: Size(double.infinity, 44),
                        ),
                        child: Text(isPremiumOrAdmin ? 'Ya lo tienes' : 'Lo quiero', style: TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('https://vnc-e.com/terminos.html');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Text(
              'T\u00e9rminos y Condiciones',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: Colors.grey[600],
              ),
            ),
          ),
          SizedBox(height: 12),
          Text(
            '\u00a9 2026 Vanacue. Todos los derechos reservados.',
            style: TextStyle(color: Colors.grey[700], fontSize: 11),
          ),
          SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildMenuChip(String label, [bool isActive = false]) {
    return GestureDetector(
      onTap: () => _onMenuChange(label),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          fontSize: 15,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    );
  }
}

class _AnimatedMenuIcon extends StatefulWidget {
  final bool isOpened;
  final VoidCallback onPressed;
  
  const _AnimatedMenuIcon({
    required this.isOpened,
    required this.onPressed,
  });

  @override
  __AnimatedMenuIconState createState() => __AnimatedMenuIconState();
}

class __AnimatedMenuIconState extends State<_AnimatedMenuIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 300));
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 50),
    ]).animate(_controller);
    _rotationAnimation = Tween(begin: 0.0, end: 0.5).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_AnimatedMenuIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpened != oldWidget.isOpened) {
      _controller.forward().then((_) => _controller.reset());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => RotationTransition(turns: _rotationAnimation, child: FadeTransition(opacity: anim, child: child)),
            child: SvgPicture.asset(
              widget.isOpened ? 'assets/images/menu_apertura.svg' : 'assets/images/menu.svg',
              key: ValueKey<bool>(widget.isOpened),
              colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
              height: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedCount extends StatefulWidget {
  final int count;
  const AnimatedCount({Key? key, required this.count}) : super(key: key);

  @override
  _AnimatedCountState createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(seconds: 1), 
        vsync: this
    );
    _animation = IntTween(begin: 0, end: widget.count).animate(_controller);
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count) {
      _controller.reset();
      _animation = IntTween(begin: 0, end: widget.count).animate(_controller);
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Text(
          '(${_animation.value})',
           style: TextStyle(fontSize: 16, color: Colors.grey),
        );
      },
    );
  }
}

class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
