import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';

import 'player/player_screen.dart';
import 'database/media_database.dart';
import 'engine/metadata/filename_tokenizer.dart';
import 'ui/pairing/pairing_manager_page.dart';
import 'ui/pairing/manual_matcher_dialog.dart';
import 'ui/pairing/interactive_mapping_page.dart';
import 'ui/pairing/pre_flight_mapping_dialog.dart';
import 'ui/hub/series_details_screen.dart';
import 'ui/hub/tracker_watchlist_page.dart';
import 'ui/settings/tracker_accounts_page.dart';
import 'engine/plugins/plugin_registry.dart';
import 'engine/sync/sync_dispatcher.dart';

// ─────────────────────────────────────────────────────────────
// PLAYBACK PERSISTENCE MANAGER
// ─────────────────────────────────────────────────────────────

class PlaybackPersistenceManager {
  static const String _prefix = 'video_state_';

  static Future<void> saveState(
    String path, {
    required int positionMs,
    required int durationMs,
    double? audioDelay,
    double? subDelay,
    String? decoderMode,
    int? audioTrack,
    int? subTrack,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix${path.hashCode}';
    final data = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'audioDelay': audioDelay ?? 0.0,
      'subDelay': subDelay ?? 0.0,
      'decoderMode': decoderMode ?? 'mediacodec',
      'audioTrackIndex': audioTrack ?? -1,
      'subtitleTrackIndex': subTrack ?? -1,
      'lastPlayedTimestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(key, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> loadState(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix${path.hashCode}';
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearState(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix${path.hashCode}';
    await prefs.remove(key);
  }
}

// ─────────────────────────────────────────────────────────────
// GLOBAL SERVICES
// ─────────────────────────────────────────────────────────────

OmniAudioHandler? audioHandler;

class OmniAudioHandler extends BaseAudioHandler {
  Player? _player;
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  final List<StreamSubscription> _subscriptions = [];

  OmniAudioHandler() {
    playbackState.add(PlaybackState(
      controls: [],
      systemActions: const {MediaAction.seek},
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  void setPlayer(Player player, String id, String title, String? album) {
    _player = player;
    
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    _updateMediaItem(title, album, _player!.state.duration, id);

    _subscriptions.add(_player!.stream.playing.listen((_) => _updatePlaybackState()));
    _subscriptions.add(_player!.stream.position.listen((_) => _updatePlaybackState()));
    _subscriptions.add(_player!.stream.buffer.listen((_) => _updatePlaybackState()));
    _subscriptions.add(_player!.stream.duration.listen((dur) {
      _updateMediaItem(title, album, dur, id);
    }));

    _updatePlaybackState();
  }

  void _updateMediaItem(String title, String? album, Duration duration, String id) {
    mediaItem.add(MediaItem(
      id: id,
      album: album ?? 'Omni Player',
      title: title,
      artist: 'Omni Player',
      duration: duration,
    ));
  }

  void _updatePlaybackState() {
    if (_player == null) return;
    
    final playing = _player!.state.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.pause,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: _player!.state.position,
      bufferedPosition: _player!.state.buffer,
      speed: _player!.state.rate,
    ));
  }

  @override
  Future<void> play() => _player?.play() ?? Future.value();

  @override
  Future<void> pause() => _player?.pause() ?? Future.value();

  @override
  Future<void> seek(Duration position) => _player?.seek(position) ?? Future.value();

  @override
  Future<void> fastForward() => _player?.seek(_player!.state.position + const Duration(seconds: 10)) ?? Future.value();

  @override
  Future<void> rewind() => _player?.seek(_player!.state.position - const Duration(seconds: 10)) ?? Future.value();

  @override
  Future<void> skipToNext() async => onSkipNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipPrevious?.call();
}

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

String formatAudioChannels(int? channels) {
  if (channels == null) return 'Audio Track';
  if (channels == 1) return 'Mono (1.0)';
  if (channels == 2) return 'Stereo (2.0)';
  if (channels == 6) return '5.1 Surround';
  if (channels == 8) return '7.1 Surround';
  return '$channels Channels';
}

// ─────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    await Permission.notification.request();
  }

  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init failed: $e');
  }

  // Initialize Database
  try {
    await MediaDatabase.instance.database;
  } catch (e) {
    debugPrint('Database init failed: $e');
  }
  
  // Initialize Plugins
  try {
    await PluginRegistry.instance.init();
  } catch (e) {
    debugPrint('Plugin Registry init failed: $e');
  }
  
