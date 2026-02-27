import re
import os

filepath = r"lib/screens/video_player_screen.dart"
with open(filepath, "r", encoding="utf-8") as f:
    code = f.read()

# 1. Imports
code = code.replace(
    "import 'package:media_kit/media_kit.dart';",
    "import 'package:flutter_vlc_player/flutter_vlc_player.dart';"
)
code = code.replace(
    "import 'package:media_kit_video/media_kit_video.dart';",
    ""
)

# 2. State Variables
code = re.sub(
    r"late final Player _player;\s+late final VideoController _videoController;",
    r"late final VlcPlayerController _videoController;",
    code
)
code = re.sub(
    r"List<AudioTrack> _audioTracks = \[\];\s+List<SubtitleTrack> _subtitleTracks = \[\];\s+AudioTrack _activeAudioTrack = AudioTrack.auto\(\);\s+SubtitleTrack _activeSubtitleTrack = SubtitleTrack.auto\(\);",
    r"Map<int, String> _audioTracks = {};\n  Map<int, String> _subtitleTracks = {};\n  int? _activeAudioTrack;\n  int? _activeSubtitleTrack;",
    code
)

# 3. Init State 
code = code.replace(
    "_player = Player();\n    _videoController = VideoController(_player);",
    "// VLC initialized in tracking method"
)

# 4. _initPlayer definition
init_player_vlc = """  Future<void> _initPlayer(String fullUrl) async {
    _videoController = VlcPlayerController.network(
      fullUrl,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(
        http: VlcHttpOptions([
          VlcHttpOptions.httpReconnect(true),
        ]),
        extras: [
          '--http-referrer=https://vnc-e.com',
          '--http-user-agent=VanacueMobile/1.0',
        ],
      ),
    );
    _setupListeners();
    // Inject external sub early if present
    if (widget.subtitulos != null && widget.subtitulos!.isNotEmpty) {
        var subUrl = widget.subtitulos!.first['url'];
        if (!subUrl.startsWith('http')) {
           subUrl = 'https://vnc-e.com${subUrl.startsWith('/') ? '' : '/'}$subUrl';
        }
        _selectedSubtitleIdentifier = widget.subtitulos!.first['label'] ?? 'Subtítulo';
        await _videoController.addSubtitleFromNetwork(subUrl, isSelected: true);
    }
  }"""

code = re.sub(
    r"Future<void> _initPlayer\(String fullUrl\) async \{.*?\n  \}",
    init_player_vlc,
    code,
    flags=re.DOTALL
)

# Remove the old _setupListeners call before _initPlayer
code = code.replace("    _setupListeners();\n    _startHideTimer();\n\n    _initPlayer(fullUrl);", "    _startHideTimer();\n\n    _initPlayer(fullUrl);")

# 5. _setupListeners
vlc_listener = """  void _setupListeners() {
    _videoController.addListener(() async {
      if (!mounted) return;
      final value = _videoController.value;
      
      bool playing = value.isPlaying;
      bool buffering = value.isBuffering;
      Duration position = value.position;
      Duration duration = value.duration;

      if (_isPlaying != playing) setState(() => _isPlaying = playing);
      
      if (_isBuffering != buffering) {
        final wasBuffering = _isBuffering;
        setState(() => _isBuffering = buffering);
        if (wasBuffering && !buffering && !_hasPlaybackStarted) {
          _hasPlaybackStarted = true;
        }
      }

      if (!_isDragging && _hasPlaybackStarted) {
         setState(() => _position = position);
      }

      if (_duration != duration && duration > Duration.zero) {
         setState(() => _duration = duration);
         if (!_initialSeekDone && widget.startPosition > Duration.zero) {
             _videoController.seekTo(widget.startPosition);
             _initialSeekDone = true;
         }
      }

      // Track extraction
      final audioTracksMap = await _videoController.getAudioTracks();
      final subTracksMap = await _videoController.getSpuTracks();
      final activeA = await _videoController.getAudioTrack();
      final activeS = await _videoController.getSpuTrack();
      
      if (mounted) {
         setState(() {
            _audioTracks = audioTracksMap;
            _subtitleTracks = subTracksMap;
            _activeAudioTrack = activeA;
            _activeSubtitleTrack = activeS;
         });
      }

      // Progress Tracker 
      if (_hasPlaybackStarted && !_showPostPlay && !_showNextEpisode && position.inSeconds > 0 && position.inSeconds % 5 == 0 && widget.contentMaster != null && duration.inSeconds > 0) {
          final provider = Provider.of<ProgressProvider>(context, listen: false);
          provider.saveVideoProgress(
            generateProgressId(widget.contentMaster!, episodeTitle: widget.episodeTitle),
            position.inSeconds.toDouble(),
            duration.inSeconds.toDouble(),
            widget.contentMaster!,
            subtitulo: widget.episodeTitle,
            seasonIndex: widget.seasonIndex,
            episodeIndex: widget.episodeIndex,
          );
      }
      
      // Post-Play Checks
      if (duration.inSeconds > 0 && widget.contentMaster != null) {
          final remaining = duration.inSeconds - position.inSeconds;
          final content = widget.contentMaster!;
          final isMovie = !content.esSerie;
          final isLastEp = _isLastEpisodeOfLastSeason();

          if ((isMovie || isLastEp) && content.postPlayExperience != null && !_postPlayDismissed) {
            final threshold = _parseTimeValue(content.postPlayExperience!);
            if (remaining <= threshold && !_showPostPlay) {
              _nextRecommendation ??= _pickRecommendation();
              if (_nextRecommendation != null) {
                setState(() => _showPostPlay = true);
              }
              final provider = Provider.of<ProgressProvider>(context, listen: false);
              provider.removeVideoProgress(generateProgressId(content, episodeTitle: widget.episodeTitle));
            }
          }

          if (content.esSerie && !isLastEp && !_nextEpDismissed) {
             final sIdx = widget.seasonIndex ?? 0;
             final eIdx = widget.episodeIndex ?? 0;
             if (content.temporadas != null && sIdx < content.temporadas!.length) {
                final episode = content.temporadas![sIdx].episodios[eIdx];
                if (episode.timeNextEpisode != null) {
                   final threshold = _parseTimeValue(episode.timeNextEpisode!);
                   if (remaining <= threshold && !_showNextEpisode) {
                      setState(() => _showNextEpisode = true);
                      final provider = Provider.of<ProgressProvider>(context, listen: false);
                      provider.removeVideoProgress(generateProgressId(content, episodeTitle: widget.episodeTitle));
                   }
                }
             }
          }
      }
    });
  }"""
  
