import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ReviewsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Review> _reviews = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _currentPage = 1;
  bool _hasMore = true;
  String _currentSortOrder = 'recent'; // 'recent' or 'oldest'
  String _searchQuery = '';

  // Getters
  List<Review> get reviews {
    if (_searchQuery.isEmpty) return _reviews;
    String _normalize(String str) {
      return str.toLowerCase().replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u').replaceAll('ü', 'u');
    }
    final qNorm = _normalize(_searchQuery);
    return _reviews.where((r) => 
      _normalize(r.movieTitle).contains(qNorm) || 
      _normalize(r.username).contains(qNorm)
    ).toList();
  }
  
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  String get currentSortOrder => _currentSortOrder;

  /// Loads reviews from the API
  Future<void> loadReviews({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _reviews = [];
      _hasMore = true;
      _errorMessage = null;
    }

    if (!_hasMore || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.fetchReviews(page: _currentPage, limit: 10, order: _currentSortOrder);
      
      if (response['success'] == true && response['reviews'] != null) {
        final List<dynamic> reviewsData = response['reviews'];
        if (reviewsData.isEmpty) {
          _hasMore = false;
        } else {
          for (var item in reviewsData) {
            _reviews.add(Review.fromJson(item));
          }
          if (reviewsData.length < 10) _hasMore = false;
          _currentPage++;
        }
      } else {
        _errorMessage = response['message'] ?? 'Error fetching reviews';
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the sort order and reloads
  void setSortOrder(String order) {
    if (_currentSortOrder == order) return;
    _currentSortOrder = order;
    loadReviews(refresh: true);
  }

  /// Sets local search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Toggle like/dislike locally and sync backend
  Future<void> toggleReaction(int reviewId, String type) async {
    // Optimistic UI Update
    final index = _reviews.indexWhere((r) => r.id == reviewId);
    if (index == -1) return;

    final review = _reviews[index];
    int updatedLikes = review.likes;
    int updatedDislikes = review.dislikes;
    int updatedHasLiked = review.userHasLiked;
    int updatedHasDisliked = review.userHasDisliked;

    if (type == 'like') {
      if (updatedHasLiked == 1) { // Undo like
        updatedHasLiked = 0;
        updatedLikes = (updatedLikes > 0) ? updatedLikes - 1 : 0;
      } else { // Do like
        updatedHasLiked = 1;
        updatedLikes += 1;
        if (updatedHasDisliked == 1) { // Remove opposite
          updatedHasDisliked = 0;
          updatedDislikes = (updatedDislikes > 0) ? updatedDislikes - 1 : 0;
        }
      }
    } else if (type == 'dislike') {
      if (updatedHasDisliked == 1) { // Undo dislike
        updatedHasDisliked = 0;
        updatedDislikes = (updatedDislikes > 0) ? updatedDislikes - 1 : 0;
      } else { // Do dislike
        updatedHasDisliked = 1;
        updatedDislikes += 1;
        if (updatedHasLiked == 1) { // Remove opposite
          updatedHasLiked = 0;
          updatedLikes = (updatedLikes > 0) ? updatedLikes - 1 : 0;
        }
      }
    }

    _reviews[index] = review.copyWith(
      userHasLiked: updatedHasLiked,
      userHasDisliked: updatedHasDisliked,
      likes: updatedLikes,
      dislikes: updatedDislikes,
    );
    notifyListeners();

    // Sync with server
    final success = await _apiService.toggleReviewReaction(reviewId, type);
    if (!success) {
      // Revert if failed
      _reviews[index] = review;
      notifyListeners();
    }
  }

  /// Delete my review
  Future<bool> deleteReviewLocallyAndRemote(int reviewId) async {
    final success = await _apiService.deleteReview(reviewId);
    if (success) {
      _reviews.removeWhere((r) => r.id == reviewId);
      notifyListeners();
    }
    return success;
  }
}
