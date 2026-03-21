import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';

class ApiService {
  static const String baseUrl = 'https://vnc-e.com';
  
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Login to get JWT token
  Future<Map<String, dynamic>> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/api/login');
    print('Attempting login to: $url with user: $username');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      print('Login Response Status: ${response.statusCode}');
      print('Login Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await _saveToken(data['token']);
          
          final String trueUsername = data['user']?['username'] ?? username;
          await saveUser(trueUsername); // Save true username
          
          final String role = data['user']?['tipo_cuenta'] ?? data['user']?['role'] ?? 'Free';
          await _saveRole(role);
          
          final String profilePic = data['user']?['profile_pic'] ?? 'alucard.jpg';
          await saveProfilePic(profilePic);
          
          return {'success': true, 'token': data['token'], 'username': trueUsername};
        } else {
          return {'success': false, 'message': data['message'] ?? 'Usuario o contraseña incorrectos'};
        }
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Usuario o contraseña incorrectos'};
      }
    } catch (e) {
      print('Login Error: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  /// Verify session (Heartbeat)
  Future<bool> verifySession() async {
    final token = await getToken();
    final username = await getUser();
    if (token == null) return false;

    // Based on script.js: verifySessionActiva
    // URL: /api/ping?t=...&u=...
    try {
      final uri = Uri.parse('$baseUrl/api/ping').replace(queryParameters: {
        't': DateTime.now().millisecondsSinceEpoch.toString(),
        'u': username ?? 'anonimo'
      });

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // If success is false, session is invalid
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Session check failed: $e');
      return false; // Fail safe
    }
  }

  /// Fetch Catalog (datos.json)
  Future<List<Contenido>> fetchCatalog() async {
    final url = Uri.parse('$baseUrl/datos.json?v=${DateTime.now().millisecondsSinceEpoch}');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((json) => Contenido.fromJson(json)).toList();
      } else {
        throw Exception('Error al cargar datos desde el servidor: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading catalog from network: $e');
      throw Exception('Error de carga de red: $e');
    }
  }

  /// Fetch Hero Slider Data (hero.json)
  Future<List<HeroItem>> fetchHeroData() async {
    final url = Uri.parse('$baseUrl/hero.json?v=${DateTime.now().millisecondsSinceEpoch}');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((json) => HeroItem.fromJson(json)).toList();
      } else {
        print('Error loading hero: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching hero: $e');
      return [];
    }
  }

  // --- REGISTRATION & RECOVERY ---

  Future<Map<String, dynamic>> checkUsername(String username) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/check-username'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'available': false, 'error': 'Error de conexión'};
    }
  }

  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'email': email, 'password': password}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  Future<Map<String, dynamic>> verifyCode(String username, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/verify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'code': code}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'code': code, 'newPassword': newPassword}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  Future<Map<String, dynamic>> updateUsername(String token, String newUsername, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/update-username'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'newUsername': newUsername, 'password': password}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  Future<Map<String, dynamic>> updateProfilePic(String token, String profilePic) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/update-profile-pic'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'profilePic': profilePic}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  // --- Token Management ---
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vanacue_token', token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('vanacue_token');
  }

  Future<void> saveUser(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vanacue_user', username);
  }

  Future<String?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('vanacue_user');
  }
  
  Future<void> _saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vanacue_role', role);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('vanacue_role');
  }
  
  Future<void> saveProfilePic(String profilePic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vanacue_profile_pic', profilePic);
  }

  Future<String?> getProfilePic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('vanacue_profile_pic');
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vanacue_token');
    await prefs.remove('vanacue_user');
    await prefs.remove('vanacue_role');
    await prefs.remove('vanacue_profile_pic');
  }
  // --- FAVORITES SYSTEM ---

  Future<List<dynamic>> getFavorites(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['favorites'] ?? [];
        }
      }
    } catch (e) {
      print('Error fetching favorites: $e');
    }
    return [];
  }

  // --- NOTIFICATIONS SYSTEM ---

  Future<List<Notificacion>> getNotifications(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['notifications'] != null) {
          final List<dynamic> list = data['notifications'];
          return list.map((json) => Notificacion.fromJson(json)).toList();
        }
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
    return [];
  }

  Future<bool> createNotification(String token, String title, String message, String type) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/notifications'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'title': title, 'message': message, 'type': type}),
      );
      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('Error creating notification: $e');
      return false;
    }
  }

  Future<bool> deleteNotification(String token, int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/notifications/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('Error deleting notification: $e');
      return false;
    }
  }

  Future<bool> addFavorite(String token, Contenido item) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/favorites/add'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'movie_tmdb_id': item.tmdbId,
          'movie_title': item.titulo,
          'poster_path': item.portada,
        }),
      );
      
      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error adding favorite: $e');
      return false;
    }
  }

  Future<bool> removeFavorite(String token, dynamic tmdbId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/favorites/remove'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'movie_tmdb_id': tmdbId,
        }),
      );

      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error removing favorite: $e');
      return false;
    }
  }

  // =====================================
  // ⭐ REVIEWS & COMMENTS (NUEVO SISTEMA)
  // =====================================

  Future<Map<String, dynamic>> fetchReviews({int page = 1, int limit = 10, String order = 'recent'}) async {
    try {
      final token = await getToken();
      final url = Uri.parse('$baseUrl/api/reviews?page=$page&limit=$limit&order=$order');
      final response = await http.get(
        url,
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      print('Error fetching reviews: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> createReview({
    required dynamic tmdbId,
    required String title,
    required String type,
    required String year,
    required int rating,
    required String comment,
  }) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final url = Uri.parse('$baseUrl/api/reviews');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'tmdb_id': tmdbId,
          'movie_title': title,
          'movie_type': type,
          'movie_year': year,
          'rating': rating,
          'comment': comment,
        }),
      );
      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error creating review: $e');
      return false;
    }
  }

  Future<bool> toggleReviewReaction(int reviewId, String type) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final url = Uri.parse('$baseUrl/api/reviews/like');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'review_id': reviewId,
          'type': type,
        }),
      );
      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error toggling reaction: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchReviewComments(int reviewId) async {
    try {
      final token = await getToken();
      final url = Uri.parse('$baseUrl/api/reviews/$reviewId/comments');
      final response = await http.get(
        url,
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      print('Error fetching comments: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> postReviewComment(int reviewId, String comment) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final url = Uri.parse('$baseUrl/api/reviews/comment');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'review_id': reviewId,
          'comment': comment,
        }),
      );
      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error posting comment: $e');
      return false;
    }
  }

  Future<bool> deleteReview(int reviewId) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final url = Uri.parse('$baseUrl/api/reviews/$reviewId');
      final response = await http.delete(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error deleting review: $e');
      return false;
    }
  }

  Future<bool> deleteComment(int commentId) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final url = Uri.parse('$baseUrl/api/reviews/comment/$commentId');
      final response = await http.delete(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = json.decode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Error deleting comment: $e');
      return false;
    }
  }
}
