import 'dart:convert';

class Contenido {
  final dynamic tmdbId; // Can be int or string based on data
  final String titulo;
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
  final List<dynamic>? audios;
  final List<dynamic>? subtitulos;
  final String? enlaceTelegram;
  final double? postPlayExperience;

  Contenido({
    required this.tmdbId,
    required this.titulo,
    required this.tipo,
    required this.sinopsis,
    required this.genero,
    required this.portada,
    required this.backdrop,
    this.continueWatching,
    this.streamUrl,
    this.temporadas,
    this.premium = false,
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
      tmdbId: json['tmdbId'],
      titulo: json['titulo'] ?? 'Sin título',
      tipo: json['tipo'] ?? 'Desconocido',
      sinopsis: json['sinopsis'] ?? '',
      genero: (json['genero'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      portada: json['portada'] ?? '',
      backdrop: json['backdrop'] ?? '',
      continueWatching: json['continue_watching'],
      streamUrl: json['streamUrl'] ?? json['video'],
      premium: json['premium'] ?? false,
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
