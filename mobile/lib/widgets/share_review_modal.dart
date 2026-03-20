import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

class ShareReviewModal extends StatefulWidget {
  final Review review;

  const ShareReviewModal({Key? key, required this.review}) : super(key: key);

  @override
  _ShareReviewModalState createState() => _ShareReviewModalState();
}

class _ShareReviewModalState extends State<ShareReviewModal> {
  final ScreenshotController _screenshotController = ScreenshotController();
  
  bool isTicketMode = false;
  bool addPremiumGradient = true;
  bool includePageLink = true;
  bool isDarkBackground = false;
  bool isExporting = false;

  void _shareContent() async {
    setState(() => isExporting = true);
    try {
      final Uint8List? imageBytes = await _screenshotController.capture(
        delay: const Duration(milliseconds: 50),
        pixelRatio: 3.0,
      );

      if (imageBytes != null) {
        final result = await ImageGallerySaverPlus.saveImage(
            imageBytes,
            quality: 100,
            name: "Vanacue_Review_${widget.review.id}_${DateTime.now().millisecondsSinceEpoch}"
        );
        
        if (mounted) {
          if (result != null && result['isSuccess'] == true) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Guardado en la galería exitosamente'), backgroundColor: Colors.green),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo guardar la imagen en la galería'), backgroundColor: Colors.red),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error al generar imagen: $e')),
         );
      }
    } finally {
      if (mounted) {
         setState(() => isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Compartir Reseña',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Elige el formato ideal para tus redes sociales. Personaliza el estilo antes de exportar.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ),
            SizedBox(height: 16),

            // Preview Area (Flexible)
            Expanded(
              child: BackgroundPattern(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5))
                        ]
                      ),
                      child: Screenshot(
                        controller: _screenshotController,
                        child: _buildPreviewContent(),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Controls Area
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFF161616),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Formato de imagen Switcher
                  Text('FORMATO DE IMAGEN', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  SizedBox(height: 8),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10)
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => isTicketMode = false),
                            child: Container(
                              decoration: BoxDecoration(
                                color: !isTicketMode ? Color(0xFFE50914) : Colors.transparent,
                                borderRadius: BorderRadius.horizontal(left: Radius.circular(7)),
                              ),
                              alignment: Alignment.center,
                              child: Text('Estándar 9:16', style: TextStyle(color: !isTicketMode ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => isTicketMode = true),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isTicketMode ? Color(0xFFE50914) : Colors.transparent,
                                borderRadius: BorderRadius.horizontal(right: Radius.circular(7)),
                              ),
                              alignment: Alignment.center,
                              child: Text('Modo Ticket', style: TextStyle(color: isTicketMode ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Checkboxes based on mode
                  if (!isTicketMode) ...[
                    _buildCheckbox('Fondo degradado premium', addPremiumGradient, (v) => setState(() => addPremiumGradient = v!)),
                    _buildCheckbox('Incluir link de la página', includePageLink, (v) => setState(() => includePageLink = v!)),
                  ] else ...[
                     Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Color de fondo:', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                        Row(
                          children: [
                            GestureDetector(
                               onTap: () => setState(() => isDarkBackground = false),
                               child: Container(
                                 width: 24, height: 24, 
                                 margin: EdgeInsets.only(right: 8),
                                 decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: !isDarkBackground ? Color(0xFFE50914) : Colors.transparent, width: 2))
                               )
                            ),
                            GestureDetector(
                               onTap: () => setState(() => isDarkBackground = true),
                               child: Container(
                                 width: 24, height: 24, 
                                 decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0E0E0E), border: Border.all(color: isDarkBackground ? Color(0xFFE50914) : Colors.white24, width: 2))
                               )
                            ),
                          ]
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildCheckbox('Incluir link de la página', includePageLink, (v) => setState(() => includePageLink = v!)),
                  ],

                  SizedBox(height: 16),
                  
                  // Primary Buttons
                  ElevatedButton.icon(
                    onPressed: isExporting ? null : _shareContent,
                    icon: isExporting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(Icons.download),
                    label: Text('Descargar como PNG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFCC0000), // Matched user standard red
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                  SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancelar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.white12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Theme(
      data: ThemeData(unselectedWidgetColor: Colors.grey[600]),
      child: CheckboxListTile(
        title: Text(label, style: TextStyle(color: value ? Colors.white : Colors.grey[400], fontSize: 13, fontWeight: FontWeight.bold)),
        value: value,
        onChanged: onChanged,
        activeColor: Color(0xFFE50914),
        checkColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }

  Widget _buildPreviewContent() {
    return Container(
      color: Colors.black, // fallback background
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: SizedBox(
          width: 1080,
          height: 1920,
          child: isTicketMode ? _buildTicketMode() : _buildStandardMode(),
        ),
      ),
    );
  }

  Widget _buildStandardMode() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF0A0A0A),
        gradient: addPremiumGradient ? LinearGradient(
          colors: [Color(0xFF3A0000), Color(0xFF0A0A0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ) : null,
      ),
      padding: EdgeInsets.all(72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundImage: widget.review.profilePic.isNotEmpty
                   ? CachedNetworkImageProvider('https://vnc-e.com/Multimedia/Profiles/${widget.review.profilePic}')
                   : null,
                backgroundColor: Color(0xFF1E1E1E),
                child: widget.review.profilePic.isEmpty ? Icon(Icons.person, color: Colors.white, size: 60) : null,
              ),
              SizedBox(width: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.review.username, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 48)),
                  Text(_formatDate(widget.review.createdAt), style: TextStyle(color: Colors.grey[400], fontSize: 32)),
                ],
              )
            ],
          ),
          SizedBox(height: 64),
          Row(
            children: List.generate(5, (index) => Icon(
              index < widget.review.rating ? Icons.star : Icons.star_border,
              color: index < widget.review.rating ? Color(0xFFFFCC00) : Colors.white24,
              size: 64,
            )),
          ),
          SizedBox(height: 64),
          Text(
            widget.review.movieTitle.toUpperCase(),
            style: TextStyle(color: Color(0xFFE50914), fontSize: 64, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 48),
          Expanded(
            child: Text(
              '"${widget.review.comment}"',
              style: TextStyle(color: Colors.white, fontSize: 52, fontStyle: FontStyle.italic, height: 1.4),
              overflow: TextOverflow.ellipsis,
              maxLines: 10,
            ),
          ),
          if (includePageLink) ...[
            Divider(color: Colors.white12, thickness: 3),
            SizedBox(height: 32),
            Center(
              child: Text(
                'MIRA MÁS EN VANACUE',
                style: TextStyle(color: Colors.grey[500], fontSize: 28, letterSpacing: 4, fontWeight: FontWeight.bold),
              ),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildTicketMode() {
    final bgColor = isDarkBackground ? Color(0xFF0E0E0E) : Colors.white;
    final fgColor = isDarkBackground ? Colors.white : Colors.black;
    final lineWidget = Row(
      children: List.generate(
        30,
        (index) => Expanded(
          child: Container(
            color: index % 2 == 0 ? Colors.transparent : fgColor,
            height: 3,
          ),
        ),
      ),
    );

    return Container(
      color: bgColor,
      padding: EdgeInsets.symmetric(horizontal: 72, vertical: 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RECEIPT ID: #VN-${DateTime.now().year}-${widget.review.id.toString().padLeft(4, '0')}',
            textAlign: TextAlign.center,
            style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 48),
          lineWidget,
          SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('USUARIO:', style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36)),
              Text(widget.review.username, style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('FECHA:', style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36)),
              Text(_formatDate(widget.review.createdAt), style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 24),
          lineWidget,
          Spacer(flex: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) => Icon(
               index < widget.review.rating ? Icons.star : Icons.star_border,
               color: fgColor,
               size: 80,
            )),
          ),
          Spacer(flex: 1),
          Text(
            widget.review.movieTitle.toUpperCase(),
            textAlign: TextAlign.left,
            style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 56, fontWeight: FontWeight.w900, height: 1.2),
          ),
          SizedBox(height: 48),
          Text(
            '"${widget.review.comment}"',
            style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 44, height: 1.4),
          ),
          SizedBox(height: 64),
          lineWidget,
          Spacer(flex: 2),
          Text(
            '| | | |  | |  | | | |  | | |',
            textAlign: TextAlign.center,
            style: TextStyle(color: fgColor, fontSize: 80, letterSpacing: 8, fontWeight: FontWeight.w300),
          ),
          SizedBox(height: 48),
          Text(
            'GRACIAS POR COMPARTIR',
            textAlign: TextAlign.center,
            style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36),
          ),
          if (includePageLink) ...[
            SizedBox(height: 12),
            Text(
              'VANACUE',
              textAlign: TextAlign.center,
              style: TextStyle(color: fgColor, fontFamily: 'Courier', fontSize: 36, fontWeight: FontWeight.bold),
            ),
          ]
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final utcDate = DateFormat("yyyy-MM-dd HH:mm:ss").parse(dateStr, true);
      final localDate = utcDate.toLocal();
      const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
      return '${localDate.day} de ${months[localDate.month - 1]} de ${localDate.year}';
    } catch (e) {
      return dateStr;
    }
  }
}

class BackgroundPattern extends StatelessWidget {
  final Widget child;
  const BackgroundPattern({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black, // O fondo punteado
      child: Stack(
        children: [
           // Subtle pattern or texture could be added here
           Positioned.fill(
             child: Opacity(
               opacity: 0.1,
               child: CustomPaint(painter: GridPainter()),
             )
           ),
           Padding(
             padding: EdgeInsets.all(16),
             child: child,
           )
        ]
      )
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 20) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
