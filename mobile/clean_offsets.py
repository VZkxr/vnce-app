f = 'lib/screens/video_player_screen.dart'
with open(f, 'r', encoding='utf-8') as fh:
    content = fh.read()

# 1. Remove _positionOffset and adjusted getters
content = content.replace("  Duration _positionOffset = Duration.zero;\n", "")

content = content.replace(
    """  Duration get _adjustedPosition {
    final adjusted = _position - _positionOffset;
    return adjusted < Duration.zero ? Duration.zero : adjusted;
  }
  
  Duration get _adjustedDuration => _duration;  // Assuming _duration from media_kit is length""",
    """  Duration get _adjustedPosition => _position;
  Duration get _adjustedDuration => _duration;"""
)

# 2. Revert _initPlayer back to basic open
old_init = """  Future<void> _initPlayer(String fullUrl) async {
    await _player.open(Media(
      fullUrl,
      httpHeaders: {
        'Referer': 'https://vnc-e.com',
        'User-Agent': 'VanacueMobile/1.0',
      },
    ), play: false);
    
    _positionOffset = _player.state.position;
    if (_positionOffset < Duration.zero) _positionOffset = Duration.zero;

    final targetPos = widget.startPosition + _positionOffset;
    await _player.seek(targetPos);
    
    if (mounted) {
      setState(() => _initialSeekDone = true);
    }
    _player.play();
  }"""

new_init = """  Future<void> _initPlayer(String fullUrl) async {
    await _player.open(Media(
      fullUrl,
      httpHeaders: {
        'Referer': 'https://vnc-e.com',
        'User-Agent': 'VanacueMobile/1.0',
      },
    ));
    // No explicit seek here, we wait for duration bounds in the listener
  }"""
content = content.replace(old_init, new_init)

# 3. Restore duration-based seek (only if >0)
old_duration = """    _player.stream.duration.listen((Duration duration) {
       if (mounted) {
         setState(() => _duration = duration);
       }
    });"""

new_duration = """    _player.stream.duration.listen((Duration duration) {
       if (mounted) {
         setState(() => _duration = duration);
         // Once duration is available, seek to saved position if we have one
         if (duration > Duration.zero && !_initialSeekDone && widget.startPosition > Duration.zero) {
             _player.seek(widget.startPosition);
             _initialSeekDone = true;
         }
       }
    });"""
content = content.replace(old_duration, new_duration)

# 4. Fix UI Seek (remove + _positionOffset)
old_slider = """                            onChanged: (value) {
                              setState(() {
                                _position = Duration(seconds: value.toInt()) + _positionOffset;
                              });
                            },
                            onChangeEnd: (value) {
                              _player.seek(Duration(seconds: value.toInt()) + _positionOffset);
                              setState(() {
                                _isDragging = false;
                              });
                            },"""
new_slider = """                            onChanged: (value) {
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
content = content.replace(old_slider, new_slider)

# 5. Fix Skip buttons (remove + _positionOffset clamping)
content = content.replace(
    "(_position.inSeconds - 10).clamp(_positionOffset.inSeconds, _positionOffset.inSeconds + _duration.inSeconds)",
    "(_position.inSeconds - 10).clamp(0, _duration.inSeconds)"
)
content = content.replace(
    "(_position.inSeconds + 10).clamp(_positionOffset.inSeconds, _positionOffset.inSeconds + _duration.inSeconds)",
    "(_position.inSeconds + 10).clamp(0, _duration.inSeconds)"
)

# 6. Make position.listen simpler - ALWAYS show 0 until duration is loaded
old_pos = """        // Always update the raw position (used for progress saving and triggers)
        // Display the adjusted position (position - offset)
        if (_hasPlaybackStarted) {
          setState(() => _position = position);
        }"""
new_pos = """        // Always update the raw position (used for progress saving and triggers)
        if (_hasPlaybackStarted) {
          // If we are at the very beginning and haven't fully synced, lock at 0
          if (!_initialSeekDone && widget.startPosition == Duration.zero && position.inSeconds < 2) {
             setState(() => _position = Duration.zero);
          } else {
             setState(() => _position = position);
          }
        }"""
content = content.replace(old_pos, new_pos)

with open(f, 'w', encoding='utf-8') as fh:
    fh.write(content)

print("Reverted to pure media_kit VOD logic. No offsets.")
