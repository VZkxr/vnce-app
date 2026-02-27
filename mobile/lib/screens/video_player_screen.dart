import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final List<dynamic>? audios;
  final List<dynamic>? subtitulos;
  final Contenido? contentMaster;
  final String? episodeTitle;
  final Duration startPosition;
  final int? seasonIndex;
  final int? episodeIndex;
  final List<Contenido>? catalog;

  const VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    required this.title,
    this.audios,
    this.subtitulos,
    this.contentMaster,
    this.episodeTitle,
    this.startPosition = Duration.zero,
    this.seasonIndex,
    this.episodeIndex,
    this.catalog,
  }) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const _channel = MethodChannel('com.vnce.player');
  bool _launched = false;
  Contenido? _pickedRecommendation; // Store the picked recommendation

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchNativePlayer());
  }

  Future<void> _launchNativePlayer() async {
    if (_launched) return;
    _launched = true;

    String fullUrl = widget.videoUrl;
    if (!fullUrl.startsWith('http')) {
      fullUrl = 'https://vnc-e.com${fullUrl.startsWith('/') ? '' : '/'}$fullUrl';
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final username = authProvider.username ?? 'anonimo';

    if (fullUrl.contains('?')) {
      fullUrl = '$fullUrl&u=${Uri.encodeComponent(username)}';
    } else {
      fullUrl = '$fullUrl?u=${Uri.encodeComponent(username)}';
    }

    try {
      // Prepare subtitles
      List<Map<String, String>> subtitlesList = [];
      if (widget.subtitulos != null) {
        for (var sub in widget.subtitulos!) {
          var subUrl = sub['url'] ?? '';
          if (!subUrl.startsWith('http')) {
            subUrl = 'https://vnc-e.com${subUrl.startsWith('/') ? '' : '/'}$subUrl';
          }
          subtitlesList.add({
            'label': sub['label'] ?? 'Subtítulo',
            'lang': sub['lang'] ?? 'es',
            'url': subUrl,
          });
        }
      }

      // Post-play: pick recommendation ONCE and store it
      Map<String, dynamic>? postPlayData;
      final content = widget.contentMaster;
      final isMovie = content != null && !content.esSerie;
      final isLastEp = _isLastEpisodeOfLastSeason();

      if ((isMovie || isLastEp) && content != null && content.postPlayExperience != null) {
        _pickedRecommendation = _pickRecommendation();
        if (_pickedRecommendation != null) {
          postPlayData = {
            'triggerMinutes': content.postPlayExperience!,
            'recTitle': _pickedRecommendation!.titulo,
            'recSynopsis': _pickedRecommendation!.sinopsis,
            'recBackdrop': _pickedRecommendation!.backdrop ?? '',
            'hasStream': _pickedRecommendation!.streamUrl != null || 
                         (_pickedRecommendation!.esSerie && 
                          _pickedRecommendation!.temporadas != null &&
                          _pickedRecommendation!.temporadas!.isNotEmpty &&
                          _pickedRecommendation!.temporadas!.first.episodios.isNotEmpty &&
                          _pickedRecommendation!.temporadas!.first.episodios.first.streamUrl != null),
          };
        }
      }

      // Next episode
      Map<String, dynamic>? nextEpData;
      if (content != null && content.esSerie && !isLastEp) {
        final nextIdx = _getNextEpisode();
        if (nextIdx != null) {
          final currentEp = _getCurrentEpisode();
          final (nSIdx, nEIdx) = nextIdx;
          final nextSeason = content.temporadas![nSIdx];
          final nextEpisode = nextSeason.episodios[nEIdx];
          nextEpData = {
            'triggerMinutes': currentEp?.timeNextEpisode ?? 1.0,
            'title': 'T${nextSeason.numero}:E${nextEpisode.numero} - ${nextEpisode.titulo}',
          };
        }
      }

      final result = await _channel.invokeMethod('launchPlayer', {
        'videoUrl': fullUrl,
        'title': widget.title,
        'username': username,
        'startPosition': widget.startPosition.inMilliseconds,
        'subtitles': subtitlesList,
        if (postPlayData != null) 'postPlay': postPlayData,
        if (nextEpData != null) 'nextEpisode': nextEpData,
      });

      if (!mounted) return;

      if (result != null && result is Map) {
        final positionMs = (result['position'] as num?)?.toInt() ?? 0;
        final durationMs = (result['duration'] as num?)?.toInt() ?? 0;
        final action = result['action'] as String? ?? 'none';

        // Save/remove progress
        if (content != null && durationMs > 0 && positionMs > 0) {
          final positionSec = positionMs / 1000;
          final durationSec = durationMs / 1000;
          final remaining = durationSec - positionSec;
          final prov = Provider.of<ProgressProvider>(context, listen: false);

          // Check if we crossed the trigger boundaries
          bool crossedBoundary = false;
          int? parseTrigger(Map<String, dynamic>? data) {
            if (data == null) return null;
            double v = data['triggerMinutes'] as double;
            int m = v.toInt();
            int s = ((v - m) * 100).round();
            return m * 60 + s;
          }
          
          final ppTrigger = parseTrigger(postPlayData);
          final epTrigger = parseTrigger(nextEpData);
          
          if (ppTrigger != null && remaining <= ppTrigger) crossedBoundary = true;
          else if (epTrigger != null && remaining <= epTrigger) crossedBoundary = true;

          if (remaining < 60 || action == 'play_rec' || action == 'next_ep' || crossedBoundary) {
            prov.removeVideoProgress(generateProgressId(content, episodeTitle: widget.episodeTitle));
          } else {
            prov.saveVideoProgress(
              generateProgressId(content, episodeTitle: widget.episodeTitle),
              positionSec, durationSec, content,
              subtitulo: widget.episodeTitle,
              seasonIndex: widget.seasonIndex, episodeIndex: widget.episodeIndex,
            );
          }
        }

        if (action == 'play_rec') {
          _navigateToStoredRecommendation();
          return;
        } else if (action == 'next_ep') {
          _navigateToNextEpisode();
          return;
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        Navigator.pop(context);
      }
    }
  }

  /// Navigate to the STORED recommendation (the one shown in post-play)
  void _navigateToStoredRecommendation() {
    final rec = _pickedRecommendation;
    if (rec == null || !mounted) { if (mounted) Navigator.pop(context); return; }

    if (rec.esSerie) {
      if (rec.temporadas == null || rec.temporadas!.isEmpty ||
          rec.temporadas!.first.episodios.isEmpty ||
          rec.temporadas!.first.episodios.first.streamUrl == null) {
        _showNotAvailableAndPop();
        return;
      }
      final season = rec.temporadas!.first;
      final episode = season.episodios.first;
      final epStr = 'T${season.numero}:E${episode.numero} - ${episode.titulo}';
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: episode.streamUrl!, title: '${rec.titulo} - $epStr',
          audios: episode.audios, subtitulos: episode.subtitulos,
          contentMaster: rec, episodeTitle: epStr,
          seasonIndex: 0, episodeIndex: 0, catalog: widget.catalog,
        ),
      ));
    } else if (rec.streamUrl != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: rec.streamUrl!, title: rec.titulo,
          audios: rec.audios, subtitulos: rec.subtitulos,
          contentMaster: rec, catalog: widget.catalog,
        ),
      ));
    } else {
      _showNotAvailableAndPop();
    }
  }

  void _showNotAvailableAndPop() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No disponible en streaming'),
        backgroundColor: Colors.red.shade700,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context);
  }

  void _navigateToNextEpisode() {
    final content = widget.contentMaster;
    if (content == null || !mounted) { if (mounted) Navigator.pop(context); return; }
    final next = _getNextEpisode();
    if (next == null) { Navigator.pop(context); return; }
    final (sIdx, eIdx) = next;
    final season = content.temporadas![sIdx];
    final episode = season.episodios[eIdx];
    if (episode.streamUrl == null) { _showNotAvailableAndPop(); return; }
    final epStr = 'T${season.numero}:E${episode.numero} - ${episode.titulo}';
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(
        videoUrl: episode.streamUrl!, title: '${content.titulo} - $epStr',
        audios: episode.audios, subtitulos: episode.subtitulos,
        contentMaster: content, episodeTitle: epStr,
        seasonIndex: sIdx, episodeIndex: eIdx, catalog: widget.catalog,
      ),
    ));
  }

  Episodio? _getCurrentEpisode() {
    final c = widget.contentMaster;
    if (c == null || !c.esSerie || c.temporadas == null) return null;
    final sIdx = widget.seasonIndex ?? 0;
    final eIdx = widget.episodeIndex ?? 0;
    if (sIdx < c.temporadas!.length && eIdx < c.temporadas![sIdx].episodios.length) {
      return c.temporadas![sIdx].episodios[eIdx];
    }
    return null;
  }

  bool _isLastEpisodeOfLastSeason() {
    final c = widget.contentMaster;
    if (c == null || !c.esSerie || c.temporadas == null || c.temporadas!.isEmpty) return false;
    final sIdx = widget.seasonIndex ?? 0;
    final eIdx = widget.episodeIndex ?? 0;
    return sIdx == c.temporadas!.length - 1 && eIdx == c.temporadas!.last.episodios.length - 1;
  }

  (int, int)? _getNextEpisode() {
    final c = widget.contentMaster;
    if (c == null || !c.esSerie || c.temporadas == null) return null;
    final sIdx = widget.seasonIndex ?? 0;
    final eIdx = widget.episodeIndex ?? 0;
    if (eIdx + 1 < c.temporadas![sIdx].episodios.length) return (sIdx, eIdx + 1);
    if (sIdx + 1 < c.temporadas!.length && c.temporadas![sIdx + 1].episodios.isNotEmpty) return (sIdx + 1, 0);
    return null;
  }

  Contenido? _pickRecommendation() {
    if (widget.catalog == null || widget.catalog!.isEmpty) return null;
    final candidates = widget.catalog!.where((c) => c.tmdbId != widget.contentMaster?.tmdbId).toList();
    if (candidates.isEmpty) return null;
    candidates.shuffle();
    return candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
    );
  }
}
