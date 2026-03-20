import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../providers/reviews_provider.dart';
import '../widgets/comment_bottom_sheet.dart';
import '../widgets/movie_detail_modal.dart';
import '../widgets/series_detail_modal.dart';
import '../widgets/share_review_modal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'home_screen.dart';

class ReviewsTab extends StatefulWidget {
  final List<Contenido> catalog;

  const ReviewsTab({super.key, required this.catalog});

  @override
  _ReviewsTabState createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<ReviewsTab> {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ReviewsProvider>(context, listen: false);
      _searchController.text = provider.searchQuery;
      provider.loadReviews(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only premium users can interact, but everyone can see.
    return SingleChildScrollView(
      physics: ClampingScrollPhysics(), // Match home_screen physics if needed
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildRulesBox(),
          _buildPopularSection(),
          _buildReviewsFeed(),
          SizedBox(height: 100), // padding bottom
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 140.0, bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reseñas de la Comunidad',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          SizedBox(height: 8),
          Text(
            'Descubre las opiniones sobre los estrenos más recientes y los clásicos de siempre.',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesBox() {
    final role = Provider.of<AuthProvider>(context).userRole.toLowerCase();
    final isPremiumOrAdmin = role == 'premium' || role == 'admin';

    if (!isPremiumOrAdmin) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFF0E0E0E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFF7A040A), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.info, color: Color(0xFFE50914), size: 24),
                   SizedBox(width: 8),
                   Flexible(
                     child: Text(
                       '¿Quieres compartir tu opinión?', 
                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                       textAlign: TextAlign.center,
                     ),
                   ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Solo los miembros con suscripción Premium pueden escribir, puntuar y comentar contenido. ¡Únete a Vanacue Premium hoy!',
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
              SizedBox(height: 16),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    HomeScreen.globalKey.currentState?.setSection('Planes');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    minimumSize: Size(0, 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('VER PLAN PREMIUM', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: Color(0xFFE50914), width: 4)),
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFFE50914), size: 20),
                SizedBox(width: 8),
                Text(
                  'Funcionamiento de reseñas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            SizedBox(height: 16),
            _buildRuleRow('1', 'Selecciona la obra que quieras puntuar y da click en el "lápiz".'),
            _buildRuleRow('2', 'Puntúa de 1 a 5 estrellas.'),
            _buildRuleRow('3', 'Redacta, no uses palabras antisonantes ni spoilers.'),
            _buildRuleRow('4', 'Publica tu reseña y espera aprobación por parte de la administración.'),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE50914)),
            child: Text(number, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey[300], fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildPopularSection() {
    final popular = widget.catalog.where((c) => c.popular == true).toList().reversed.take(4).toList();
    
    // Hide section entirely if no popular movies found like in real apps, or just show whatever is available
    if (popular.isEmpty) return SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Populares ahora', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to Home
                },
                child: Text('Ver todo', style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: popular.length > 4 ? 4 : popular.length,
            itemBuilder: (context, index) {
              final movie = popular[index];
              return GestureDetector(
                onTap: () {
                  if (movie.esSerie) {
                    Navigator.push(context, MaterialPageRoute(builder: (ctx) => SeriesDetailModal(item: movie, similarItems: widget.catalog, isFavorite: false, onToggleFavorite: () {})));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (ctx) => MovieDetailModal(item: movie, similarItems: widget.catalog, isFavorite: false, onToggleFavorite: () {}, onPlay: (){})));
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: movie.portada,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsFeed() {
    return Consumer<ReviewsProvider>(
      builder: (context, provider, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Últimas reseñas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  DropdownButton<String>(
                    dropdownColor: Color(0xFF1E1E1E),
                    value: provider.currentSortOrder,
                    style: TextStyle(color: Colors.grey[300], fontSize: 14),
                    underline: SizedBox(),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.grey[300]),
                    items: [
                      DropdownMenuItem(value: 'recent', child: Text('Recientes')),
                      DropdownMenuItem(value: 'oldest', child: Text('Antiguas')),
                    ],
                    onChanged: (val) {
                      if (val != null) provider.setSortOrder(val);
                    },
                  ),
                ],
              ),
              SizedBox(height: 12),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF222222),
                  hintText: 'Buscar por película o usuario...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (val) {
                  provider.setSearchQuery(val);
                },
              ),
              SizedBox(height: 24),
              if (provider.isLoading && provider.reviews.isEmpty)
                Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
              if (!provider.isLoading && provider.reviews.isEmpty)
                Center(child: Text("No hay reseñas aún.", style: TextStyle(color: Colors.grey[500]))),
              ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: provider.reviews.length,
                separatorBuilder: (context, index) => SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return _buildReviewCard(provider.reviews[index], provider);
                },
              ),
              if (provider.hasMore && !provider.isLoading && provider.reviews.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFFE50914)),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => provider.loadReviews(),
                      child: Text("Cargar más"),
                    ),
                  ),
                )
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewCard(Review review, ReviewsProvider provider) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isFree = authProvider.userRole == 'Free' || authProvider.userRole == 'free';

    void handleInteraction(VoidCallback action) {
      if (isFree) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Esta acción requiere suscripción Premium'),
            backgroundColor: Color(0xFFE50914),
          ),
        );
      } else {
        action();
      }
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF161616),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[800],
                backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/${review.profilePic}'),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.username, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    Text('Reseñado el ${_formatDate(review.createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < review.rating ? Icons.star : Icons.star_border,
                    color: Color(0xFFE50914),
                    size: 16,
                  );
                }),
              )
            ],
          ),
          SizedBox(height: 16),
          Text(
            '${review.movieTitle} (${review.movieYear})',
            style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            '"${review.comment}"',
            style: TextStyle(color: Colors.grey[300], fontSize: 14, fontStyle: FontStyle.italic),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(color: Color(0xFF333333)),
          ),
          Row(
            children: [
              _buildInteractionButton(
                Icons.thumb_up_alt_outlined, 
                review.userHasLiked == 1 ? Icons.thumb_up : Icons.thumb_up_alt_outlined, 
                review.likes.toString(), 
                review.userHasLiked == 1 ? Color(0xFFE50914) : Colors.grey[400]!,
                () => handleInteraction(() {
                  provider.toggleReaction(review.id, 'like');
                })
              ),
              SizedBox(width: 16),
              _buildInteractionButton(
                Icons.thumb_down_alt_outlined, 
                review.userHasDisliked == 1 ? Icons.thumb_down : Icons.thumb_down_alt_outlined, 
                review.dislikes.toString(), 
                review.userHasDisliked == 1 ? Color(0xFFE50914) : Colors.grey[400]!,
                () => handleInteraction(() {
                  provider.toggleReaction(review.id, 'dislike');
                })
              ),
              SizedBox(width: 16),
              _buildInteractionButton(
                Icons.chat_bubble_outline, 
                Icons.chat_bubble_outline, 
                review.commentsCount.toString(), 
                Colors.grey[400]!,
                () => handleInteraction(() {
                  showCommentBottomSheet(context, review);
                })
              ),
              SizedBox(width: 16),
              _buildInteractionButton(
                Icons.share_outlined, 
                Icons.share_outlined, 
                'Compartir', 
                Colors.grey[400]!,
                () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => FractionallySizedBox(
                    heightFactor: 0.9,
                    child: ShareReviewModal(review: review),
                  ),
                );
              }),
            ],
          )
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final inputDate = dateStr.endsWith('Z') ? dateStr : '${dateStr}Z';
      final dt = DateTime.parse(inputDate).toLocal();
      const monthNames = [
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
      ];
      return "${dt.day} de ${monthNames[dt.month - 1]} de ${dt.year}";
    } catch (_) {
      return dateStr; // fallback
    }
  }

  Widget _buildInteractionButton(IconData iconData, IconData activeIcon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(activeIcon, color: color, size: 18),
          SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
