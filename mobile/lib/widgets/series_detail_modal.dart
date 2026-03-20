import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../screens/video_player_screen.dart';
import '../providers/providers.dart';
import 'movie_detail_modal.dart';
import 'package:flutter/services.dart';
import 'write_review_modal.dart';
import '../screens/home_screen.dart';
import '../providers/reviews_provider.dart';

class SeriesDetailModal extends StatefulWidget {
  final Contenido item;
  final VoidCallback onToggleFavorite;
  final bool isFavorite;
  final List<Contenido> similarItems;

  const SeriesDetailModal({
    Key? key,
    required this.item,
    required this.onToggleFavorite,
    required this.isFavorite,
    this.similarItems = const [],
  }) : super(key: key);

  @override
  _SeriesDetailModalState createState() => _SeriesDetailModalState();
}

class _SeriesDetailModalState extends State<SeriesDetailModal> {
  int _selectedSeasonIndex = 0;
  int? _watchedSeasonIndex;
  int? _watchedEpisodeIndex;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
    _loadSavedSeasonAndEpisode();
  }

  void _loadSavedSeasonAndEpisode() {
    final progressProvider = Provider.of<ProgressProvider>(context, listen: false);
    final progressData = progressProvider.progressData;
    
    // Search through all progress entries to find one matching this series
    int? savedSeasonIndex;
    int? savedEpisodeIndex;
    int latestTimestamp = 0;
    
    for (final entry in progressData.entries) {
      final data = entry.value;
      if (data['tmdbId'] == widget.item.tmdbId && data['esSerie'] == true) {
        final ts = (data['timestamp'] as num?)?.toInt() ?? 0;
        if (ts > latestTimestamp) {
          latestTimestamp = ts;
          savedSeasonIndex = (data['seasonIndex'] as num?)?.toInt();
          savedEpisodeIndex = (data['episodeIndex'] as num?)?.toInt();
        }
      }
    }
    
    if (savedSeasonIndex != null && widget.item.temporadas != null &&
        savedSeasonIndex < widget.item.temporadas!.length) {
      _selectedSeasonIndex = savedSeasonIndex;
      _watchedSeasonIndex = savedSeasonIndex;
      _watchedEpisodeIndex = savedEpisodeIndex;
    }
  }

  String _getPlayButtonLabel() {
    int sIdx = _watchedSeasonIndex ?? 0;
    int eIdx = _watchedEpisodeIndex ?? 0;
    
    if (widget.item.temporadas != null && sIdx < widget.item.temporadas!.length) {
      final season = widget.item.temporadas![sIdx];
      if (eIdx < season.episodios.length) {
        final ep = season.episodios[eIdx];
        return 'Reproducir T${season.numero}:E${ep.numero}';
      }
    }
    return 'Reproducir T1:E1';
  }

  void _handleToggleFavorite() {
    setState(() {
      _isFavorite = !_isFavorite;
    });
    widget.onToggleFavorite();
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

  void _handlePlay(Contenido item, [int? seasonIndex, int? episodeIndex]) {
     final authProvider = Provider.of<AuthProvider>(context, listen: false);
     final String role = authProvider.userRole.toLowerCase();

     if (item.premium && role != 'premium' && role != 'admin') {
       _showPremiumModal();
       return;
     }

     // Default to S1 E1 if no specific episode logic yet (later we can use tracking)
     final seasons = item.temporadas;
     if (seasons != null && seasons.isNotEmpty) {
       final season = seasons[seasonIndex ?? 0]; // Default to first available or selected
       if (season.episodios.isNotEmpty) {
         final episode = season.episodios[episodeIndex ?? 0];
         
         if (episode.streamUrl != null && episode.streamUrl!.isNotEmpty) {
            final String episodeString = 'T${season.numero}:E${episode.numero} - ${episode.titulo}';
            final progressProvider = Provider.of<ProgressProvider>(context, listen: false);
            final String progressId = generateProgressId(widget.item, episodeTitle: episodeString);
            final double savedProgress = progressProvider.getVideoProgress(progressId);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  videoUrl: episode.streamUrl!,
                  title: '${widget.item.titulo} - $episodeString',
                  audios: episode.audios,
                  subtitulos: episode.subtitulos,
                  contentMaster: widget.item,
                  episodeTitle: episodeString,
                  startPosition: Duration(seconds: savedProgress.toInt()),
                ),
              ),
            );
         } else {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Este episodio no está disponible')),
           );
         }
         return;
       }
     }
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('No hay episodios disponibles para reproducir')),
     );
  }

  void _playEpisode(Episodio episode) {
     final authProvider = Provider.of<AuthProvider>(context, listen: false);
     final String role = authProvider.userRole.toLowerCase();

     if (widget.item.premium && role != 'premium' && role != 'admin') {
       _showPremiumModal();
       return;
     }

     if (episode.streamUrl != null && episode.streamUrl!.isNotEmpty) {
        final Temporada selectedSeason = widget.item.temporadas![_selectedSeasonIndex];
        final int episodeIdx = selectedSeason.episodios.indexOf(episode);
        final String episodeString = 'T${selectedSeason.numero}:E${episode.numero} - ${episode.titulo}';
        final progressProvider = Provider.of<ProgressProvider>(context, listen: false);
        final String progressId = generateProgressId(widget.item, episodeTitle: episodeString);
        final double savedProgress = progressProvider.getVideoProgress(progressId);

        // Update displayed watched episode
        setState(() {
          _watchedEpisodeIndex = episodeIdx;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              videoUrl: episode.streamUrl!,
              title: '${widget.item.titulo} - $episodeString',
              audios: episode.audios,
              subtitulos: episode.subtitulos,
              contentMaster: widget.item,
              episodeTitle: episodeString,
              startPosition: Duration(seconds: savedProgress.toInt()),
              seasonIndex: _selectedSeasonIndex,
              episodeIndex: episodeIdx >= 0 ? episodeIdx : 0,
              catalog: widget.similarItems,
            ),
          ),
        ).then((_) {
           _loadSavedSeasonAndEpisode();
           setState((){});
        });
     } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Este episodio no está disponible')),
       );
     }
  }

  @override
  Widget build(BuildContext context) {
    // Safety check for seasons
    final seasons = widget.item.temporadas ?? [];
    final currentSeason = seasons.isNotEmpty ? seasons[_selectedSeasonIndex] : null;

    // Filter and Sort Similar Items (Same logic as MovieDetailModal)
    final filteredSimilarMap = <String, Contenido>{};
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
    final similarFiltered = filteredSimilarMap.values.toList().reversed.take(6).toList();

    return Scaffold(
      backgroundColor: Color(0xFF141414),
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
                    shadows: [Shadow(color: Colors.black, blurRadius: 10)],
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
                     color: Color(0xFFFFD700),
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
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // Action Buttons Row
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _handlePlay(widget.item, _watchedSeasonIndex ?? _selectedSeasonIndex, _watchedEpisodeIndex ?? 0),
                            icon: Icon(Icons.play_arrow, color: Colors.black),
                            label: Text(_getPlayButtonLabel()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.item.premium ? Color(0xFFFFD700) : Colors.white,
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
                          icon: Icon(Icons.telegram, color: Colors.blue), // Telegram Color
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
                   
                   // Metadata
                   Row(
                     children: [
                       Text(
                         'Match ${widget.item.match ?? '85%'}', 
                         style: TextStyle(color: Color(0xFF46D369), fontWeight: FontWeight.bold, fontSize: 16),
                       ),
                       SizedBox(width: 12),
                       Text('2018', style: TextStyle(color: Colors.grey, fontSize: 16)),
                       SizedBox(width: 12),
                       Text('${seasons.length} temporadas', style: TextStyle(color: Colors.grey, fontSize: 16)),
                       SizedBox(width: 12),
                       Container(
                         padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                         decoration: BoxDecoration(
                           border: Border.all(color: Colors.grey),
                           borderRadius: BorderRadius.circular(2),
                         ),
                         child: Text('Serie', style: TextStyle(color: Colors.grey, fontSize: 10)),
                       ),
                     ],
                   ),
                   SizedBox(height: 16),

                   // Synopsis
                   Text(
                     widget.item.sinopsis,
                     style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                   ),
                   SizedBox(height: 16),
                   
                   _buildInfoRow('Director:', widget.item.director ?? 'Varios'),
                   SizedBox(height: 4),
                   _buildInfoRow('Elenco:', widget.item.reparto ?? 'No disponible'),
                   SizedBox(height: 4),
                   _buildInfoRow('Géneros:', widget.item.genero.join(', ')),


                   SizedBox(height: 24),
                   
                   // Seasons & Episodes Section
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Text('Episodios', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                       if (seasons.isNotEmpty)
                         DropdownButton<int>(
                           value: _selectedSeasonIndex,
                           dropdownColor: Colors.grey[900],
                           style: TextStyle(color: Colors.white, fontSize: 16),
                           icon: Icon(Icons.keyboard_arrow_down, color: Colors.white),
                           underline: Container(), // Remove underline
                           items: List.generate(seasons.length, (index) {
                             return DropdownMenuItem(
                               value: index,
                               child: Text('Temporada ${seasons[index].numero}'),
                             );
                           }),
                           onChanged: (val) {
                             setState(() {
                               _selectedSeasonIndex = val!;
                             });
                           },
                         ),
                     ],
                   ),
                   SizedBox(height: 16),

                   if (currentSeason != null)
                     ListView.builder(
                       shrinkWrap: true,
                       physics: NeverScrollableScrollPhysics(),
                       itemCount: currentSeason.episodios.length,
                       itemBuilder: (context, index) {
                         final episode = currentSeason.episodios[index];
                         final bool isWatched = (_watchedEpisodeIndex == index && _watchedSeasonIndex == _selectedSeasonIndex);
                         return Container(
                           margin: EdgeInsets.only(bottom: 16),
                           decoration: isWatched 
                               ? BoxDecoration(
                                   color: Color(0xFF333333),
                                   border: Border(left: BorderSide(color: Color(0xFFE50914), width: 4)),
                                 )
                               : null,
                           padding: isWatched ? EdgeInsets.symmetric(vertical: 8, horizontal: 8) : EdgeInsets.zero,
                           child: Row(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               // Episode Number
                               SizedBox(
                                 width: 24, 
                                 child: Center(child: Text('${episode.numero}', style: TextStyle(color: isWatched ? Color(0xFFE50914) : Colors.grey, fontSize: 16)))
                               ),
                               SizedBox(width: 8),
                               // Thumbnail
                               GestureDetector(
                                 onTap: () => _playEpisode(episode),
                                 child: Container(
                                   width: 120,
                                   height: 68,
                                   decoration: BoxDecoration(
                                     borderRadius: BorderRadius.circular(4),
                                     image: DecorationImage(
                                       image: CachedNetworkImageProvider(
                                         (episode.imagen != null && episode.imagen!.isNotEmpty)
                                             ? (episode.imagen!.startsWith('http') ? episode.imagen! : '${ApiService.baseUrl}/${episode.imagen}')
                                             : (widget.item.backdrop.startsWith('http') ? widget.item.backdrop : '${ApiService.baseUrl}/${widget.item.backdrop}')
                                       ),
                                       fit: BoxFit.cover,
                                     ),
                                   ),
                                   child: Center(
                                     child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 32),
                                   ),
                                 ),
                               ),
                               SizedBox(width: 12),
                               // Info
                               Expanded(
                                 child: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     Text(
                                       episode.titulo,
                                       style: TextStyle(color: isWatched ? Color(0xFFE50914) : Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                     ),
                                     Text(
                                       episode.duracion ?? '21 min',
                                       style: TextStyle(color: Colors.grey, fontSize: 12),
                                     ),
                                     SizedBox(height: 4),
                                     Text(
                                       episode.sinopsis,
                                       maxLines: 2,
                                       overflow: TextOverflow.ellipsis,
                                       style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                     ),
                                   ],
                                 ),
                               ),
                             ],
                           ),
                         );
                       },
                     ),
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
                       itemCount: similarFiltered.length,
                       itemBuilder: (context, index) {
                           final similar = similarFiltered[index];
                           
                           return GestureDetector(
                             onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (ctx) => similar.tipo.toLowerCase() == 'serie' ? SeriesDetailModal(item: similar, similarItems: widget.similarItems, isFavorite: false, onToggleFavorite: () {}) : MovieDetailModal(item: similar, similarItems: widget.similarItems, isFavorite: false, onToggleFavorite: () {}, onPlay: () {}))); },
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
                   ],
                ],
              ),
            ),
          )
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

