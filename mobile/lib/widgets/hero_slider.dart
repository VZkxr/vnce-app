import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class HeroSlider extends StatefulWidget {
  final List<HeroItem> heroItems;
  final List<Contenido> catalog;
  final Function(String title)? onPlayPressed;

  const HeroSlider({Key? key, required this.heroItems, required this.catalog, this.onPlayPressed}) : super(key: key);

  @override
  State<HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<HeroSlider> {
  late PageController _pageController;
  Timer? _timer;
  int _virtualPage = 0;

  @override
  void initState() {
    super.initState();
    // Start in the middle
    _virtualPage = 1000 * widget.heroItems.length; 
    _pageController = PageController(initialPage: _virtualPage);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 5), (Timer timer) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: Duration(milliseconds: 1000), // Smooth slow transition
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _resetTimer() {
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.heroItems.isEmpty) return SizedBox.shrink();

    return SizedBox(
      height: 600, // Taller as requested to blend better
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _virtualPage = index;
              });
              _resetTimer(); // Reset timer on manual swipe or auto change
            },
            itemBuilder: (context, index) {
              final item = widget.heroItems[index % widget.heroItems.length];
              final bool isActive = index == _virtualPage;
              
              // Get premium status
              final matchingContenido = widget.catalog.firstWhere((c) => c.titulo.toLowerCase() == item.titulo.toLowerCase(), orElse: () => Contenido(
                tmdbId: 0, 
                tipo: '', 
                titulo: '', 
                portada: '', 
                backdrop: '', 
                genero: [], 
                sinopsis: '', 
                premium: false,
              ));
              final bool isPremium = matchingContenido.premium;

              // Custom Swipe-Fade Transition
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double value = 1.0;
                  if (_pageController.position.haveDimensions) {
                    value = _pageController.page! - index;
                  }
                  
                  double clampedValue = value.clamp(-1.0, 1.0);
                  double opacity = (1 - clampedValue.abs()).clamp(0.0, 1.0);
                  
                  if (opacity == 0) return SizedBox.shrink();

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      double translateX = clampedValue * constraints.maxWidth;
                      
                      return Transform.translate(
                        offset: Offset(translateX, 0), // Stick in place
                        child: Opacity(
                          opacity: opacity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Background Image with Controlled Ken Burns
                              _KenBurnsImage(
                                imageUrl: '${ApiService.baseUrl}/${item.imagen}',
                                isActive: isActive, // Only animate if active
                              ),
                              
                              // Deep Blend Gradient (Extended)
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.0),
                                      Colors.black.withOpacity(0.4),
                                      Colors.black.withOpacity(0.9),
                                      Color(0xFF0E0E0E),
                                    ],
                                    stops: [0.0, 0.5, 0.7, 0.9, 1.0],
                                  ),
                                ),
                              ),

                              // Content
                              Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.logo != null && item.logo!.isNotEmpty)
                                      CachedNetworkImage(
                                        imageUrl: '${ApiService.baseUrl}/${item.logo}',
                                        height: 120,
                                        fit: BoxFit.contain,
                                        alignment: Alignment.centerLeft,
                                      )
                                    else
                                      Text(
                                        item.titulo,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Serif',
                                          shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                                        ),
                                      ),
                                    SizedBox(height: 12),
                                    Text(
                                      item.subtitulo,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 16,
                                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                      ),
                                    ),
                                    SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                         if (widget.onPlayPressed != null) {
                                            widget.onPlayPressed!(item.titulo);
                                          } else {
                                            print('Play ${item.titulo}');
                                          }
                                      },
                                      icon: Icon(Icons.play_arrow, color: Colors.black),
                                      label: Text('Reproducir'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isPremium ? Color(0xFFFFD700) : Colors.white,
                                        foregroundColor: Colors.black,
                                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    SizedBox(height: 50),
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
              );
            },
          ),
          
          // Indicators
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.heroItems.length, (index) {
                // Calculate based on virtual page to handle infinite
                int actualIndex = _virtualPage % widget.heroItems.length;
                bool isActive = actualIndex == index;
                return AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  width: isActive ? 12.0 : 8.0,
                  height: isActive ? 12.0 : 8.0,
                  margin: EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? Colors.white : Colors.white38,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _KenBurnsImage extends StatefulWidget {
  final String imageUrl;
  final bool isActive;
  
  const _KenBurnsImage({
    Key? key, 
    required this.imageUrl,
    required this.isActive,
  }) : super(key: key);

  @override
  State<_KenBurnsImage> createState() => _KenBurnsImageState();
}

class _KenBurnsImageState extends State<_KenBurnsImage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10), 
      vsync: this,
    );

    // Scaling up to 1.2 to 1.25 to prevent black strip edges
    _scaleAnimation = Tween<double>(begin: 1.2, end: 1.25).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Moving from Right (positive) to Left (negative/zero) or creating Panning effect
    // To move "Right to Left", the image should start at a positive offset and move to a smaller/negative offset?
    // Or if we want the "Camera" to pan right to left, the image moves Left to Right? 
    // User said "images move right to left". 
    // Let's try Offset(0.05, 0.0) -> Offset(-0.05, 0.0)
    _slideAnimation = Tween<Offset>(begin: Offset(0.05, 0.0), end: Offset(-0.05, 0.0)).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    if (widget.isActive) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_KenBurnsImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        // Reset and start only when becoming active
        _controller.reset();
        _controller.forward();
      } else {
        // Optional: Pause or let it finish. 
        // Request said: "image next... not enter movement until change complete"
        // Since we are creating new widgets in PageView builder often, 
        // or reusing them, resetting on active=true handles the "start fresh" requirement.
        _controller.stop(); 
      }
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
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.translate(
            offset: Offset(_slideAnimation.value.dx * MediaQuery.of(context).size.width, 0),
            child: child,
          ),
        );
      },
      child: CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment(0.0, -0.5), // Center-Top alignment to lower the subject
        placeholder: (context, url) => Container(color: Colors.black),
        errorWidget: (context, url, error) => Icon(Icons.error),
      ),
    );
  }
}
