import 'dart:async';
import '../../database/media_database.dart';
import '../sync/sync_dispatcher.dart';

class PlaybackSessionManager {
  static final PlaybackSessionManager instance = PlaybackSessionManager._();
  PlaybackSessionManager._();

  Timer? _saveTimer;
  String? _currentFilePath;
  int _lastSavedPositionMs = 0;
  int _durationMs = 0;
  bool _scrobbledThisSession = false;

  Future<int> startSession(String filePath) async {
    _currentFilePath = filePath;
    _scrobbledThisSession = false;
    final db = await MediaDatabase.instance.database;
    final rows = await db.query(
      'local_files',
      columns: ['last_position_ms', 'duration_ms'],
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    if (rows.isNotEmpty) {
      _lastSavedPositionMs = (rows.first['last_position_ms'] as int?) ?? 0;
      _durationMs = (rows.first['duration_ms'] as int?) ?? 0;
      return _lastSavedPositionMs;
    }
    return 0;
  }

  void onPositionChanged(int positionMs, int durationMs) {
    if (_currentFilePath == null) return;
    _durationMs = durationMs > 0 ? durationMs : _durationMs;
    _lastSavedPositionMs = positionMs;

    // Check 85% scrobble threshold
    if (!_scrobbledThisSession && _durationMs > 1000) {
      final ratio = positionMs / _durationMs;
      if (ratio >= 0.85) {
        _scrobbledThisSession = true;
        _triggerScrobble(_currentFilePath!);
        _persistProgress(forceWatched: true);
      } else if (positionMs > 15000) {
        // Mark as watching if past 15 seconds but not yet watched
        _persistProgress(forceWatching: true);
      }
    }

    // Throttle saving to DB every 3 seconds
    if (_saveTimer == null || !_saveTimer!.isActive) {
      _saveTimer = Timer(const Duration(seconds: 3), () => _persistProgress());
    }
  }

  Future<void> endSession() async {
    _saveTimer?.cancel();
    await _persistProgress();
    _currentFilePath = null;
  }

  Future<void> _persistProgress({bool forceWatched = false, bool forceWatching = false}) async {
    if (_currentFilePath == null) return;
    
    int watchState = 0; // 0 = UNWATCHED
    if (forceWatched || (_durationMs > 0 && (_lastSavedPositionMs / _durationMs) >= 0.85)) {
      watchState = 1; // 1 = WATCHED
    } else if (forceWatching || _lastSavedPositionMs > 15000) {
      watchState = 2; // 2 = WATCHING
    }

    await MediaDatabase.instance.updateProgress(
      _currentFilePath!, 
      _lastSavedPositionMs, 
      _durationMs
    );
    
    await MediaDatabase.instance.updateWatchState(_currentFilePath!, watchState);
  }

  Future<void> _triggerScrobble(String filePath) async {
    final db = await MediaDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT lf.episode_id, ep.episode_number, ep.season_number, ep.media_entity_id, me.allow_sync
      FROM local_files lf
      JOIN episodes ep ON lf.episode_id = ep.id
      JOIN media_entities me ON ep.media_entity_id = me.id
      WHERE lf.file_path = ?
    ''', [filePath]);

    if (rows.isNotEmpty && (rows.first['allow_sync'] as int?) == 1) {
      final row = rows.first;
      SyncDispatcher.instance.scrobbleEpisode(
        entityId: row['media_entity_id'] as String,
        episodeNumber: row['episode_number'] as int,
        seasonNumber: row['season_number'] as int? ?? 1,
      );
    }
  }
}