  try {
    audioHandler = await AudioService.init(
      builder: () => OmniAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationChannelId: 'com.bobby.omni_player.channel.audio',
        androidNotificationChannelName: 'Omni Player Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        notificationColor: Color(0xFF1E1E1E),
      ),
    );
  } catch (e) {
    debugPrint('AudioService init failed: $e');
  }

  await setHighRefreshRate();
  
  runApp(const OmniPlayerApp());
}

Future<void> setHighRefreshRate() async {
  try {
    if (Platform.isAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
    }
  } catch (_) {}
}

// ─────────────────────────────────────────────────────────────
// ROOT APP
// ─────────────────────────────────────────────────────────────

class OmniPlayerApp extends StatelessWidget {
  const OmniPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omni Player',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF0F0F0F),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const MainShellScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ROOT: Main Shell with Floating Navbar
// ─────────────────────────────────────────────────────────────

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _retryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      SyncDispatcher.instance.processRetryQueue();
    });
    // Immediate check on boot
    Future.delayed(const Duration(seconds: 10), () => SyncDispatcher.instance.processRetryQueue());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  final List<Widget> _screens = [
    const FolderListScreen(),
    const MediaHubScreen(),
    const NetworkStreamScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          _buildFloatingNavbar(),
        ],
      ),
    );
  }

  Widget _buildFloatingNavbar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white10, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navbarItem(0, Icons.folder_outlined, Icons.folder, 'Browse'),
              _navbarItem(1, Icons.auto_awesome_motion_outlined, Icons.auto_awesome_motion, 'Hub'),
              _navbarItem(2, Icons.link, Icons.link, 'Stream'),
              _navbarItem(3, Icons.tune_outlined, Icons.tune, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navbarItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? Colors.redAccent : Colors.white54,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: isSelected ? Colors.redAccent : Colors.white38, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCREEN 1: Library Root (Folders)
// ─────────────────────────────────────────────────────────────

class FolderListScreen extends StatefulWidget {
  const FolderListScreen({super.key});

  @override
  State<FolderListScreen> createState() => _FolderListScreenState();
}

class _FolderListScreenState extends State<FolderListScreen> {
  List<AssetPathEntity> _albums = [];
  bool _isLoading = true;
  int _fetchId = 0;

  @override
  void initState() {
    super.initState();
    _fetchAlbums();
  }

  Future<void> _fetchAlbums() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final currentFetchId = ++_fetchId;

    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (ps.isAuth || ps.hasAccess) {
        final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
          type: RequestType.video,
          onlyAll: false,
        );
        if (currentFetchId == _fetchId && mounted) {
          setState(() {
            _albums = albums;
          });
        }
      }
    } catch (e) {
      debugPrint('Fetch albums error: $e');
    } finally {
      if (currentFetchId == _fetchId && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Library', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAlbums),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _albums.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: _albums.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    return FutureBuilder<Map<String, dynamic>?>(
                      future: MediaDatabase.instance.getMediaEntityByFolder(album.id),
                      builder: (context, snapshot) {
                        final paired = snapshot.data;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: paired != null ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10,
                            child: Icon(Icons.folder, color: paired != null ? Colors.redAccent : Colors.amber),
                          ),
                          title: Text(album.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(paired != null ? 'Paired: ${paired['title']}' : 'Local Files', style: TextStyle(color: paired != null ? Colors.redAccent : Colors.white38, fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.more_vert, color: Colors.white24),
                                onPressed: () => _showFolderOptions(album, paired),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.white24),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => FolderVideosScreen(album: album)),
                            );
                          },
                        );
                      }
                    );
                  },
                ),
    );
  }

  void _showFolderOptions(AssetPathEntity album, Map<String, dynamic>? paired) {
     showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (paired == null)
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.redAccent),
                title: const Text('Pair Folder with Metadata'),
                onTap: () {
                  Navigator.pop(context);
                  ManualMatcherDialog.show(context, folder: album, onComplete: () => setState(() {}));
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.white70),
                title: const Text('Edit Mapping'),
                onTap: () {
                   Navigator.pop(context);
                   ManualMatcherDialog.show(context, folder: album, onComplete: () => setState(() {}));
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.redAccent),
                title: const Text('Unlink Folder'),
                onTap: () async {
                  Navigator.pop(context);
                  await MediaDatabase.instance.unlinkAllFilesForEntity(paired['id']);
                  await MediaDatabase.instance.deleteMediaEntity(paired['id']);
                  setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('No video folders found', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _fetchAlbums, child: const Text('Refresh')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCREEN 2: Video List for Selected Folder
// ─────────────────────────────────────────────────────────────

class FolderVideosScreen extends StatefulWidget {
  final AssetPathEntity album;
  const FolderVideosScreen({super.key, required this.album});

  @override
  State<FolderVideosScreen> createState() => _FolderVideosScreenState();
}

class _FolderVideosScreenState extends State<FolderVideosScreen> {
  List<AssetEntity> _videos = [];
  bool _isLoading = true;
  int _fetchId = 0;

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final currentFetchId = ++_fetchId;
    try {
      final List<AssetEntity> media = await widget.album.getAssetListRange(start: 0, end: 1000);
      if (currentFetchId == _fetchId && mounted) {
        setState(() {
          _videos = media;
        });
      }
    } catch (e) {
      debugPrint('Folder: Fetch videos error: $e');
    } finally {
      if (currentFetchId == _fetchId && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMagicPairMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_fix_high, color: Colors.redAccent),
              title: const Text('Auto-Pair (Magic)'),
              subtitle: const Text('Search and align files automatically'),
              onTap: () async {
                Navigator.pop(context);
                _runAutoPair();
              },
            ),
            ListTile(
              leading: const Icon(Icons.search, color: Colors.white70),
              title: const Text('Manual Search & Align'),
              onTap: () {
                Navigator.pop(context);
                ManualMatcherDialog.show(context, folder: widget.album, onComplete: () => setState(() {}));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAutoPair() async {
    final token = FilenameTokenizer.parse(widget.album.name);
    String? folderPath;
    if (_videos.isNotEmpty) {
      final firstFile = await _videos.first.originFile;
      folderPath = firstFile?.parent.path;
    }

    if (context.mounted) {
      PreFlightMappingDialog.show(
        context,
        files: _videos,
        initialQuery: token.cleanTitle,
        folderId: widget.album.id,
        folderPath: folderPath,
        onComplete: () => setState(() {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.redAccent),
            tooltip: 'Magic Pair',
            onPressed: () => _showMagicPairMenu(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : ListView.separated(
              itemCount: _videos.length,
              separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final video = _videos[index];
                final token = FilenameTokenizer.parse(video.title ?? '');
                
                return FutureBuilder<Map<String, dynamic>?>(
                  future: video.originFile.then((f) => f != null ? MediaDatabase.instance.getLocalFile(f.path) : null),
                  builder: (context, snapshot) {
                    final dbFile = snapshot.data;
                    
                    // Fallback badges from token if not in DB
                    final List<String> badgeList = [];
                    if (dbFile != null && dbFile['resolution_badge'] != null) {
                      badgeList.add(dbFile['resolution_badge']);
                      if (dbFile['fps_badge'] != null) badgeList.add(dbFile['fps_badge']);
                      if (dbFile['audio_codec_badge'] != null) badgeList.add(dbFile['audio_codec_badge']);
                    } else {
                      if (token.resolutionTag != null) badgeList.add(token.resolutionTag!);
                      // Basic codec detection from raw filename if token doesn't have it
                      final raw = video.title ?? '';
                      if (raw.contains(RegExp(r'x265|HEVC', caseSensitive: false))) badgeList.add('HEVC');
                      else if (raw.contains(RegExp(r'x264|AVC', caseSensitive: false))) badgeList.add('AVC');
                      if (raw.contains(RegExp(r'AAC', caseSensitive: false))) badgeList.add('AAC');
                      else if (raw.contains(RegExp(r'Opus', caseSensitive: false))) badgeList.add('Opus');
                    }

                    String title = token.cleanTitle;
                    String epText = token.formattedDisplayTitle;

                    if (dbFile != null && dbFile['episode_number'] != null) {
                       epText = 'Episode ${dbFile['episode_number']} · Matched';
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 80,
                          height: 50,
                          color: Colors.white10,
                          child: Stack(
                            children: [
                              _buildThumb(video, dbFile),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    formatDuration(Duration(seconds: video.duration)),
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            epText,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      subtitle: badgeList.isEmpty 
                        ? null 
                        : Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 4,
                              children: badgeList.map((b) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(b, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                              )).toList(),
                            ),
                          ),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                        onPressed: () => _showFileOptions(video, dbFile != null && dbFile['media_entity_id'] != null),
                      ),
                      onTap: () async {
                        final file = await video.originFile;
                        if (file != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                filePath: file.path,
                                title: token.formattedDisplayTitle,
                                playlist: _videos,
                                initialIndex: index,
                              ),
                            ),
                          );
                        }
                      },
                    );
                  }
                );
              },
            ),
    );
  }

  Widget _buildThumb(AssetEntity video, [Map<String, dynamic>? dbFile]) {
    return FutureBuilder<Uint8List?>(
      future: video.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        final hasThumb = snapshot.connectionState == ConnectionState.done && snapshot.data != null;
        final double progress = (dbFile != null && dbFile['duration_ms'] != null && dbFile['duration_ms'] > 0)
            ? (dbFile['last_position_ms'] ?? 0) / dbFile['duration_ms']
            : 0.0;
        final bool isWatched = dbFile != null && dbFile['watch_state'] == 1;

        return Stack(
          fit: StackFit.expand,
          children: [
            if (hasThumb)
              Image.memory(snapshot.data!, fit: BoxFit.cover)
            else
              const Center(child: Icon(Icons.videocam, color: Colors.white24, size: 20)),
            
            if (isWatched)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(child: Icon(Icons.check_circle, color: Colors.green, size: 32)),
                ),
              )
            else if (progress > 0.05)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                  minHeight: 3,
                ),
              ),
          ],
        );
      },
    );
  }

  void _showFileOptions(AssetEntity video, bool isPaired) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isPaired ? Icons.edit_note : Icons.auto_awesome, color: Colors.redAccent),
              title: Text(isPaired ? 'Edit Metadata' : 'Pair with Media Hub'),
              onTap: () {
                Navigator.pop(context);
                ManualMatcherDialog.show(context, video: video, onComplete: () => setState(() {}));
              },
            ),
            if (isPaired)
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.white38),
                title: const Text('Unpair'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await video.originFile;
                  if (file != null) {
                    await MediaDatabase.instance.updateLocalFileLinks(file.path, null, null);
                    setState(() {});
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline, color: Colors.white70),
              title: const Text('Play Directly'),
              onTap: () async {
                Navigator.pop(context);
                final file = await video.originFile;
                if (file != null && mounted) {
                  final token = FilenameTokenizer.parse(video.title ?? '');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        filePath: file.path,
                        title: token.formattedDisplayTitle,
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCREEN 3: Media Hub (Paired Media)
// ─────────────────────────────────────────────────────────────

class MediaHubScreen extends StatefulWidget {
  const MediaHubScreen({super.key});

  @override
  State<MediaHubScreen> createState() => _MediaHubScreenState();
}

class _MediaHubScreenState extends State<MediaHubScreen> {
  List<Map<String, dynamic>> _entities = [];
  bool _isLoading = true;
  int _currentViewIndex = 0; // 0: Local Hub, 1: AniList Watchlist
  bool _isAniListLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadPairedMedia();
    MediaDatabase.instance.addListener(_loadPairedMedia);
  }

  @override
  void dispose() {
    MediaDatabase.instance.removeListener(_loadPairedMedia);
    super.dispose();
  }

  Future<void> _loadPairedMedia() async {
    final db = MediaDatabase.instance;
    final list = await db.getAllMediaEntities();
    
    // De-duplicate by franchise or folder path for Hub view
    final Map<String, Map<String, dynamic>> seen = {};
    for (var item in list) {
      final key = item['franchise_id'] ?? item['folder_path'] ?? item['title'];
      if (!seen.containsKey(key)) {
        seen[key] = item;
      }
    }
    
    final prefs = await SharedPreferences.getInstance();
    final bool loggedIn = prefs.getBool('anilist_logged_in') ?? false;

    if (mounted) {
      setState(() {
        _entities = seen.values.toList();
        _isAniListLoggedIn = loggedIn;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Hub', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_suggest_outlined),
            onPressed: () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => const PairingManagerPage())).then((_) => _loadPairedMedia());
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _viewTab(0, 'Local Hub'),
                const SizedBox(width: 8),
                _viewTab(1, 'AniList Watchlist'),
              ],
            ),
          ),
        ),
      ),
      body: _currentViewIndex == 0 ? _buildLocalHub() : _buildRemoteWatchlist(),
    );
  }

  Widget _viewTab(int index, String label) {
    final bool isSelected = _currentViewIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentViewIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white38,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteWatchlist() {
    return const TrackerWatchlistPage();
  }

  Widget _buildLocalHub() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_entities.isEmpty) {
       return const Center(child: Text('No media paired yet.\nGo to Browse to pair your files.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _entities.length,
      itemBuilder: (context, index) {
        final entity = _entities[index];
        return GestureDetector(
          onTap: () {
             Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesDetailsScreen(mediaEntityId: entity['id']))).then((_) => _loadPairedMedia());
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: entity['poster_url'] != null 
                    ? Image.network(
                        entity['poster_url'], 
                        fit: BoxFit.cover, 
                        cacheWidth: 250,
                        errorBuilder: (_, __, ___) => Container(color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24))
                      )
                    : Container(color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entity['title'] ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                '${entity['year'] ?? ""} · ${entity['total_episodes'] ?? "?"} Eps',
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCREEN: Network Stream
// ─────────────────────────────────────────────────────────────

class NetworkStreamScreen extends StatefulWidget {
  const NetworkStreamScreen({super.key});

  @override
  State<NetworkStreamScreen> createState() => _NetworkStreamScreenState();
}

class _NetworkStreamScreenState extends State<NetworkStreamScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<String> _recentStreams = [];
  final String _historyKey = 'recent_streams';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentStreams = prefs.getStringList(_historyKey) ?? [];
    });
  }

  Future<void> _saveToHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _recentStreams.remove(url);
    _recentStreams.insert(0, url);
    if (_recentStreams.length > 20) _recentStreams.removeLast();
    await prefs.setStringList(_historyKey, _recentStreams);
    setState(() {});
  }

  Future<void> _removeFromHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _recentStreams.remove(url);
    await prefs.setStringList(_historyKey, _recentStreams);
    setState(() {});
  }

  void _playStream(String url) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;

    if (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://') && !trimmedUrl.startsWith('rtsp://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL (http, https, or rtsp)')),
      );
      return;
    }

    _saveToHistory(trimmedUrl);
    
    String title = "Network Stream";
    try {
      final uri = Uri.parse(trimmedUrl);
      title = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : "Stream";
      if (title.isEmpty) title = uri.host;
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(filePath: trimmedUrl, title: title),
      ),
    );
  }

  Widget _presetChip(String label, String url) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.white10,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        _urlController.text = url;
        _playStream(url);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network Stream', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        children: [
          _buildInputSection(),
          const SizedBox(height: 24),
          _buildPresetsSection(),
          const SizedBox(height: 32),
          _buildHistorySection(),
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      children: [
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: 'HLS, DASH, MP4, RTSP...',
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.link, color: Colors.redAccent),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.content_paste, size: 20),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) _urlController.text = data!.text!;
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () => _urlController.clear(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _playStream(_urlController.text),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play Stream'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              shadowColor: Colors.redAccent.withValues(alpha: 0.3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Presets', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _presetChip('Big Buck Bunny (HLS)', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'),
            _presetChip('Tears of Steel (MP4)', 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4'),
          ],
        ),
      ],
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recently Played', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            if (_recentStreams.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_historyKey);
                  setState(() => _recentStreams = []);
                },
                child: const Text('Clear all', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
          ],
        ),
        if (_recentStreams.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.history, size: 48, color: Colors.white10),
                  SizedBox(height: 12),
                  Text('No recent streams', style: TextStyle(color: Colors.white24)),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentStreams.length,
            itemBuilder: (context, index) {
              final url = _recentStreams[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.link, size: 20, color: Colors.white54)),
                title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.play_circle_outline, color: Colors.redAccent), onPressed: () => _playStream(url)),
                    IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.white24), onPressed: () => _removeFromHistory(url)),
                  ],
                ),
                onTap: () => _playStream(url),
              );
            },
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCREEN: Plugins & Shaders
// ─────────────────────────────────────────────────────────────

class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plugins & Shaders', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPluginTile('Anime4K', 'High-quality real-time upscaling for anime.', Icons.auto_awesome, true),
          _buildPluginTile('Custom Shaders', 'Load external .glsl or .mpv shader files.', Icons.brush, false),
          _buildPluginTile('Subtitle Engine', 'Advanced libass styling and placement.', Icons.subtitles, true),
        ],
      ),
    );
  }

  Widget _buildPluginTile(String title, String desc, IconData icon, bool enabled) {
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.redAccent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        trailing: Switch(value: enabled, onChanged: (v) {}),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCREEN: Settings
// ─────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Tracker Accounts'),
            subtitle: const Text('Connect to AniList, Kitsu, or SIMKL'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackerAccountsPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Omni Player'),
            subtitle: const Text('v1.0.0-alpha'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
