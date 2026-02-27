f = 'lib/screens/video_player_screen.dart'
with open(f, 'r', encoding='utf-8') as fh:
    content = fh.read()

# 1. Clean out the _initPlayer completely to standard raw open
old_init = """  Future<void> _initPlayer(String fullUrl) async {
    try {
      final platform = _player.platform as dynamic;
      await platform.setProperty('framedrop', 'no');
      await platform.setProperty('video-sync', 'audio');
    } catch (_) {}

    await _player.open(Media(
      fullUrl,
      httpHeaders: {
        'Referer': 'https://vnc-e.com',
        'User-Agent': 'VanacueMobile/1.0',
      },
      extras: {
        // Force ffmpeg demuxer to start at absolute zero, ignoring HLS start-time drift
        'start': '0',
        'ss': '0',
        // Strip HLS absolute timestamp offsets and force them to start from 0 locally
        'demuxer-lavf-o': 'avoid_negative_ts=make_zero',
        // Configure precise seeking during stream opens
        'hr-seek': 'yes',
        'hr-seek-framedrop': 'no'
      },
    ));
    // No explicit seek here, we wait for duration bounds in the listener
  }"""

new_init = """  Future<void> _initPlayer(String fullUrl) async {
    await _player.open(Media(
      fullUrl,
      httpHeaders: {
        'Referer': 'https://vnc-e.com',
        'User-Agent': 'VanacueMobile/1.0',
      },
    ));
  }"""
content = content.replace(old_init, new_init)

# 2. Add boundary tracking variables
content = content.replace("  bool _hasPlaybackStarted = false;\n", "  bool _hasPlaybackStarted = false;\n  Duration _safeStreamingBoundary = Duration.zero;\n  bool _boundaryCaptured = false;\n")

# 3. Create the Safe Getters
content = content.replace(
    """  Duration get _adjustedPosition => _position;
  Duration get _adjustedDuration => _duration;""",
    """  Duration get _adjustedPosition {
    if (widget.startPosition > Duration.zero) return _position; // If resuming from saved time, don't mask
    final adjusted = _position - _safeStreamingBoundary;
    return adjusted < Duration.zero ? Duration.zero : adjusted;
  }
  
  Duration get _adjustedDuration {
    if (widget.startPosition > Duration.zero) return _duration;
    final adjusted = _duration - _safeStreamingBoundary;
    return adjusted < Duration.zero ? _duration : adjusted;
  }"""
)

# 4. Modify Position Listener to capture the boundary when video finally boots up
old_pos = """        // Always update the raw position (used for progress saving and triggers)
        if (_hasPlaybackStarted) {
          // If we are at the very beginning and haven't fully synced, lock at 0
          if (!_initialSeekDone && widget.startPosition == Duration.zero && position.inSeconds < 2) {
             setState(() => _position = Duration.zero);
          } else {
             setState(() => _position = position);
          }
        }"""
new_pos = """        // Track true safe boundary on first valid playback tick
        if (_hasPlaybackStarted && !_boundaryCaptured && position > Duration.zero && widget.startPosition == Duration.zero) {
           _safeStreamingBoundary = position;
           _boundaryCaptured = true;
        }

        if (_hasPlaybackStarted) {
          setState(() => _position = position);
        }"""
content = content.replace(old_pos, new_pos)

# 5. Modify slider and Seek commands to inject the safe boundary
old_slider = """                            onChanged: (value) {
                              setState(() {
                                _position = Duration(seconds: value.toInt());
                              });
                            },
                            onChangeEnd: (value) {
                              _player.seek(Duration(seconds: value.toInt()));
                              setState(() {
                                _isDragging = false;
                              });
                            },"""

new_slider = """                            onChanged: (value) {
                              setState(() {
                                final offset = (widget.startPosition == Duration.zero) ? _safeStreamingBoundary : Duration.zero;
                                _position = Duration(seconds: value.toInt()) + offset;
                              });
                            },
                            onChangeEnd: (value) {
                              final offset = (widget.startPosition == Duration.zero) ? _safeStreamingBoundary : Duration.zero;
                              final safeSeek = Duration(seconds: value.toInt()) + offset;
                              _player.seek(safeSeek);
                              setState(() {
                                _isDragging = false;
                              });
                            },"""
content = content.replace(old_slider, new_slider)


# 6. Apply limits to skip buttons
content = content.replace("(_position.inSeconds - 10).clamp(0, _duration.inSeconds)", "(_position.inSeconds - 10).clamp((widget.startPosition == Duration.zero ? _safeStreamingBoundary.inSeconds : 0), _duration.inSeconds)")
content = content.replace("(_position.inSeconds + 10).clamp(0, _duration.inSeconds)", "(_position.inSeconds + 10).clamp((widget.startPosition == Duration.zero ? _safeStreamingBoundary.inSeconds : 0), _duration.inSeconds)")

# 7. Use _adjusted getters for progress saving and trigger checking
content = content.replace(
    "_adjustedPosition.inSeconds > 0 && _adjustedPosition.inSeconds % 5 == 0 && widget.contentMaster != null && _adjustedDuration.inSeconds > 0",
    "_adjustedPosition.inSeconds > 0 && _adjustedPosition.inSeconds % 5 == 0 && widget.contentMaster != null && _adjustedDuration.inSeconds > 0"
) # Just verify it's there
# Actually we need to explicitly replace the old ones if they were reverted
# Let's cleanly patch the entire progress saving check
import re

content = re.sub(
    r"if \(_hasPlaybackStarted && !_showPostPlay && !_showNextEpisode.*?\)",
    r"if (_hasPlaybackStarted && !_showPostPlay && !_showNextEpisode && _adjustedPosition.inSeconds > 0 && _adjustedPosition.inSeconds % 5 == 0 && widget.contentMaster != null && _adjustedDuration.inSeconds > 0)",
    content
)

content = re.sub(
    r"provider\.saveVideoProgress\([\s\S]*?,\n[\s\S]*?position\.inSeconds\.toDouble\(\),\n[\s\S]*?_duration\.inSeconds\.toDouble\(\),",
    r"provider.saveVideoProgress(\n            generateProgressId(widget.contentMaster!, episodeTitle: widget.episodeTitle),\n            _adjustedPosition.inSeconds.toDouble(),\n            _adjustedDuration.inSeconds.toDouble(),",
    content
)

content = re.sub(
    r"final remaining = _duration\.inSeconds - position\.inSeconds;",
    r"final remaining = _adjustedDuration.inSeconds - _adjustedPosition.inSeconds;",
    content
)


# write back
with open(f, 'w', encoding='utf-8') as fh:
    fh.write(content)

print("Applied boundary-safe tracking offset replacement.")