code = re.sub(
    r"void _setupListeners\(\) \{.*?\n  \}",
    vlc_listener,
    code,
    flags=re.DOTALL
)

# 6. Audio / Sub UI Tracks
# Find the entire bottom sheet UI inside _showSettingsModal
audio_ui_replacement = """                ..._audioTracks.entries.where((e) => e.value.toLowerCase() != 'disable').map((entry) {
                   String label = entry.value;
                   final String lowerLabel = label.toLowerCase();
                   
                   if (lowerLabel.contains('spa') || lowerLabel.contains('español') || lowerLabel == 'es') {
                     label = 'Español Latino';
                   } else if (lowerLabel.contains('eng') || lowerLabel.contains('inglés') || lowerLabel == 'en') {
                     label = 'Inglés';
                   } else if (lowerLabel.contains('fre') || lowerLabel.contains('francés') || lowerLabel == 'fr') {
                     label = 'Francés';
                   }
                   
                   bool isSelected = _activeAudioTrack == entry.key;

                   return ListTile(
                     title: Text(label, style: TextStyle(color: isSelected ? Color(0xFFE50914) : Colors.white)),
                     trailing: isSelected ? Icon(Icons.check, color: Color(0xFFE50914)) : null,
                     contentPadding: EdgeInsets.zero,
                     dense: true,
                     onTap: () {
                       _videoController.setAudioTrack(entry.key);
                       Navigator.pop(context);
                     }
                   );
                }).toList(),

                SizedBox(height: 16),
                
                Text('Subtítulos', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                
                ListTile(
                     title: Text('Desactivado', style: TextStyle(color: _activeSubtitleTrack == -1 || _selectedSubtitleIdentifier == 'no' ? Color(0xFFE50914) : Colors.white)),
                     trailing: _activeSubtitleTrack == -1 || _selectedSubtitleIdentifier == 'no' ? Icon(Icons.check, color: Color(0xFFE50914)) : null,
                     contentPadding: EdgeInsets.zero,
                     dense: true,
                     onTap: () {
                       setState(() => _selectedSubtitleIdentifier = 'no');
                       _videoController.setSpuTrack(-1);
                       Navigator.pop(context);
                     }
                ),

                ..._subtitleTracks.entries.where((e) => e.value.toLowerCase() != 'disable').map((entry) {
                     String label = entry.value;
                     
                     bool isSelectedSub = _selectedSubtitleIdentifier == label.trim() || _activeSubtitleTrack == entry.key;
                     
                     return ListTile(
                       title: Text(label, style: TextStyle(color: isSelectedSub ? Color(0xFFE50914) : Colors.white)),
                       trailing: isSelectedSub ? Icon(Icons.check, color: Color(0xFFE50914)) : null,
                       contentPadding: EdgeInsets.zero,
                       dense: true,
                       onTap: () {
                         setState(() => _selectedSubtitleIdentifier = label.trim());
                         _videoController.setSpuTrack(entry.key);
                         Navigator.pop(context);
                       }
                     );
                }).toList(),"""

code = re.sub(
    r"\.\.\._audioTracks\.where.*?\}\)\(\),",
    audio_ui_replacement,
    code,
    flags=re.DOTALL
)

# 7. Disposals
code = code.replace("_player.dispose();", "_videoController.dispose();")

# 8. Video Player Display
video_widget_vlc = """              child: VlcPlayer(
                controller: _videoController,
                aspectRatio: 16 / 9,
                placeholder: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
              ),"""
              
code = re.sub(
    r"child: Video\(.*?padding: EdgeInsets\.all\(24\.0\),\s+\),\s+\),",
    video_widget_vlc,
    code,
    flags=re.DOTALL
)

# PostPlay Video widget replacement (small video preview)
video_widget_small_vlc = """                                child: VlcPlayer(
                                  controller: _videoController,
                                  aspectRatio: 16 / 9,
                                  placeholder: Container(color: Colors.black),
                                ),"""
                                
code = re.sub(
    r"child: Video\(\s+controller: _videoController,\s+controls: NoVideoControls,\s+\),",
    video_widget_small_vlc,
    code,
    flags=re.DOTALL
)

# 9. Generic play controls
code = code.replace("_player.pause()", "_videoController.pause()")
code = code.replace("_player.play()", "_videoController.play()")
code = code.replace("_player.seek(", "_videoController.seekTo(")


with open(filepath, "w", encoding="utf-8") as f:
    f.write(code)
    print("Migration script executed.")
