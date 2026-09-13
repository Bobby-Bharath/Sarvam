import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:file_picker/file_picker.dart';

import '../main.dart';
import 'subtitles/subtitle_studio_sheet.dart';
import 'widgets/subtitle_overlay.dart';
import 'gesture_arena.dart';
import '../engine/player/playback_session_manager.dart';

enum AspectRatioMode { fit, fill, stretch, ratio16_9, ratio4_3 }
enum RepeatMode { none, all, one }

class PlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String? thumbnailPath;
  final List<AssetEntity>? playlist;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.thumbnailPath,
    this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  static const _bgChannel = MethodChannel('com.bobby.omni_player/background');
  static const _pipChannel = MethodChannel('com.bobby.omni_player/pip');
  late final Player player;
  late final VideoController controller;

  bool _showControls = true;
  Timer? _hideTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _hasResumed = false;
  StreamSubscription? _durationSubscription;

  String? _indicatorText;
  IconData? _indicatorIcon;
  Timer? _indicatorTimer;
  bool _indicatorIsVertical = false;
  bool _indicatorIsLeft = false;

  Tracks _tracks = const Tracks();
  Track _track = const Track();

  double _eqBrightness = 0.0;
  double _eqContrast = 0.0;
  double _eqSaturation = 0.0;
  double _eqGamma = 0.0;

  bool _isUiLocked = false;
  AspectRatioMode _aspectRatioMode = AspectRatioMode.fit;
  final List<String> _aspectRatioLabels = ['Fit', 'Fill (Zoom)', 'Stretch', '16:9', '4:3'];
  
  double _playbackSpeed = 1.0;
  bool _isPitchCorrectionEnabled = true;
  int _abLoopState = 0; // 0: None, 1: A Set, 2: Looping
  Duration? _loopA;
  Duration? _loopB;
  int _videoRotation = 0;

  double _audioDelay = 0.0;
  double _subDelay = 0.0;
  int _decoderIndex = 0;
  final List<String> _decoderModes = ['mediacodec', 'mediacodec-copy', 'no'];
  final List<String> _decoderLabels = ['HW+', 'HW', 'SW'];
  
  late int _currentIndex;
  late String _currentTitle;
  List<AssetEntity> _queue = [];
  bool _isShuffled = false;
  RepeatMode _repeatMode = RepeatMode.none;
  List<String> _activeSubtitles = [];
  StreamSubscription? _subSubscription;

  bool _isInPip = false;
  bool _backgroundAudio = true;
  int _videoWidth = 0;
  int _videoHeight = 0;

  Duration? _voiceTimestamp;
  Duration? _subTimestamp;
  Duration? _videoActionTimestamp;
  Duration? _soundTimestamp;

  Timer? _autosaveTimer;
  bool _showResumeOverlay = false;
  int _savedPositionMs = 0;
  int? _pendingAudioIndex;
  int? _pendingSubtitleIndex;

  // Subtitle Style State
  Map<String, dynamic> _subtitleStyle = {
    'textColor': Colors.white.toARGB32(),
    'textAlpha': 1.0,
    'fontSize': 24.0,
    'fontWeight': 600,
    'letterSpacing': 0.5,
    'fontFamily': 'Roboto',
    'allCaps': false,
    'italic': false,
    'borderColor': Colors.black.toARGB32(),
    'borderAlpha': 1.0,
    'borderSize': 2.5,
    'shadowColor': Colors.black.toARGB32(),
    'shadowAlpha': 0.8,
    'shadowDistance': 3.0,
    'shadowAngle': 45.0,
    'shadowBlur': 2.0,
    'boxColor': Colors.black.toARGB32(),
    'boxAlpha': 0.0,
    'boxPaddingH': 8.0,
    'boxPaddingV': 4.0,
    'boxRadius': 6.0,
    'positionOffset': 20.0,
    'overrideAss': true,
    'align': 1,
  };

  double _previousRate = 1.0;
  final TransformationController _transformationController = TransformationController();
  double _currentScale = 1.0;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _currentIndex = widget.initialIndex;
    _currentTitle = widget.title;
    _queue = widget.playlist != null ? List.from(widget.playlist!) : [];

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    player = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
    controller = VideoController(player);

    _initMpv();
    _setupStreams();
    _setupMethodChannels();
    
    player.open(Media(widget.filePath));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final resumeMs = await PlaybackSessionManager.instance.startSession(widget.filePath);
      if (resumeMs > 15000 && mounted) {
        _durationSubscription = player.stream.duration.listen((dur) {
          if (dur > Duration.zero && !_hasResumed) {
            _hasResumed = true;
            player.seek(Duration(milliseconds: resumeMs));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Resumed from ${formatDuration(Duration(milliseconds: resumeMs))}'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
        });
      }
    });

    _bgChannel.invokeMethod('startNotification', {
      'title': widget.title,
      'isPlaying': true,
      if (widget.thumbnailPath != null) 'thumbPath': widget.thumbnailPath,
    });
    
    audioHandler?.setPlayer(player, widget.filePath, _currentTitle, widget.playlist != null ? "Playlist" : "Omni Player");
    _setupAudioHandlerCallbacks();

    _loadSavedState();
    
    _autosaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isPlaying) _saveCurrentState();
    });
  }

  void _initMpv() {
    Future.microtask(() {
      try {
        final mpv = player.platform as dynamic;
        mpv.setProperty('hwdec', 'mediacodec');
        mpv.setProperty('keep-open', 'yes');
        mpv.setProperty('vid', 'auto');
        mpv.setProperty('force-window', 'no');
        mpv.setProperty('stop-screensaver', 'yes');
        mpv.setProperty('audio-display', 'no');
      } catch (_) {}
    });
  }

  void _setupStreams() {
    player.stream.position.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
        if (_loopA != null && _loopB != null && pos >= _loopB!) {
          player.seek(_loopA!);
        }
      }
      PlaybackSessionManager.instance.onPositionChanged(
        pos.inMilliseconds,
        player.state.duration.inMilliseconds,
      );
    });
    player.stream.duration.listen((dur) {
      if (mounted) {
        setState(() => _duration = dur);
        _syncNotification();
      }
    });
    player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        if (playing) _startHideTimer();
        _syncNotification();
        _pipChannel.invokeMethod('updatePiPState', {'isPlaying': playing});
      }
    });

    player.stream.completed.listen((completed) {
      if (completed && mounted) {
        _handleVideoCompletion();
      }
    });

    player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() => _tracks = tracks);
        _restorePendingTracks();
      }
    });
    player.stream.track.listen((track) {
      if (mounted) setState(() => _track = track);
    });

    _subSubscription = player.stream.subtitle.listen((lines) {
      if (mounted) {
        setState(() {
          _activeSubtitles = lines;
        });
      }
    });

    player.stream.videoParams.listen((params) {
      if (mounted && params.w != null && params.h != null && params.w! > 0 && params.h! > 0) {
        setState(() {
          _videoWidth = params.w!;
          _videoHeight = params.h!;
        });
      }
    });
  }

  void _setupMethodChannels() {
    _pipChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipRewind':
          await player.seek(player.state.position - const Duration(seconds: 10));
          break;
        case 'onPipPlayPause':
          await player.playOrPause();
          _pipChannel.invokeMethod('updatePiPState', {'isPlaying': player.state.playing});
          break;
        case 'onPipForward':
          await player.seek(player.state.position + const Duration(seconds: 10));
          break;
        case 'onPipStatusChanged':
          if (call.arguments is bool) {
            setState(() => _isInPip = call.arguments as bool);
          }
          break;
      }
    });

    _bgChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMediaPlayPause':
          await player.playOrPause();
          _syncNotification();
          _pipChannel.invokeMethod('updatePiPState', {'isPlaying': player.state.playing});
          break;
        case 'onMediaRewind':
          await player.seek(player.state.position - const Duration(seconds: 10));
          _syncNotification();
          break;
        case 'onMediaForward':
          await player.seek(player.state.position + const Duration(seconds: 10));
          _syncNotification();
          break;
        case 'onMediaNext':
          if (_currentIndex < _queue.length - 1) {
            _playPlaylistItem(_currentIndex + 1);
          }
          break;
        case 'onMediaPrevious':
          if (_currentIndex > 0) {
            _playPlaylistItem(_currentIndex - 1);
          }
          break;
        case 'onMediaSeekTo':
          final posMs = call.arguments as int?;
          if (posMs != null) {
            await player.seek(Duration(milliseconds: posMs));
            _syncNotification();
          }
          break;
      }
    });
  }

  void _setupAudioHandlerCallbacks() {
    audioHandler?.onSkipNext = () {
      if (_currentIndex < _queue.length - 1) _playPlaylistItem(_currentIndex + 1);
    };
    audioHandler?.onSkipPrevious = () {
      if (_currentIndex > 0) _playPlaylistItem(_currentIndex - 1);
    };
  }

  Future<void> _loadSavedState() async {
    final data = await PlaybackPersistenceManager.loadState(widget.filePath);
    if (data != null && mounted) {
      setState(() {
        _audioDelay = (data['audioDelay'] ?? 0.0).toDouble();
        _subDelay = (data['subDelay'] ?? 0.0).toDouble();
        final savedDecoder = data['decoderMode'] as String?;
        if (savedDecoder != null) {
          _decoderIndex = _decoderModes.indexOf(savedDecoder).clamp(0, _decoderModes.length - 1);
        }
        _pendingAudioIndex = data['audioTrackIndex'];
        _pendingSubtitleIndex = data['subtitleTrackIndex'];
      });
      
      final mpv = player.platform as dynamic;
      mpv.setProperty('audio-delay', _audioDelay.toStringAsFixed(3));
      mpv.setProperty('sub-delay', _subDelay.toStringAsFixed(3));
      mpv.setProperty('hwdec', _decoderModes[_decoderIndex]);

      final int positionMs = data['positionMs'] ?? 0;
      final int durationMs = data['durationMs'] ?? 0;

      if (positionMs > 5000 && positionMs < (durationMs * 0.95)) {
        setState(() {
          _savedPositionMs = positionMs;
          _showResumeOverlay = true;
        });
        Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _showResumeOverlay = false);
        });
      }
    }
  }

  void _restorePendingTracks() {
    if (_pendingAudioIndex != null && _pendingAudioIndex! >= 0 && _pendingAudioIndex! < _tracks.audio.length) {
      player.setAudioTrack(_tracks.audio[_pendingAudioIndex!]);
      _pendingAudioIndex = null;
    }
    if (_pendingSubtitleIndex != null && _pendingSubtitleIndex! >= 0 && _pendingSubtitleIndex! < _tracks.subtitle.length) {
      player.setSubtitleTrack(_tracks.subtitle[_pendingSubtitleIndex!]);
      _pendingSubtitleIndex = null;
    }
  }

  Future<void> _saveCurrentState() async {
    if (_duration == Duration.zero) return;
    
    await PlaybackPersistenceManager.saveState(
      widget.filePath,
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
      audioDelay: _audioDelay,
      subDelay: _subDelay,
      decoderMode: _decoderModes[_decoderIndex],
      audioTrack: _tracks.audio.indexOf(_track.audio),
      subTrack: _tracks.subtitle.indexOf(_track.subtitle),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_isPlaying) {
        player.play();
      }
    }
  }

  void _syncNotification() {
    _bgChannel.invokeMethod('updateNotification', {
      'title': _currentTitle,
      'isPlaying': player.state.playing,
      'duration': player.state.duration.inMilliseconds,
      'position': player.state.position.inMilliseconds,
      if (widget.thumbnailPath != null) 'thumbPath': widget.thumbnailPath,
    });
  }

  void _applySubtitleStyle() {
    String toMpvColor(Color c, double alpha) {
      final Color finalColor = c.withValues(alpha: alpha);
      final r = (finalColor.r > 1.0 ? finalColor.r / 255.0 : finalColor.r).toStringAsFixed(3);
      final g = (finalColor.g > 1.0 ? finalColor.g / 255.0 : finalColor.g).toStringAsFixed(3);
      final b = (finalColor.b > 1.0 ? finalColor.b / 255.0 : finalColor.b).toStringAsFixed(3);
      final a = (finalColor.a).toStringAsFixed(3);
      return '$r/$g/$b/$a';
    }

    try {
      final mpv = player.platform as dynamic;
      mpv.setProperty('sub-ass-override', _subtitleStyle['overrideAss'] ? 'force' : 'scale');
      mpv.setProperty('sub-color', toMpvColor(Color(_subtitleStyle['textColor']), _subtitleStyle['textAlpha']));
      mpv.setProperty('sub-border-color', toMpvColor(Color(_subtitleStyle['borderColor']), _subtitleStyle['borderAlpha']));
      mpv.setProperty('sub-shadow-color', toMpvColor(Color(_subtitleStyle['shadowColor']), _subtitleStyle['shadowAlpha']));
      mpv.setProperty('sub-back-color', toMpvColor(Color(_subtitleStyle['boxColor']), _subtitleStyle['boxAlpha']));
      mpv.setProperty('sub-border-size', _subtitleStyle['borderSize'].toStringAsFixed(1));
      mpv.setProperty('sub-shadow-offset', _subtitleStyle['shadowDistance'].toStringAsFixed(1));
      mpv.setProperty('sub-blur', _subtitleStyle['shadowBlur'].toStringAsFixed(1));
      mpv.setProperty('sub-font-size', _subtitleStyle['fontSize'].toInt().toString());
      mpv.setProperty('sub-bold', _subtitleStyle['fontWeight'] >= 700 ? 'yes' : 'no');
      mpv.setProperty('sub-italic', _subtitleStyle['italic'] ? 'yes' : 'no');
      mpv.setProperty('sub-pos', _subtitleStyle['positionOffset'].round().toString());
      
      final alignNames = ['left', 'center', 'right'];
      mpv.setProperty('sub-align-x', alignNames[_subtitleStyle['align']]);
      mpv.setProperty('sub-font', _subtitleStyle['fontFamily']);
    } catch (e) {
      debugPrint('Error applying sub styles: $e');
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_isUiLocked) return;
    setState(() => _showControls = !_showControls);
    _showControls ? _startHideTimer() : _hideTimer?.cancel();
  }

  void _toggleUiLock() {
    setState(() {
      _isUiLocked = !_isUiLocked;
      if (_isUiLocked) _showControls = false;
    });
    if (!_isUiLocked) _toggleControls();
  }

  void _cycleAspectRatio() {
    setState(() {
      final nextIndex = (_aspectRatioMode.index + 1) % AspectRatioMode.values.length;
      _aspectRatioMode = AspectRatioMode.values[nextIndex];
      _showIndicator(_aspectRatioLabels[_aspectRatioMode.index], Icons.aspect_ratio);
    });
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    player.setRate(speed);
    _showIndicator('${speed}x', Icons.speed);
  }

  Future<void> _togglePitchCorrection(bool enable) async {
    setState(() => _isPitchCorrectionEnabled = enable);
    try {
      final mpv = player.platform as dynamic;
      if (enable) {
        await mpv.setProperty('audio-pitch-correction', 'yes');
        await mpv.command(['af', 'set', 'scaletempo2']);
      } else {
        await mpv.setProperty('audio-pitch-correction', 'no');
        await mpv.command(['af', 'clr', '']);
      }
    } catch (e) {
      debugPrint('Pitch toggle error: $e');
    }
  }

  void _toggleAbLoop() {
    final mpv = player.platform as dynamic;
    setState(() {
      if (_abLoopState == 0) {
        _abLoopState = 1;
        _loopA = _position;
        mpv.setProperty('ab-loop-a', (_position.inMilliseconds / 1000.0).toStringAsFixed(3));
        _showIndicator('Point A set', Icons.repeat);
      } else if (_abLoopState == 1) {
        _abLoopState = 2;
        _loopB = _position;
        mpv.setProperty('ab-loop-b', (_position.inMilliseconds / 1000.0).toStringAsFixed(3));
        _showIndicator('Looping A-B', Icons.repeat_on);
      } else {
        _abLoopState = 0;
        _loopA = null;
        _loopB = null;
        mpv.setProperty('ab-loop-a', 'no');
        mpv.setProperty('ab-loop-b', 'no');
        _showIndicator('Loop Cleared', Icons.repeat);
      }
    });
  }

  void _frameStep(bool forward) {
    if (forward) {
      try {
        final mpv = player.platform as dynamic;
        mpv.command(['frame-step']);
      } catch (_) {}
    } else {
      _stepFrameBack();
    }
  }

  Future<void> _stepFrameBack() async {
    try {
      final mpv = player.platform as dynamic;
      await mpv.command(['frame-back-step']);
    } catch (_) {
      final target = _position - const Duration(milliseconds: 40);
      if (target > Duration.zero) {
        await player.seek(target);
      }
    }
  }

  void _cycleRotation() {
    _videoRotation = (_videoRotation + 90) % 360;
    try {
      final mpv = player.platform as dynamic;
      mpv.setProperty('video-rotate', _videoRotation.toString());
      _showIndicator('$_videoRotation°', Icons.rotate_right);
    } catch (_) {}
    setState(() {});
  }

  void _toggleDecoder() {
    _decoderIndex = (_decoderIndex + 1) % _decoderModes.length;
    final mode = _decoderModes[_decoderIndex];
    try {
      final mpv = player.platform as dynamic;
      mpv.setProperty('hwdec', mode);
      _showIndicator('Decoder: ${_decoderLabels[_decoderIndex]}', Icons.memory);
    } catch (_) {}
    setState(() {});
  }

  void _handleVideoCompletion() {
    if (_duration != Duration.zero && _position.inMilliseconds > (_duration.inMilliseconds * 0.95)) {
      _saveCurrentStateWithPosition(0);
    }
    if (_repeatMode == RepeatMode.one) {
      player.seek(Duration.zero);
      player.play();
    } else {
      _playNext();
    }
  }

  Future<void> _saveCurrentStateWithPosition(int posMs) async {
    if (_duration == Duration.zero) return;
    await PlaybackPersistenceManager.saveState(
      widget.filePath,
      positionMs: posMs,
      durationMs: _duration.inMilliseconds,
      audioDelay: _audioDelay,
      subDelay: _subDelay,
      decoderMode: _decoderModes[_decoderIndex],
      audioTrack: _tracks.audio.indexOf(_track.audio),
      subTrack: _tracks.subtitle.indexOf(_track.subtitle),
    );
  }

  void _playNext() {
    if (_queue.isEmpty) return;
    int nextIndex = _currentIndex + 1;
    if (nextIndex >= _queue.length) {
      if (_repeatMode == RepeatMode.all) {
        nextIndex = 0;
      } else {
        return;
      }
    }
    _playPlaylistItem(nextIndex);
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffled = !_isShuffled;
      if (_isShuffled) {
        final currentItem = _queue[_currentIndex];
        _queue.shuffle();
        _currentIndex = _queue.indexOf(currentItem);
      }
    });
  }

  void _cycleRepeatMode() {
    setState(() {
      _repeatMode = RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length];
    });
  }

  void _setAudioDelay(double seconds) {
    setState(() => _audioDelay = seconds);
    try {
      final mpv = player.platform as dynamic;
      mpv.setProperty('audio-delay', seconds.toStringAsFixed(3));
    } catch (_) {}
  }

  void _setSubDelay(double seconds) {
    setState(() => _subDelay = seconds);
    try {
      final mpv = player.platform as dynamic;
      mpv.setProperty('sub-delay', seconds.toStringAsFixed(3));
    } catch (_) {}
  }

  Future<void> _playPlaylistItem(int index) async {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) return;
    
    final video = _queue[index];
    final file = await video.originFile;
    if (file != null && mounted) {
      setState(() {
        _currentIndex = index;
        _currentTitle = video.title ?? 'Video';
        _position = Duration.zero;
        _duration = Duration.zero;
        _loopA = null;
        _loopB = null;
        _abLoopState = 0;
        _activeSubtitles = [];
      });
      player.open(Media(file.path));
      _syncNotification();
      audioHandler?.setPlayer(player, file.path, _currentTitle, "Playlist");
    }
  }

  void _showSyncSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Synchronization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Audio (Lip-sync)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('${(_audioDelay * 1000).round()} ms', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSmartSyncGroup(
                    label1: 'Lips Moved',
                    label2: 'Sound Heard',
                    isSet1: _videoActionTimestamp != null,
                    isSet2: _soundTimestamp != null,
                    onTap1: () {
                      setSheetState(() => _videoActionTimestamp = _position);
                      _checkAudioSync(setSheetState);
                    },
                    onTap2: () {
                      setSheetState(() => _soundTimestamp = _position);
                      _checkAudioSync(setSheetState);
                    },
                    onReset: () {
                      setSheetState(() {
                        _videoActionTimestamp = null;
                        _soundTimestamp = null;
                        _audioDelay = 0.0;
                      });
                      _setAudioDelay(0.0);
                    },
                  ),
                  _buildSyncNudgeRow((delta) {
                    final newVal = (_audioDelay + delta).clamp(-5.0, 5.0);
                    setSheetState(() => _audioDelay = newVal);
                    _setAudioDelay(newVal);
                  }),

                  const Divider(height: 48, color: Colors.white10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtitles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('${(_subDelay * 1000).round()} ms', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSmartSyncGroup(
                    label1: 'Voice Heard',
                    label2: 'Subtitle Seen',
                    isSet1: _voiceTimestamp != null,
                    isSet2: _subTimestamp != null,
                    onTap1: () {
                      setSheetState(() => _voiceTimestamp = _position);
                      _checkSubSync(setSheetState);
                    },
                    onTap2: () {
                      setSheetState(() => _subTimestamp = _position);
                      _checkSubSync(setSheetState);
                    },
                    onReset: () {
                      setSheetState(() {
                        _voiceTimestamp = null;
                        _subTimestamp = null;
                        _subDelay = 0.0;
                      });
                      _setSubDelay(0.0);
                    },
                  ),
                  _buildSyncNudgeRow((delta) {
                    final newVal = (_subDelay + delta).clamp(-5.0, 5.0);
                    setSheetState(() => _subDelay = newVal);
                    _setSubDelay(newVal);
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  Widget _buildSmartSyncGroup({
    required String label1,
    required String label2,
    required bool isSet1,
    required bool isSet2,
    required VoidCallback onTap1,
    required VoidCallback onTap2,
    required VoidCallback onReset,
  }) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: onTap1,
            style: ElevatedButton.styleFrom(
              backgroundColor: isSet1 ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white10,
              foregroundColor: isSet1 ? Colors.redAccent : Colors.white70,
              side: isSet1 ? const BorderSide(color: Colors.redAccent) : BorderSide.none,
            ),
            child: Text(label1, style: const TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: onTap2,
            style: ElevatedButton.styleFrom(
              backgroundColor: isSet2 ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white10,
              foregroundColor: isSet2 ? Colors.redAccent : Colors.white70,
              side: isSet2 ? const BorderSide(color: Colors.redAccent) : BorderSide.none,
            ),
            child: Text(label2, style: const TextStyle(fontSize: 12)),
          ),
        ),
        IconButton(onPressed: onReset, icon: const Icon(Icons.refresh, size: 20, color: Colors.white38)),
      ],
    );
  }

  Widget _buildSyncNudgeRow(ValueChanged<double> onNudge) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton(onPressed: () => onNudge(-1.0), child: const Text('-1000ms', style: TextStyle(color: Colors.redAccent, fontSize: 11))),
          TextButton(onPressed: () => onNudge(-0.1), child: const Text('-100ms')),
          TextButton(onPressed: () => onNudge(-0.05), child: const Text('-50ms')),
          TextButton(onPressed: () => onNudge(0.05), child: const Text('+50ms')),
          TextButton(onPressed: () => onNudge(0.1), child: const Text('+100ms')),
          TextButton(onPressed: () => onNudge(1.0), child: const Text('+1000ms', style: TextStyle(color: Colors.redAccent, fontSize: 11))),
        ],
      ),
    );
  }

  void _checkAudioSync(StateSetter setSheetState) {
    if (_videoActionTimestamp != null && _soundTimestamp != null) {
      final double offset = (_soundTimestamp!.inMilliseconds - _videoActionTimestamp!.inMilliseconds) / 1000.0;
      setSheetState(() => _audioDelay = offset);
      _setAudioDelay(offset);
      _showIndicator('Audio Synced: ${(offset * 1000).round()}ms', Icons.sync);
    }
  }

  void _checkSubSync(StateSetter setSheetState) {
    if (_voiceTimestamp != null && _subTimestamp != null) {
      final double offset = (_voiceTimestamp!.inMilliseconds - _subTimestamp!.inMilliseconds) / 1000.0;
      setSheetState(() => _subDelay = offset);
      _setSubDelay(offset);
      _showIndicator('Subtitles Synced: ${(offset * 1000).round()}ms', Icons.sync);
    }
  }

  Future<void> _enterPiP() async {
    setState(() => _showControls = false);
    
    int width = _videoWidth;
    int height = _videoHeight;
    
    if (width <= 0 || height <= 0) {
      width = player.state.videoParams.w ?? 16;
      height = player.state.videoParams.h ?? 9;
    }
    
    await _pipChannel.invokeMethod('enterPiP', {
      'isPlaying': player.state.playing,
      'width': width > 0 ? width : 16,
      'height': height > 0 ? height : 9,
    });
  }

  void _showCastSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Cast to Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1, color: Colors.white10),
            const ListTile(
              leading: Icon(Icons.tv),
              title: Text('Living Room TV (Chromecast)'),
              subtitle: Text('Scanning...'),
            ),
            const ListTile(
              leading: Icon(Icons.speaker),
              title: Text('Bedroom Roku'),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Card(
                color: Colors.white10,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Note: Local file streaming requires a local HTTP server daemon. Network streams can be cast directly.',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  void _showPlaylistSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.shuffle, color: _isShuffled ? Colors.redAccent : Colors.white54),
                        onPressed: () {
                          _toggleShuffle();
                          setSheetState(() {});
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                          color: _repeatMode == RepeatMode.none ? Colors.white54 : Colors.redAccent,
                        ),
                        onPressed: () {
                          _cycleRepeatMode();
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                if (_queue.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Text('No other videos in folder'))
                else
                  Flexible(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      itemCount: _queue.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final item = _queue.removeAt(oldIndex);
                          _queue.insert(newIndex, item);
                          if (_currentIndex == oldIndex) {
                            _currentIndex = newIndex;
                          } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
                            _currentIndex -= 1;
                          } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
                            _currentIndex += 1;
                          }
                        });
                        setSheetState(() {});
                      },
                      itemBuilder: (context, index) {
                        final video = _queue[index];
                        final isSelected = index == _currentIndex;
                        return ListTile(
                          key: ValueKey(video.id),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, color: Colors.white24, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 40,
                                height: 30,
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                                child: Icon(isSelected ? Icons.play_arrow : Icons.videocam, size: 16, color: isSelected ? Colors.redAccent : Colors.white38),
                              ),
                            ],
                          ),
                          title: Text(
                            video.title ?? 'Video $index',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: isSelected ? Colors.redAccent : Colors.white, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                          ),
                          subtitle: Text(formatDuration(Duration(seconds: video.duration)), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          selected: isSelected,
                          onTap: () {
                            _playPlaylistItem(index);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  void _showSpeedSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Playback Speed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1, color: Colors.white10),
              SwitchListTile(
                title: const Text('Pitch Correction'),
                subtitle: const Text('Keep audio pitch when changing speed'),
                value: _isPitchCorrectionEnabled,
                onChanged: (v) {
                  setSheetState(() => _isPitchCorrectionEnabled = v);
                  _togglePitchCorrection(v);
                },
              ),
              const Divider(height: 1, color: Colors.white10),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0].map((s) {
                    final isSelected = _playbackSpeed == s;
                    return ChoiceChip(
                      label: Text('${s}x'),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setSheetState(() => _playbackSpeed = s);
                          _setPlaybackSpeed(s);
                          Navigator.pop(context);
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  void _showMoreActionsSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('More Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1, color: Colors.white10),
              SwitchListTile(
                secondary: Icon(Icons.headset, color: _backgroundAudio ? Colors.redAccent : Colors.white54),
                title: const Text('Play in Background'),
                subtitle: const Text('Audio continues when screen is off'),
                value: _backgroundAudio,
                onChanged: (v) {
                  setSheetState(() => _backgroundAudio = v);
                  setState(() => _backgroundAudio = v);
                },
              ),
              ListTile(
                leading: Icon(_abLoopState == 2 ? Icons.repeat_on : Icons.repeat, color: _abLoopState > 0 ? Colors.redAccent : Colors.white),
                title: const Text('A-B Repeat'),
                subtitle: Text(_abLoopState == 0 ? 'Off' : _abLoopState == 1 ? 'Point A set' : 'Looping A-B'),
                onTap: () {
                  _toggleAbLoop();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.rotate_right),
                title: const Text('Rotation'),
                subtitle: Text('$_videoRotation°'),
                onTap: () {
                  _cycleRotation();
                  Navigator.pop(context);
                },
              ),
              if (!_isPlaying)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(onPressed: _stepFrameBack, icon: const Icon(Icons.skip_previous), label: const Text('Frame -1')),
                    TextButton.icon(onPressed: () => _frameStep(true), icon: const Icon(Icons.skip_next), label: const Text('Frame +1')),
                  ],
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  void _updateMpvProperty(String property, dynamic value) {
    try {
      final mpv = player.platform as dynamic;
      mpv.setProperty(property, value.toString());
    } catch (e) {
      debugPrint('Failed to set mpv property $property:$e');
    }
  }

  void _showSubtitleTrackSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Subtitle Tracks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1, color: Colors.white10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Icon(Icons.subtitles_off, color: _track.subtitle == SubtitleTrack.no() ? Colors.redAccent : Colors.white54),
                      title: Text(
                        'Off / Disable Subtitles',
                        style: TextStyle(
                          color: _track.subtitle == SubtitleTrack.no() ? Colors.redAccent : Colors.white,
                          fontWeight: _track.subtitle == SubtitleTrack.no() ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: _track.subtitle == SubtitleTrack.no() ? const Icon(Icons.check, color: Colors.redAccent) : null,
                      onTap: () {
                        player.setSubtitleTrack(SubtitleTrack.no());
                        Navigator.pop(context);
                      },
                    ),
                    ..._tracks.subtitle
                        .where((t) => t.id != 'no' && t.id != 'auto')
                        .map((track) {
                      final isSelected = _track.subtitle == track;
                      return ListTile(
                        leading: Icon(Icons.subtitles, color: isSelected ? Colors.redAccent : Colors.white54),
                        title: Text(
                          track.title ?? track.language ?? 'Subtitle ${track.id}',
                          style: TextStyle(color: isSelected ? Colors.redAccent : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.redAccent) : null,
                        onTap: () {
                          player.setSubtitleTrack(track);
                          Navigator.pop(context);
                        },
                      );
                    }),
                    const Divider(color: Colors.white10),
                    ListTile(
                      leading: const Icon(Icons.style_outlined, color: Colors.white70),
                      title: const Text('Customize Appearance'),
                      subtitle: const Text('Colors, shadows, border, and blur'),
                      onTap: () {
                        Navigator.pop(context);
                        _showSubtitleCustomizationSheet();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.add, color: Colors.white54),
                      title: const Text('Load External Subtitle (.srt, .ass, .vtt, .sub)'),
                      onTap: () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['srt', 'ass', 'vtt', 'sub'],
                        );
                        if (result != null && result.files.single.path != null) {
                          await player.setSubtitleTrack(SubtitleTrack.uri(result.files.single.path!));
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  void _showSubtitleCustomizationSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SubtitleStudioSheet(
        initialStyle: _subtitleStyle,
        onStyleChanged: (newStyle) {
          setState(() {
            _subtitleStyle = newStyle;
          });
          _applySubtitleStyle();
        },
      ),
    ).then((_) => _startHideTimer());
  }

  void _showAudioTrackSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Audio Tracks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1, color: Colors.white10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _tracks.audio.map((track) {
                  final isSelected = _track.audio == track;
                  return ListTile(
                    leading: Icon(Icons.audiotrack, color: isSelected ? Colors.redAccent : Colors.white54),
                    title: Text(
                      track.title ?? track.language ?? 'Audio Track ${track.id}',
                      style: TextStyle(color: isSelected ? Colors.redAccent : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    ),
                    subtitle: isSelected && player.state.audioParams.format != null
                        ? Text('${player.state.audioParams.format} • ${formatAudioChannels(player.state.audioParams.channelCount)}', style: const TextStyle(fontSize: 11, color: Colors.white38))
                        : null,
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.redAccent) : null,
                    onTap: () {
                      player.setAudioTrack(track);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  void _showVideoEqSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Video Equalizer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          _eqBrightness = 0; _eqContrast = 0; _eqSaturation = 0; _eqGamma = 0;
                        });
                        _updateMpvProperty('brightness', 0);
                        _updateMpvProperty('contrast', 0);
                        _updateMpvProperty('saturation', 0);
                        _updateMpvProperty('gamma', 0);
                      },
                      child: const Text('Reset All', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildEqSlider('Brightness', _eqBrightness, (v) {
                  setSheetState(() => _eqBrightness = v);
                  _updateMpvProperty('brightness', v.round());
                }),
                _buildEqSlider('Contrast', _eqContrast, (v) {
                  setSheetState(() => _eqContrast = v);
                  _updateMpvProperty('contrast', v.round());
                }),
                _buildEqSlider('Saturation', _eqSaturation, (v) {
                  setSheetState(() => _eqSaturation = v);
                  _updateMpvProperty('saturation', v.round());
                }),
                _buildEqSlider('Gamma', _eqGamma, (v) {
                  setSheetState(() => _eqGamma = v);
                  _updateMpvProperty('gamma', v.round());
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  Widget _buildEqSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(value.round().toString(), style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          min: -100, max: 100,
          activeColor: Colors.redAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildHudControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_currentTitle, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.lock_open, color: Colors.white),
                  onPressed: _toggleUiLock,
                ),
                TextButton(
                  onPressed: _toggleDecoder,
                  child: Text('[${_decoderLabels[_decoderIndex]}]', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                if (_audioDelay != 0 || _subDelay != 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_audioDelay != 0) Text('A: ${(_audioDelay * 1000).round()}ms', style: const TextStyle(color: Colors.white54, fontSize: 8)),
                        if (_subDelay != 0) Text('S: ${(_subDelay * 1000).round()}ms', style: const TextStyle(color: Colors.white54, fontSize: 8)),
                      ],
                    ),
                  ),
                IconButton(icon: const Icon(Icons.sync, color: Colors.white, size: 20), onPressed: _showSyncSheet),
                IconButton(icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 20), onPressed: _enterPiP),
                IconButton(icon: const Icon(Icons.cast, color: Colors.white, size: 20), onPressed: _showCastSheet),
                IconButton(icon: const Icon(Icons.audiotrack, color: Colors.white, size: 20), onPressed: _showAudioTrackSheet),
                IconButton(icon: const Icon(Icons.subtitles, color: Colors.white, size: 20), onPressed: _showSubtitleTrackSheet),
                IconButton(icon: const Icon(Icons.tune, color: Colors.white, size: 20), onPressed: _showVideoEqSheet),
                IconButton(icon: const Icon(Icons.more_vert, color: Colors.white, size: 20), onPressed: _showMoreActionsSheet),
              ],
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.translucent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 42),
                  onPressed: _currentIndex > 0 ? () => _playPlaylistItem(_currentIndex - 1) : null,
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 64,
                  color: Colors.white,
                  icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                  onPressed: () {
                    player.playOrPause();
                    _startHideTimer();
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 42),
                  onPressed: _currentIndex < _queue.length - 1 ? () => _playPlaylistItem(_currentIndex + 1) : null,
                ),
              ],
            ),
          ),
        ),
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(formatDuration(_position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 12),
                    if (player.state.audioParams.format != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          formatAudioChannels(player.state.audioParams.channelCount),
                          style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    const Spacer(),
                    if (_subDelay != 0.0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text('S: ${(_subDelay * 1000).round()}ms', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      ),
                    TextButton(onPressed: _cycleAspectRatio, child: Text(_aspectRatioLabels[_aspectRatioMode.index], style: const TextStyle(color: Colors.white70, fontSize: 12))),
                    TextButton(onPressed: _showSpeedSheet, child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                    IconButton(icon: const Icon(Icons.playlist_play, color: Colors.white70), onPressed: _showPlaylistSheet),
                    Text(formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 3,
                    activeTrackColor: Colors.redAccent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.redAccent,
                  ),
                  child: Slider(
                    min: 0.0,
                    max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                    value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
                    onChangeStart: (_) => _hideTimer?.cancel(),
                    onChangeEnd: (_) => _startHideTimer(),
                    onChanged: (value) {
                      player.seek(Duration(milliseconds: value.toInt()));
                      _syncNotification();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    setState(() {
      _currentScale = 1.0;
    });
    _showIndicator('Zoom Reset', Icons.zoom_out_map);
  }

  void _showIndicator(String text, IconData icon, {bool isVertical = false, bool isLeft = false}) {
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
      _indicatorIsVertical = isVertical;
      _indicatorIsLeft = isLeft;
    });
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(Duration(milliseconds: isVertical ? 1500 : 900), () {
      if (mounted) setState(() { _indicatorText = null; _indicatorIcon = null; });
    });
  }

  void _hideIndicator() {
    if (mounted) setState(() { _indicatorText = null; _indicatorIcon = null; });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    PlaybackSessionManager.instance.endSession();
    _saveCurrentState();
    _autosaveTimer?.cancel();
    _bgChannel.invokeMethod('stopNotification');
    audioHandler?.onSkipNext = null;
    audioHandler?.onSkipPrevious = null;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _subSubscription?.cancel();
    try {
      VolumeController.instance.removeListener();
    } catch (_) {}
    
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    player.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Widget _buildVideoSurface() {
    final videoWidth = player.state.videoParams.w?.toDouble() ?? 1920.0;
    final videoHeight = player.state.videoParams.h?.toDouble() ?? 1080.0;
    final config = const SubtitleViewConfiguration(visible: false);

    Widget videoWidget;

    switch (_aspectRatioMode) {
      case AspectRatioMode.fit:
        videoWidget = Video(controller: controller, controls: NoVideoControls, fit: BoxFit.contain, subtitleViewConfiguration: config);
        break;
      case AspectRatioMode.fill:
        videoWidget = Video(controller: controller, controls: NoVideoControls, fit: BoxFit.cover, subtitleViewConfiguration: config);
        break;
      case AspectRatioMode.stretch:
        videoWidget = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: Video(controller: controller, controls: NoVideoControls, subtitleViewConfiguration: config),
            ),
          ),
        );
        break;
      case AspectRatioMode.ratio16_9:
        videoWidget = Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: controller, controls: NoVideoControls, fit: BoxFit.fill, subtitleViewConfiguration: config),
          ),
        );
        break;
      case AspectRatioMode.ratio4_3:
        videoWidget = Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Video(controller: controller, controls: NoVideoControls, fit: BoxFit.fill, subtitleViewConfiguration: config),
          ),
        );
        break;
    }

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1.0,
      maxScale: 4.0,
      panEnabled: false,
      scaleEnabled: false,
      child: videoWidget,
    );
  }

  Widget _buildVerticalHudPill(String text, IconData icon, bool isLeft) {
    final double percent = double.tryParse(text.replaceAll('%', '')) ?? 0.0;
    
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (percent / 100.0).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RotatedBox(
            quarterTurns: 3,
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          player.pause();
          SystemChrome.setPreferredOrientations(DeviceOrientation.values);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: _buildVideoSurface()),

            if (_activeSubtitles.isNotEmpty)
              Positioned(
                left: 32,
                right: 32,
                bottom: _subtitleStyle['positionOffset'],
                child: IgnorePointer(
                  child: Align(
                    alignment: _subtitleStyle['align'] == 0 ? Alignment.bottomLeft : (_subtitleStyle['align'] == 2 ? Alignment.bottomRight : Alignment.bottomCenter),
                    child: SubtitleOverlay(
                      lines: _activeSubtitles,
                      fontSize: _subtitleStyle['fontSize'],
                      letterSpacing: _subtitleStyle['letterSpacing'],
                      fontWeight: FontWeight.values.firstWhere((w) => w.value == _subtitleStyle['fontWeight'], orElse: () => FontWeight.w600),
                      isItalic: _subtitleStyle['italic'],
                      isAllCaps: _subtitleStyle['allCaps'],
                      fontFamily: _subtitleStyle['fontFamily'],
                      textColor: Color(_subtitleStyle['textColor']),
                      textAlpha: _subtitleStyle['textAlpha'],
                      borderColor: Color(_subtitleStyle['borderColor']),
                      borderAlpha: _subtitleStyle['borderAlpha'],
                      borderSize: _subtitleStyle['borderSize'],
                      shadowColor: Color(_subtitleStyle['shadowColor']),
                      shadowAlpha: _subtitleStyle['shadowAlpha'],
                      shadowDistance: _subtitleStyle['shadowDistance'],
                      shadowAngle: _subtitleStyle['shadowAngle'],
                      shadowBlur: _subtitleStyle['shadowBlur'],
                      boxColor: Color(_subtitleStyle['boxColor']),
                      boxAlpha: _subtitleStyle['boxAlpha'],
                      boxRadius: _subtitleStyle['boxRadius'],
                      boxPaddingH: _subtitleStyle['boxPaddingH'],
                      boxPaddingV: _subtitleStyle['boxPaddingV'],
                    ),
                  ),
                ),
              ),

            GestureArena(
              isUiLocked: _isUiLocked,
              currentScale: _currentScale,
              transformationController: _transformationController,
              position: _position,
              duration: _duration,
              playbackRate: _playbackSpeed,
              onTap: _toggleControls,
              onZoomUpdate: (scale) => setState(() => _currentScale = scale),
              onSeekUpdate: (pos) => setState(() => _position = pos),
              onSeekEnd: (pos) => player.seek(pos),
              onBrightnessUpdate: (val) {},
              onVolumeUpdate: (val) {},
              onLongPressStart: (rate) {
                _previousRate = player.state.rate;
                player.setRate(2.0);
                _showIndicator('2.0x Fast Forwarding', Icons.speed);
              },
              onLongPressMove: (rate) {
                if (rate != player.state.rate) {
                  player.setRate(rate);
                  _showIndicator('${rate.toStringAsFixed(2)}x Fast Forwarding', Icons.speed);
                }
              },
              onLongPressEnd: () => player.setRate(_previousRate),
              onDoubleTapReset: _resetZoom,
              onDoubleTapSeek: (isRight) {
                final target = isRight ? _position + const Duration(seconds: 10) : _position - const Duration(seconds: 10);
                final targetMs = target.inMilliseconds.clamp(0, _duration.inMilliseconds);
                player.seek(Duration(milliseconds: targetMs));
                _showIndicator(isRight ? '+10s' : '-10s', isRight ? Icons.fast_forward : Icons.fast_rewind);
              },
              showIndicator: _showIndicator,
              hideIndicator: _hideIndicator,
              child: const SizedBox.expand(),
            ),

            if (_isUiLocked)
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.lock_outline, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: _toggleUiLock,
                ),
              ),
            if (_showResumeOverlay && !_isUiLocked)
              Positioned(
                bottom: 110,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Resume from ${formatDuration(Duration(milliseconds: _savedPositionMs))}?', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () {
                            player.seek(Duration(milliseconds: _savedPositionMs));
                            setState(() => _showResumeOverlay = false);
                          },
                          style: TextButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(onPressed: () { player.seek(Duration.zero); setState(() => _showResumeOverlay = false); }, child: const Text('Start Over', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      ],
                    ),
                  ),
                ),
              ),
            if (_indicatorText != null && !_indicatorIsVertical)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_indicatorIcon, color: Colors.white, size: 28),
                      const SizedBox(width: 8),
                      Text(_indicatorText!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            if (_indicatorText != null && _indicatorIsVertical)
              Positioned(
                left: _indicatorIsLeft ? 40 : null,
                right: _indicatorIsLeft ? null : 40,
                top: screenHeight * 0.2,
                bottom: screenHeight * 0.2,
                child: _buildVerticalHudPill(_indicatorText!, _indicatorIcon!, _indicatorIsLeft),
              ),
            IgnorePointer(
              ignoring: !_showControls || _isUiLocked || _isInPip,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _showControls && !_isUiLocked && !_isInPip ? 1.0 : 0.0,
                child: _buildHudControls(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
