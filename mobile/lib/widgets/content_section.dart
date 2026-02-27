import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'movie_detail_modal.dart';
import 'series_detail_modal.dart';

class ContentSection extends StatelessWidget {
  final String title;
  final List<Contenido> items;
  final List<Contenido> fullCatalog;
  final Set<String> favorites;
  final Function(Contenido) onToggleFavorite;
  final VoidCallback? onExploreAll;

  const ContentSection({
    Key? key,
    required this.title,
    required this.items,
    this.fullCatalog = const [],
    this.favorites = const {},
    required this.onToggleFavorite,
    this.onExploreAll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onExploreAll != null)
                GestureDetector(
                  onTap: onExploreAll,
                  child: Text(
                    'Explorar todo >',
                    style: TextStyle(
                      color: Color(0xFFD30000),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 320, 
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: BouncingScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                width: 150, 
                margin: EdgeInsets.symmetric(horizontal: 6.0),
                child: ContentCard(
                  item: item,
                  isFavorite: favorites.contains(item.tmdbId.toString()),
                  onToggleFavorite: () => onToggleFavorite(item),
                  similarItems: fullCatalog.isNotEmpty ? fullCatalog : items,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


// ... (existing imports)

class ContentCard extends StatelessWidget {
  final Contenido item;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final List<Contenido> similarItems;

  const ContentCard({
    Key? key, 
    required this.item,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.similarItems = const [],
  }) : super(key: key);

  void _showDetailModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        if (item.tipo == 'Serie') {
          return SeriesDetailModal(
            item: item, 
            isFavorite: isFavorite,
            onToggleFavorite: onToggleFavorite,
            similarItems: similarItems,
          );
        } else {
          return MovieDetailModal(
            item: item,
            isFavorite: isFavorite,
            onToggleFavorite: onToggleFavorite,
            similarItems: similarItems,
            onPlay: () { /* Play Logic */ },
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isStreaming = item.streamUrl != null || (item.temporadas != null && item.temporadas!.isNotEmpty);

    return GestureDetector(
      onTap: () => _showDetailModal(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: item.portada.startsWith('http') 
                      ? item.portada 
                      : '${ApiService.baseUrl}/${item.portada}',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey[900]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                      child: Icon(Icons.error, color: Colors.white),
                    ),
                  ),
                ),
                // Gradient Overlay (Bottom)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                      ),
                    ),
                  ),
                ),
                // Top-Left Pulsing Dot
                Positioned(
                  top: 8,
                  left: 8,
                  child: PulsingDot(
                    color: isStreaming ? Color(0xFF00E676) : Color(0xFFD30000), 
                  ),
                ),
                // Top-Right Star
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border,
                      color: Color(0xFFFFD700),
                      size: 28,
                    ),
                    padding: EdgeInsets.all(8), 
                    constraints: BoxConstraints(),
                    onPressed: onToggleFavorite,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          // Title and Genres
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  item.genero.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PulsingDot extends StatefulWidget {
  final Color color;
  const PulsingDot({Key? key, required this.color}) : super(key: key);

  @override
  _PulsingDotState createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 1500))..repeat();
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
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(1.0 - _controller.value),
                blurRadius: _controller.value * 10,
                spreadRadius: _controller.value * 5,
              ),
            ],
          ),
        );
      },
    );
  }
}
