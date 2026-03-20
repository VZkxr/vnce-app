import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'package:provider/provider.dart';
import '../providers/reviews_provider.dart';

void showWriteReviewModal(BuildContext context, Contenido item) {
  showDialog(
    context: context,
    builder: (context) {
      return _WriteReviewDialog(item: item);
    },
  );
}

class _WriteReviewDialog extends StatefulWidget {
  final Contenido item;

  const _WriteReviewDialog({required this.item});

  @override
  __WriteReviewDialogState createState() => __WriteReviewDialogState();
}

class __WriteReviewDialogState extends State<_WriteReviewDialog> {
  final ApiService _apiService = ApiService();
  final TextEditingController _textController = TextEditingController();
  
  int _rating = 0;
  bool _isSending = false;

  Future<void> _submitReview() async {
    final text = _textController.text.trim();
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Por favor selecciona una puntuación (1 a 5 estrellas).')));
      return;
    }
    if (text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('La reseña es muy corta. Mínimo 10 caracteres.')));
      return;
    }

    setState(() => _isSending = true);

    final success = await _apiService.createReview(
      tmdbId: widget.item.tmdbId,
      title: widget.item.titulo,
      type: widget.item.tipo,
      year: widget.item.fecha?.substring(0, 4) ?? '',
      rating: _rating,
      comment: text
    );

    setState(() => _isSending = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reseña enviada para aprobación'), backgroundColor: Colors.green));
      if (context.mounted) {
        // Refresh feed naturally on next visit
        Provider.of<ReviewsProvider>(context, listen: false).loadReviews(refresh: true);
        Navigator.pop(context);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al procesar. Intenta nuevamente.'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Color(0xFF161616),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.star, color: Color(0xFFE50914), size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Escribir Reseña', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            Divider(height: 1, color: Color(0xFF333333)),
            
            // Movie Info
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: widget.item.portada,
                        height: 60,
                        width: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.item.titulo, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('${widget.item.tipo} • ${widget.item.fecha?.substring(0, 4) ?? ''}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Rating
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Text('¿Qué te pareció?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _rating = index + 1;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _rating >= (index + 1) ? Color(0xFFE50914).withOpacity(0.2) : Color(0xFF2C2C2C),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _rating >= (index + 1) ? Icons.star : Icons.star_border,
                              color: _rating >= (index + 1) ? Color(0xFFE50914) : Colors.grey[600],
                              size: 28,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),

            // Input TextField
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  border: Border.all(color: Color(0xFF333333)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _textController,
                  maxLines: 5,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                    hintText: 'Escribe tu opinión aquí...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            ),

            // Warning
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Icon(Icons.info, color: Color(0xFFE50914), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('RECUERDA NO USAR PALABRAS ANTISONANTES NI SPOILERS', style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            Divider(height: 1, color: Color(0xFF333333)),

            // Footer / Actions
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancelar', style: TextStyle(color: Colors.grey[300])),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _submitReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFE50914),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isSending
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Publicar Reseña', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
