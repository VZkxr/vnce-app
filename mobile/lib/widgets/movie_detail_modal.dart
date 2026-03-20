import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../screens/video_player_screen.dart';
import '../providers/providers.dart';
import 'series_detail_modal.dart';
import 'package:flutter/services.dart';
import 'write_review_modal.dart';
import '../providers/reviews_provider.dart';
import '../screens/home_screen.dart';

class MovieDetailModal extends StatefulWidget {
  final Contenido item;
  final VoidCallback onPlay;
  final VoidCallback onToggleFavorite;
  final bool isFavorite;
  final List<Contenido> similarItems;

  const MovieDetailModal({
    Key? key,
    required this.item,
    required this.onPlay,
    required this.onToggleFavorite,
    required this.isFavorite,
    this.similarItems = const [],
  }) : super(key: key);

  @override
  _MovieDetailModalState createState() => _MovieDetailModalState();
}

class _MovieDetailModalState extends State<MovieDetailModal> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }
  
  void _showPremiumModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF222222),
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber),
            SizedBox(width: 8),
            Text('Contenido Premium', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Este contenido es exclusivo para usuarios Premium. Contacta a soporte en Telegram para mejorar tu cuenta.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              final username = authProvider.username ?? 'Usuario';
              final message = '¡Hola!%20soy%20el%20usuario%20$username,%20quisiera%20mejorar%20mi%20plan%20de%20Vanacue,%20espero%20más%20información.';
              final url = Uri.parse('https://t.me/llzkxrll?text=$message');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            icon: Icon(Icons.telegram, color: Colors.white),
            label: Text('Contactar Soporte', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  void _handlePlay() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final progressProvider = Provider.of<ProgressProvider>(context, listen: false);
    final String role = authProvider.userRole.toLowerCase();
    
    if (widget.item.premium && role != 'premium' && role != 'admin') {
      _showPremiumModal();
      return;
    }

    if (widget.item.streamUrl != null && widget.item.streamUrl!.isNotEmpty) {
      final String progressId = generateProgressId(widget.item);
      final double savedProgress = progressProvider.getVideoProgress(progressId);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: widget.item.streamUrl!,
            title: widget.item.titulo,
            audios: widget.item.audios,
            subtitulos: widget.item.subtitulos,
            contentMaster: widget.item,
            startPosition: Duration(seconds: savedProgress.toInt()),
            catalog: widget.similarItems,
          ),
        ),
      );
    } else {
      // Show snackbar or toast if no stream URL
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No disponible en streaming')),
      );
    }
  }

  void _handleToggleFavorite() {
    setState(() {
      _isFavorite = !_isFavorite;
    });
    widget.onToggleFavorite();
  }

  @override
  Widget build(BuildContext context) {
    // Filter and Sort Similar Items
    final filteredSimilarMap = <String, Contenido>{};
    
    // First pass: Filter by genre match
    for (var similar in widget.similarItems) {
      if (similar.tmdbId == widget.item.tmdbId) continue;
       
       bool hasGenreMatch = false;
       for (var genre in widget.item.genero) {
         if (similar.genero.contains(genre)) {
           hasGenreMatch = true;
           break;
         }
       }
       
       if (hasGenreMatch) {
         filteredSimilarMap[similar.tmdbId.toString()] = similar;
       }
    }

    // Convert to list and sort (Newest first)
    // Assuming input 'widget.similarItems' (from _catalog) is Oldest -> Newest.
    // So we reverse the results to get Newest -> Oldest.
    final similarFiltered = filteredSimilarMap.values.toList().reversed.take(6).toList();

    return Scaffold(
      backgroundColor: Color(0xFF141414), // Dark background matching modal image
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFFE50914),
        onPressed: () {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          if (authProvider.userRole == 'Free' || authProvider.userRole == 'free') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Esta acción requiere suscripción Premium'), backgroundColor: Color(0xFFE50914))
            );
            return;
          }
          showWriteReviewModal(context, widget.item);
        },
        child: Icon(Icons.edit, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Color(0xFF141414),
            expandedHeight: 350,
            toolbarHeight: 110,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              bottom: false,
              child: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 16, bottom: 16, right: 16),
                title: Text(
                  widget.item.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24, // Smaller when pinned
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 10)], // Added shadow for readability
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                   ShaderMask(
                     shaderCallback: (rect) {
                       return LinearGradient(
                         begin: Alignment.topCenter,
                         end: Alignment.bottomCenter,
                         colors: [Colors.black, Colors.transparent],
                       ).createShader(Rect.fromLTRB(0, 0, rect.width, rect.height));
                     },
                     blendMode: BlendMode.dstIn,
                     child: CachedNetworkImage(
                       imageUrl: (widget.item.backdrop.isNotEmpty ? widget.item.backdrop : widget.item.portada).startsWith('http')
                           ? (widget.item.backdrop.isNotEmpty ? widget.item.backdrop : widget.item.portada)
                           : '${ApiService.baseUrl}/${widget.item.backdrop.isNotEmpty ? widget.item.backdrop : widget.item.portada}',
                       fit: BoxFit.cover,
                       alignment: Alignment.topCenter,
                       errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                     ),
                   ),
                  ],
                ),
              ),
            ),
            actions: [
               Container(
                 margin: EdgeInsets.only(right: 12),
                 decoration: BoxDecoration(
                   color: Colors.black.withOpacity(0.6),
                   shape: BoxShape.circle,
                 ),
                 child: IconButton(
                   icon: Icon(
                     _isFavorite ? Icons.star : Icons.star_border,
                     color: Color(0xFFFFD700), // Gold
                     size: 26,
                   ),
                   onPressed: _handleToggleFavorite,
                 ),
               ),
               Container(
                 margin: EdgeInsets.only(right: 16),
                 decoration: BoxDecoration(
                   color: Colors.black.withOpacity(0.6),
                   shape: BoxShape.circle,
                 ),
                 child: IconButton(
                   icon: Icon(Icons.close, color: Colors.white, size: 26),
                   onPressed: () => Navigator.pop(context),
                 ),
               ),
            ],
          ),
          
          SliverToBoxAdapter(
            child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   // Action Buttons Row
                   Row(
                     children: [
                       Expanded(
                         child: ElevatedButton.icon(
                           onPressed: _handlePlay,
                           icon: Icon(Icons.play_arrow, color: Colors.black),
                           label: Text('Reproducir'),
                           style: ElevatedButton.styleFrom(
                             backgroundColor: widget.item.premium ? Color(0xFFFFD700) : Colors.white, // Gold or White
                             foregroundColor: Colors.black,
                             padding: EdgeInsets.symmetric(vertical: 12),
                             textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                           ),
                         ),
                       ),
                       SizedBox(width: 8),
                       Expanded(
                         child: OutlinedButton.icon(
                           onPressed: () {
                             Provider.of<ReviewsProvider>(context, listen: false).setSearchQuery(widget.item.titulo);
                             Navigator.popUntil(context, (route) => route.isFirst);
                             HomeScreen.globalKey.currentState?.setSection('Reseñas');
                           },
                           icon: Icon(Icons.forum_outlined, color: Colors.white),
                           label: Text('Ver reseñas', style: TextStyle(color: Colors.white)),
                           style: OutlinedButton.styleFrom(
                             side: BorderSide(color: Colors.white54),
                             padding: EdgeInsets.symmetric(vertical: 12),
                           ),
                         ),
                       ),
                     ],
                   ),
                   SizedBox(height: 12),
                   Row(
                     children: [
                       IconButton(
                         icon: Icon(Icons.telegram, color: Colors.blue), // Telegram Blue
                         onPressed: () {
                          if (widget.item.enlaceTelegram != null && widget.item.enlaceTelegram!.isNotEmpty) {
                            launchUrl(Uri.parse(widget.item.enlaceTelegram!), mode: LaunchMode.externalApplication);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No disponible en Telegram')),
                            );
                          }
                         },
                         style: IconButton.styleFrom(
                           backgroundColor: Colors.grey[800],
                           padding: EdgeInsets.all(12),
                         ),
                       ),
                        SizedBox(width: 12),
                       IconButton(
                         icon: Icon(Icons.share, color: Colors.white),
                         onPressed: () {
                          final String shareUrl = 'https://vnc-e.com/share/${widget.item.tmdbId}';
                          Clipboard.setData(ClipboardData(text: shareUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Enlace copiado al portapapeles')),
                          );
                        },
                         style: IconButton.styleFrom(
                           backgroundColor: Colors.grey[800],
                           padding: EdgeInsets.all(12),
                         ),
                       ),
                     ],
                   ),
                   SizedBox(height: 16),

                   // Metadata Row
                   Row(
                     children: [
                       Text(
                         'Match ${widget.item.match ?? '95%'}', 
                         style: TextStyle(color: Color(0xFF46D369), fontWeight: FontWeight.bold, fontSize: 16), // Green match color
                       ),
                       SizedBox(width: 12),
                       Text('2023', style: TextStyle(color: Colors.grey, fontSize: 16)), // Year placeholder
                       SizedBox(width: 12),
                       Text(widget.item.duracion ?? '1h 30m', style: TextStyle(color: Colors.grey, fontSize: 16)),
                       SizedBox(width: 12),
                       Container(
                         padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                         decoration: BoxDecoration(
                           border: Border.all(color: Colors.grey),
                           borderRadius: BorderRadius.circular(2),
                         ),
                         child: Text('Película', style: TextStyle(color: Colors.grey, fontSize: 10)),
                       ),
                     ],
                   ),
                   SizedBox(height: 16),

                   // Synopsis
                   Text(
                     widget.item.sinopsis, // 'Description...'
                     style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                   ),
                   SizedBox(height: 16),

                   // Cast & Director
                   _buildInfoRow('Director:', widget.item.director ?? 'Desconocido'),
                   SizedBox(height: 4),
                   _buildInfoRow('Elenco:', widget.item.reparto ?? 'No disponible'),
                   SizedBox(height: 4),
                   _buildInfoRow('Géneros:', widget.item.genero.join(', ')),
                   
                   SizedBox(height: 24),
                   if (similarFiltered.isNotEmpty) ...[
                     Text(
                       'Más títulos similares',
                       style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                     ),
                     SizedBox(height: 16),
                     GridView.builder(
                       shrinkWrap: true,
                       physics: NeverScrollableScrollPhysics(),
                       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                         crossAxisCount: 3,
                         childAspectRatio: 0.55,
                         crossAxisSpacing: 8,
                         mainAxisSpacing: 12,
                       ),
                       itemCount: similarFiltered.length, // Already limited to 6
                       itemBuilder: (context, index) {
                           final similar = similarFiltered[index];
                           
                           return GestureDetector(
                             onTap: () {
                               Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (ctx) => similar.tipo.toLowerCase() == 'serie' ? SeriesDetailModal(item: similar, similarItems: widget.similarItems, isFavorite: false, onToggleFavorite: () {}) : MovieDetailModal(item: similar, similarItems: widget.similarItems, isFavorite: false, onToggleFavorite: () {}, onPlay: () {})));
                             },
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Expanded(
                                   child: ClipRRect(
                                     borderRadius: BorderRadius.circular(8),
                                     child: CachedNetworkImage(
                                       imageUrl: similar.portada.startsWith('http') 
                                           ? similar.portada 
                                           : '${ApiService.baseUrl}/${similar.portada}',
                                       fit: BoxFit.cover,
                                       errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                                     ),
                                   ),
                                 ),
                                 SizedBox(height: 8),
                                 Text(
                                   similar.titulo,
                                   maxLines: 2,
                                   overflow: TextOverflow.ellipsis,
                                   style: TextStyle(color: Colors.grey[300], fontSize: 11),
                                 )
                               ],
                             ),
                           );
                         },
                       ),
                   ], // This closes the `if` block's list of widgets.
                 ],
               ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14, color: Colors.grey),
        children: [
          TextSpan(text: '$label ', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          TextSpan(text: value, style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}


