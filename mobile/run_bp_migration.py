import re
import os

filepath = 'lib/screens/video_player_screen.dart'
bakpath = 'lib/screens/video_player_screen.dart.bak'

with open(bakpath, 'r', encoding='utf-8') as f:
    code = f.read()

# Replace Imports
code = code.replace("import 'package:flutter_vlc_player/flutter_vlc_player.dart';", "import 'package:better_player/better_player.dart';")

# Replace Controller definitions
code = code.replace("VlcPlayerController _videoController;", "late BetterPlayerController _videoController;")
code = code.replace("late VlcPlayerController _videoController;", "late BetterPlayerController _videoController;")

# 1. Rewrite _initPlayer
init_pattern = r'Future<void> _initPlayer\(String fullUrl\) async \{.*?\s+await _videoController\.addSubtitleFromNetwork[^\}]+\}\s*\}'
bp_init = """Future<void> _initPlayer(String fullUrl) async {
    List<BetterPlayerSubtitlesSource> externalSubs = [];
    if (widget.subtitulos != null && widget.subtitulos!.isNotEmpty) {
      for (var sub in widget.subtitulos!) {
        var subUrl = sub['url'];
        if (!subUrl.startsWith('http')) {
          subUrl = 'https://vnc-e.com${subUrl.startsWith('/') ? '' : '/'}$subUrl';
        }
        externalSubs.add(BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          urls: [subUrl],
          name: sub['label'] ?? 'Subtítulo',
          selectedByDefault: true,
        ));
      }
    }

    BetterPlayerDataSource dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      fullUrl,
      subtitles: externalSubs,
      liveStream: false,
      headers: {
        'Referer': 'https://vnc-e.com',
        'User-Agent': 'VanacueMobile/1.0',
      },
    );

    _videoController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        aspectRatio: 16 / 9,
        fit: BoxFit.contain,
        autoDetectFullscreenDeviceOrientation: true,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      ),
      betterPlayerDataSource: dataSource,
    );
    _setupListeners();
  }"""
code = re.sub(init_pattern, bp_init, code, flags=re.DOTALL)

# 2. Rewrite UI Wrapper
code = code.replace("""VlcPlayer(
                controller: _videoController,
                aspectRatio: 16 / 9,
                placeholder: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
              )""", """BetterPlayer(
                controller: _videoController,
              )""")

# 3. Rewrite _setupListeners
listener_pattern = r'void _setupListeners\(\) \{.*?\s+_videoController\.addListener\(\(\) async \{.*?\s+final value = _videoController\.value;\s+bool playing = value\.isPlaying;\s+bool buffering = value\.isBuffering;\s+Duration position = value\.position;\s+Duration duration = value\.duration;.*?\s+if \(_hasPlaybackStarted && !_tracksExtracted\) \{.*?\}.*?\}'
bp_listener = """void _setupListeners() {
    _videoController.addEventsListener((BetterPlayerEvent event) {
      if (!mounted) return;
      
      final val = _videoController.videoPlayerController?.value;
      if (val == null) return;
      
      bool playing = val.isPlaying;
      bool buffering = val.isBuffering;
      Duration position = val.position;
      Duration duration = val.duration ?? Duration.zero;

      if (_isPlaying != playing) setState(() => _isPlaying = playing);
      
      if (_isBuffering != buffering) {
        final wasBuffering = _isBuffering;
        setState(() => _isBuffering = buffering);
        if (wasBuffering && !buffering && !_hasPlaybackStarted) {
          _hasPlaybackStarted = true;
        }
      }

      if (mounted) {
         if (!_isDragging && _hasPlaybackStarted) {
            if (_position.inSeconds != position.inSeconds) {
               setState(() => _position = position);
            }
         }

         if (_duration != duration && duration > Duration.zero) {
            setState(() => _duration = duration);
            if (!_initialSeekDone && widget.startPosition > Duration.zero) {
                _videoController.seekTo(widget.startPosition);
                _initialSeekDone = true;
            }
         }
      }
      
      if (_hasPlaybackStarted && !_tracksExtracted) {
          _tracksExtracted = true;
          _extractTracks();
      }"""
code = re.sub(listener_pattern, bp_listener, code, flags=re.DOTALL)

# 4. Track Extraction
ext_pattern = r'Future<void> _extractTracks\(\) async \{.*?\}'
bp_ext = """Future<void> _extractTracks() async {
      await Future.delayed(Duration(seconds: 1)); // Give ExoPlayer time to parse manifest
      if (!mounted) return;
      
      final asmsTracks = _videoController.betterPlayerAsmsAudioTracks ?? [];
      final bpSubs = _videoController.betterPlayerSubtitlesSourceList ?? [];
      
      Map<int, String> audioMap = {};
      for (int i=0; i<asmsTracks.length; i++) {
         audioMap[i] = asmsTracks[i].label ?? 'Audio ${i+1}';
      }
      
      Map<int, String> subMap = {};
      for (int i=0; i<bpSubs.length; i++) {
         subMap[i] = bpSubs[i].name ?? 'Subtítulo ${i+1}';
      }
      
      if (mounted) {
         setState(() {
            _audioTracks = audioMap;
            _subtitleTracks = subMap;
         });
      }
  }"""
code = re.sub(ext_pattern, bp_ext, code, flags=re.DOTALL)

# 5. Fix UI Modals
code = code.replace("import 'package:provider/provider.dart';", "import 'package:provider/provider.dart';\nimport 'package:flutter/services.dart';")

code = code.replace("_videoController.pause()", "_videoController.pause()")
code = code.replace("_videoController.stop()", "_videoController.pause()")

code = code.replace("_videoController.getAudioTracks()", "Future.value(_audioTracks)")
code = code.replace("_videoController.getSpuTracks()", "Future.value(_subtitleTracks)")
code = code.replace("_videoController.setSpuTrack(entry.key)", '''
    final bpSubs = _videoController.betterPlayerSubtitlesSourceList ?? [];
    if(entry.key >= 0 && entry.key < bpSubs.length) {
       _videoController.setupTranslations(bpSubs[entry.key]);
    }
''')
code = code.replace("_videoController.setSpuTrack(-1)", "_videoController.setupTranslations(BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none))")

code = code.replace("_videoController.setAudioTrack(entry.key)", '''
    final asmsTracks = _videoController.betterPlayerAsmsAudioTracks ?? [];
    if(entry.key >= 0 && entry.key < asmsTracks.length) {
       _videoController.setAudioTrack(asmsTracks[entry.key]);
    }
''')

# 6. Add BetterPlayer External Audio Fake Stub (BetterPlayer natively grabs it via M3U8 but if not we can't manually inject HTTP audio stream anyway, it has to be in the TS).
code = code.replace("_videoController.addAudioFromNetwork(url, isSelected: true);", "")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(code)

print("Migration applied successfully.")
