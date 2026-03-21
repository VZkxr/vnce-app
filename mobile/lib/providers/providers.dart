import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isInitializing = true;
  String? _username;
  String _userRole = 'Free';
  String _profilePic = 'alucard.jpg';

  bool get isAuthenticated => _isAuthenticated;
  bool get isInitializing => _isInitializing;
  String? get username => _username;
  String get userRole => _userRole;
  String get profilePic => _profilePic;

  final ApiService _api = ApiService();
  ApiService get api => _api; // Expose api for login_screen to use

  AuthProvider() {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    _isInitializing = true;
    notifyListeners();

    final token = await _api.getToken();
    if (token != null) {
      // Validate token with server
      final isValid = await _api.verifySession();
      if (isValid) {
        _isAuthenticated = true;
        _username = await _api.getUser();
        _userRole = await _api.getRole() ?? 'Free';
        _profilePic = await _api.getProfilePic() ?? 'alucard.jpg';
      } else {
        await logout(); // Invalid token
      }
    } else {
      _isAuthenticated = false;
    }

    _isInitializing = false;
    notifyListeners();
  }

  Future<String?> login(String username, String password) async {
    final result = await _api.login(username, password);
    
    if (result['success']) {
      _isAuthenticated = true;
      _username = result['username'] ?? username;
      _userRole = await _api.getRole() ?? 'Free';
      _profilePic = await _api.getProfilePic() ?? 'alucard.jpg';
      notifyListeners();
      return null; // Return null on success
    } else {
      notifyListeners();
      return result['message'] ?? 'Usuario o contraseña incorrectos';
    }
  }

  Future<Map<String, dynamic>> changeUsername(String newUsername, String password) async {
    final token = await _api.getToken();
    if (token == null) return {'success': false, 'message': 'No autenticado'};
    
    final result = await _api.updateUsername(token, newUsername, password);
    if (result['success'] == true) {
      _username = newUsername;
      await _api.saveUser(newUsername);
      notifyListeners();
    }
    return result;
  }

  Future<bool> updateProfilePic(String newPic) async {
    final token = await _api.getToken();
    if (token == null) return false;

    final result = await _api.updateProfilePic(token, newPic);
    if (result['success'] == true) {
      _profilePic = newPic;
      await _api.saveProfilePic(newPic);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _api.logout();
    _isAuthenticated = false;
    _username = null;
    _userRole = 'Free';
    _profilePic = 'alucard.jpg';
    notifyListeners();
  }
}

class ContentProvider with ChangeNotifier {
  List<Contenido> _catalogo = [];
  bool _isLoading = false;
  String? _error;

  List<Contenido> get catalogo => _catalogo;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final ApiService _api = ApiService();

  Future<void> loadCatalog() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _catalogo = await _api.fetchCatalog();
      // Reverse to show newest first as per web app logic
      _catalogo = _catalogo.reversed.toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  List<Contenido> getByGenre(String genre) {
    if (genre == 'Recién agregadas') return _catalogo.take(20).toList();
    
    return _catalogo.where((c) => 
      c.genero.any((g) => g.toLowerCase() == genre.toLowerCase())
    ).toList();
  }
}

class NotificationProvider with ChangeNotifier {
  List<Notificacion> _notifications = [];
  bool _isLoading = false;

  List<Notificacion> get notifications => _notifications;
  bool get isLoading => _isLoading;

  final ApiService _api = ApiService();

  Future<void> fetchNotifications() async {
    final token = await _api.getToken();
    if (token == null) return;

    _isLoading = true;
    notifyListeners();

    _notifications = await _api.getNotifications(token);

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createNotification(String title, String message, String type) async {
    final token = await _api.getToken();
    if (token == null) return false;

    final success = await _api.createNotification(token, title, message, type);
    if (success) {
      await fetchNotifications(); // Refresh list automatically
    }
    return success;
  }

  Future<bool> deleteNotification(int id) async {
    final token = await _api.getToken();
    if (token == null) return false;

    final success = await _api.deleteNotification(token, id);
    if (success) {
      _notifications.removeWhere((n) => n.id == id);
      notifyListeners();
    }
    return success;
  }
}

class ProgressProvider with ChangeNotifier {
  Map<String, Map<String, dynamic>> _progressData = {};
  bool _isLoading = false;

  Map<String, Map<String, dynamic>> get progressData => _progressData;
  bool get isLoading => _isLoading;

  ProgressProvider() {
    loadProgress();
  }

  Future<void> loadProgress() async {
    _isLoading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString('vanacue_video_progress');
    if (dataStr != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(dataStr);
        _progressData = decoded.map((key, value) => MapEntry(key, value as Map<String, dynamic>));
      } catch (e) {
        _progressData = {};
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveVideoProgress(String id, double time, double duration, Contenido dataMaestra, {String? subtitulo, int? seasonIndex, int? episodeIndex}) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Auto-remove if > 95%
    if (duration > 0 && (time / duration) > 0.95) {
      _progressData.remove(id);
    } else {
      _progressData[id] = {
        'time': time,
        'duration': duration,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'titulo': dataMaestra.titulo,
        'subtitulo': subtitulo,
        'esSerie': dataMaestra.esSerie,
        'continue_watching': dataMaestra.continueWatching,
        'backdrop': dataMaestra.backdrop,
        'portada': dataMaestra.portada,
        'tmdbId': dataMaestra.tmdbId,
        'seasonIndex': seasonIndex,
        'episodeIndex': episodeIndex,
      };
    }
    
    await prefs.setString('vanacue_video_progress', json.encode(_progressData));
    notifyListeners();
  }

  double getVideoProgress(String id) {
    if (_progressData.containsKey(id)) {
      final item = _progressData[id];
      if (item != null && item['time'] != null) {
        return (item['time'] as num).toDouble();
      }
    }
    return 0.0;
  }

  Future<void> removeVideoProgress(String id) async {
    final prefs = await SharedPreferences.getInstance();
    _progressData.remove(id);
    await prefs.setString('vanacue_video_progress', json.encode(_progressData));
    notifyListeners();
  }
}

String generateProgressId(Contenido c, {String? episodeTitle}) {
  String baseTitle = episodeTitle ?? c.titulo;
  return baseTitle.replaceAll(' ', '_').toLowerCase() + '_' + (c.fecha ?? '');
}
