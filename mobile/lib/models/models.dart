import 'dart:convert';

class Contenido {
  final dynamic tmdbId; // Can be int or string based on data
  final String titulo;
  final String? tituloOriginal;
  final String tipo; // "Película" or "Serie"
  final String sinopsis;
  final List<String> genero;
  final String portada;
  final String backdrop;
  final String? continueWatching;
  final String? streamUrl; // Only for movies
  final List<Temporada>? temporadas; // Only for series
  final String? director;
  final String? reparto;
  final String? duracion;
  final String? fecha;
  final String? match;
  final bool premium;
  final bool popular;
  final List<dynamic>? audios;
  final List<dynamic>? subtitulos;
  final String? enlaceTelegram;
  final double? postPlayExperience;

  Contenido({
    required this.tmdbId,
    required this.titulo,
    this.tituloOriginal,
    required this.tipo,
    required this.sinopsis,
    required this.genero,
    required this.portada,
    required this.backdrop,
    this.continueWatching,
    this.streamUrl,
    this.temporadas,
    this.premium = false,
    this.popular = false,
    this.director,
    this.reparto,
    this.duracion,
    this.fecha,
    this.match,
    this.audios,
    this.subtitulos,
    this.enlaceTelegram,
    this.postPlayExperience,
  });

  factory Contenido.fromJson(Map<String, dynamic> json) {
    // Handle reparto/elenco as String or List
    String? repartoParsed;
    var rawReparto = json['reparto'] ?? json['elenco']; // Check both keys
    
    if (rawReparto is List) {
      repartoParsed = (rawReparto as List).join(', ');
    } else {
      repartoParsed = rawReparto;
    }

    return Contenido(
      tmdbId: json['tmdbId'] ?? json['id'] ?? 0,
      titulo: json['titulo'] ?? '',
      tituloOriginal: json['titulo_original'] ?? json['tituloOriginal'],
      tipo: json['tipo'] ?? 'Película',
      sinopsis: json['sinopsis'] ?? '',
      genero: (json['genero'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      portada: json['portada'] ?? '',
      backdrop: json['backdrop'] ?? '',
      continueWatching: json['continue_watching'],
      streamUrl: json['streamUrl'] ?? json['video'],
      premium: json['premium'] ?? false,
      popular: json['popular'] != null && json['popular'].toString().trim().toLowerCase() == 'true',
      temporadas: json['temporadas'] != null
          ? (json['temporadas'] as List).map((i) => Temporada.fromJson(i)).toList()
          : null,
      director: json['director'] ?? 'Desconocido',
      reparto: repartoParsed ?? 'No disponible',
      duracion: json['duracion'] ?? '0 min',
      fecha: json['fecha'],
      match: json['match'] ?? '90%', 
      audios: json['audios'],
      subtitulos: json['subtitulos'],
      enlaceTelegram: json['enlaceTelegram'],
      postPlayExperience: json['post-play_experience']?.toDouble(),
    );
  }

  bool get esSerie => tipo == 'Serie';
}

class Temporada {
  final int numero;
  final String nombre;
  final List<Episodio> episodios;

  Temporada({
    required this.numero,
    required this.nombre,
    required this.episodios,
  });

  factory Temporada.fromJson(Map<String, dynamic> json) {
    return Temporada(
      numero: json['numero'] ?? 0,
      nombre: json['nombre'] ?? '',
      episodios: (json['episodios'] as List)
          .map((i) => Episodio.fromJson(i))
          .toList(),
    );
  }
}

class Episodio {
  final int numero; // 'episodio' in JSON
  final String titulo;
  final String sinopsis;
  final String? streamUrl;
  final String? imagen;
  final String? duracion;
  final List<dynamic>? audios;
  final List<dynamic>? subtitulos;
  final double? timeNextEpisode;

  Episodio({
    required this.numero,
    required this.titulo,
    required this.sinopsis,
    this.streamUrl,
    this.imagen,
    this.duracion,
    this.audios,
    this.subtitulos,
    this.timeNextEpisode,
  });

  factory Episodio.fromJson(Map<String, dynamic> json) {
    return Episodio(
      numero: json['episodio'] ?? 0,
      titulo: json['titulo'] ?? '',
      sinopsis: json['sinopsis'] ?? '',
      streamUrl: json['streamUrl'] ?? json['video'],
      imagen: json['imagen'],
      duracion: json['duracion'],
      audios: json['audios'],
      subtitulos: json['subtitulos'],
      timeNextEpisode: json['time_next_episode']?.toDouble(),
    );
  }
}

class HeroItem {
  final String titulo;
  final String imagen;
  final String? logo;
  final String subtitulo;
  final String? enlaceTelegram;
  final double? postPlayExperience;

  HeroItem({
    required this.titulo,
    required this.imagen,
    this.logo,
    required this.subtitulo,
    this.enlaceTelegram,
    this.postPlayExperience,
  });

  factory HeroItem.fromJson(Map<String, dynamic> json) {
    return HeroItem(
      titulo: json['titulo'] ?? '',
      imagen: json['imagen'] ?? '',
      logo: json['logo'],
      subtitulo: json['subtitulo'] ?? '',
      enlaceTelegram: json['enlaceTelegram'],
    );
  }
}

class Notificacion {
  final int id;
  final String title;
  final String message;
  final String type;
  final String createdAt;

  Notificacion({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    return Notificacion(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: json['type'] ?? 'info',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class Review {
  final int id;
  final int userHasLiked;
  final int userHasDisliked;
  final String profilePic;
  final String username;
  final String createdAt;
  final int rating;
  final String movieTitle;
  final String movieYear;
  final String comment;
  final int likes;
  final int dislikes;
  final int commentsCount;

  Review({
    required this.id,
    required this.userHasLiked,
    required this.userHasDisliked,
    required this.profilePic,
    required this.username,
    required this.createdAt,
    required this.rating,
    required this.movieTitle,
    required this.movieYear,
    required this.comment,
    required this.likes,
    required this.dislikes,
    required this.commentsCount,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] ?? 0,
      userHasLiked: json['user_has_liked'] ?? 0,
      userHasDisliked: json['user_has_disliked'] ?? 0,
      profilePic: json['profile_pic'] ?? 'alucard.jpg',
      username: json['username'] ?? 'Usuario',
      createdAt: json['created_at'] ?? '',
      rating: json['rating'] ?? 0,
      movieTitle: json['movie_title'] ?? '',
      movieYear: json['movie_year']?.toString() ?? '',
      comment: json['comment'] ?? '',
      likes: json['likes'] ?? 0,
      dislikes: json['dislikes'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
    );
  }
  
  Review copyWith({
    int? userHasLiked,
    int? userHasDisliked,
    int? likes,
    int? dislikes,
    int? commentsCount,
  }) {
    return Review(
      id: this.id,
      userHasLiked: userHasLiked ?? this.userHasLiked,
      userHasDisliked: userHasDisliked ?? this.userHasDisliked,
      profilePic: this.profilePic,
      username: this.username,
      createdAt: this.createdAt,
      rating: this.rating,
      movieTitle: this.movieTitle,
      movieYear: this.movieYear,
      comment: this.comment,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      commentsCount: commentsCount ?? this.commentsCount,
    );
  }
}

class ReviewComment {
  final int id;
  final String role;
  final String username;
  final String profilePic;
  final String createdAt;
  final String comment;

  ReviewComment({
    required this.id,
    required this.role,
    required this.username,
    required this.profilePic,
    required this.createdAt,
    required this.comment,
  });

  factory ReviewComment.fromJson(Map<String, dynamic> json) {
    return ReviewComment(
      id: json['id'] ?? 0,
      role: json['role'] ?? 'free',
      username: json['username'] ?? 'Usuario',
      profilePic: json['profile_pic'] ?? 'alucard.jpg',
      createdAt: json['created_at'] ?? '',
      comment: json['comment'] ?? '',
    );
  }
}
