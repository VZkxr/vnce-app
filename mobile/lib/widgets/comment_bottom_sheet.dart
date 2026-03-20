import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';

void showCommentBottomSheet(BuildContext context, Review review) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _CommentBottomSheet(review: review);
    },
  );
}

class _CommentBottomSheet extends StatefulWidget {
  final Review review;

  const _CommentBottomSheet({required this.review});

  @override
  __CommentBottomSheetState createState() => __CommentBottomSheetState();
}

class __CommentBottomSheetState extends State<_CommentBottomSheet> {
  final ApiService _apiService = ApiService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<ReviewComment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final response = await _apiService.fetchReviewComments(widget.review.id);
    if (response['success'] == true) {
      final List<dynamic> list = response['comments'] ?? [];
      setState(() {
        _comments = list.map((c) => ReviewComment.fromJson(c)).toList();
        _isLoading = false;
      });
      _scrollToBottom();
    } else {
      setState(() {
        _errorMessage = response['message'] ?? 'Error desconocido';
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.userRole == 'Free' || authProvider.userRole == 'free') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Esta acción requiere suscripción Premium'), backgroundColor: Color(0xFFE50914)),
      );
      return;
    }

    setState(() => _isSending = true);

    final success = await _apiService.postReviewComment(widget.review.id, text);
    if (success) {
      _commentController.clear();
      await _loadComments();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar el comentario'), backgroundColor: Colors.red),
      );
    }

    setState(() => _isSending = false);
  }

  String _formatDate(String dateStr) {
    try {
      final inputDate = dateStr.endsWith('Z') ? dateStr : '${dateStr}Z';
      final dt = DateTime.parse(inputDate).toLocal();
      const monthNames = ["Ene.", "Feb.", "Mar.", "Abr.", "May.", "Jun.", "Jul.", "Ago.", "Sep.", "Oct.", "Nov.", "Dic."];
      final month = monthNames[dt.month - 1];
      
      int hours = dt.hour;
      final ampm = hours >= 12 ? 'pm' : 'am';
      hours = hours % 12;
      hours = hours == 0 ? 12 : hours;
      final minutes = dt.minute.toString().padLeft(2, '0');
      
      return "${dt.day} $month a las $hours:$minutes $ampm ${dt.year}";
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final myUsername = authProvider.username;
    final isFree = authProvider.userRole == 'Free' || authProvider.userRole == 'free';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Color(0xFF131313),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Pull Bar
              Center(
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: 12),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Comentarios de "${widget.review.movieTitle}" por ${widget.review.username}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Divider(color: Colors.white10),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                    : _errorMessage != null
                        ? Center(child: Text(_errorMessage!, style: TextStyle(color: Colors.red)))
                        : _comments.isEmpty
                            ? Center(child: Text("Sé el primero en comentar.", style: TextStyle(color: Colors.grey[500])))
                            : ListView.builder(
                                controller: controller,
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: _comments.length,
                                itemBuilder: (context, index) {
                                  final comment = _comments[index];
                                  final isMe = comment.username == myUsername;
                                  final isAdmin = comment.role == 'admin';

                                  return _buildCommentBubble(comment, isMe, isAdmin);
                                },
                              ),
              ),
              // Input Area
              Container(
                padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  border: Border(top: BorderSide(color: Color(0xFF333333))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/${authProvider.profilePic}'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Color(0xFF333333)),
                        ),
                        child: TextField(
                          controller: _commentController,
                          style: TextStyle(color: Colors.white, fontSize: 14),
                          maxLines: 4,
                          minLines: 1,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: isFree ? 'Esta acción requiere suscripción Premium' : 'Añadir un comentario...',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                          ),
                          enabled: !isFree,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    if (!isFree)
                      _isSending
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2)),
                            )
                          : IconButton(
                              icon: Icon(Icons.send, color: Color(0xFFE50914)),
                              onPressed: _postComment,
                            )
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentBubble(ReviewComment comment, bool isMe, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isAdmin ? Border.all(color: Color(0xFFE50914), width: 2) : null,
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey[800],
                backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/${comment.profilePic}'),
              ),
            ),
            SizedBox(width: 8),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      comment.username, 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)
                    ),
                    if (isAdmin) ...[
                      SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: Color(0xFFE50914), borderRadius: BorderRadius.circular(2)),
                        child: Text('ADMIN', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    ]
                  ],
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? Color(0xFF4A0A0F) : Color(0xFF1E1E1E), // Reddish for me, grey for others
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: isMe ? Radius.circular(16) : Radius.circular(2),
                      bottomRight: isMe ? Radius.circular(2) : Radius.circular(16),
                    ),
                    border: isAdmin ? Border(left: BorderSide(color: Color(0xFFE50914), width: 3)) : null,
                  ),
                  child: Text(
                    comment.comment,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _formatDate(comment.createdAt),
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                )
              ],
            ),
          ),

          if (isMe) ...[
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isAdmin ? Border.all(color: Color(0xFFE50914), width: 2) : null,
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey[800],
                backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/${comment.profilePic}'),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
