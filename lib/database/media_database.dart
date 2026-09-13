import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class MediaDatabase extends ChangeNotifier {
  static final MediaDatabase instance = MediaDatabase._init();
  static Database? _database;

  MediaDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('omni_media.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7, // Bumped to 7
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 6) {
      final List<String> mediaEntityCols = [
        'franchise_id TEXT',
        'status TEXT',
        'start_date TEXT',
        'end_date TEXT',
        'average_score TEXT',
        'subtype TEXT',
        'id_mal INTEGER',
        'entity_type TEXT',
        'folder_path TEXT',
      ];

      for (final col in mediaEntityCols) {
        try {
          await db.execute("ALTER TABLE media_entities ADD COLUMN $col;");
        } catch (_) {
          // Column might already exist from a previous failed upgrade
        }
      }

      try {
        await db.execute("ALTER TABLE episodes ADD COLUMN is_filler INTEGER DEFAULT 0;");
      } catch (_) {}
    }

    if (oldVersion < 7) {
      try {
        await db.execute("ALTER TABLE episodes ADD COLUMN episode_type TEXT DEFAULT 'CANON';");
      } catch (_) {}
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT';
    const integerType = 'INTEGER';
    const boolType = 'INTEGER'; // 0 for false, 1 for true

    await db.execute('''
      CREATE TABLE media_entities (
        id $idType,
        display_provider $textType,
        entity_type $textType, -- TV_SERIES, ANIME, MOVIE, MOVIE_COLLECTION
        folder_path $textType, -- Binds a folder to this entity
        title $textType NOT NULL,
        original_title $textType,
        poster_url $textType,
        backdrop_url $textType,
        overview $textType,
        year $integerType,
        total_seasons $integerType,
        total_episodes $integerType,
        anilist_id $integerType,
        mal_id $integerType,
        tmdb_id $integerType,
        simkl_id $integerType,
        trakt_id $integerType,
        id_mal $integerType, -- Added v5
        franchise_id $textType, -- Groups related entries
        allow_sync $boolType DEFAULT 1,
        is_manual_match $boolType DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE episodes (
        id $idType,
        media_entity_id $textType NOT NULL,
        season_number $integerType NOT NULL,
        episode_number $integerType NOT NULL,
        title $textType,
        overview $textType,
        still_path $textType,
        air_date $textType,
        is_filler $integerType DEFAULT 0,
        episode_type $textType DEFAULT 'CANON',
        FOREIGN KEY (media_entity_id) REFERENCES media_entities (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE local_files (
        file_path $textType PRIMARY KEY,
        media_entity_id $textType,
        episode_id $textType,
        file_size $integerType,
        duration_ms $integerType,
        last_position_ms $integerType DEFAULT 0,
        watch_state $integerType DEFAULT 0,
        resolution_badge $textType,
        hdr_badge $textType,
        fps_badge $textType,
        audio_codec_badge $textType,
        audio_channels_badge $textType,
        audio_tracks_count $integerType DEFAULT 0,
        subtitle_tracks_count $integerType DEFAULT 0,
        FOREIGN KEY (media_entity_id) REFERENCES media_entities (id) ON DELETE SET NULL,
        FOREIGN KEY (episode_id) REFERENCES episodes (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_service $textType NOT NULL,
        remote_id $integerType,
        season_number $integerType,
        episode_number $integerType,
        progress_percent $integerType,
        created_at $textType NOT NULL
      )
    ''');
  }

  // --- CRUD for media_entities ---

  Future<int> upsertMediaEntity(Map<String, dynamic> row) async {
    final db = await instance.database;
    final res = await db.insert(
      'media_entities',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
    return res;
  }

  Future<Map<String, dynamic>?> getMediaEntity(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'media_entities',
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<Map<String, dynamic>?> getMediaEntityByFolder(String folderPath) async {
    final db = await instance.database;
    final maps = await db.query(
      'media_entities',
      where: 'folder_path = ?',
      whereArgs: [folderPath],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllMediaEntities() async {
    final db = await instance.database;
    // Group by franchise_id or title to show one card per show
    return await db.rawQuery('''
      SELECT me.*, COUNT(lf.file_path) as mapped_file_count
      FROM media_entities me
      LEFT JOIN episodes ep ON me.id = ep.media_entity_id
      LEFT JOIN local_files lf ON ep.id = lf.episode_id
      GROUP BY COALESCE(me.franchise_id, me.title)
      ORDER BY me.rowid DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getFranchiseEntities(String franchiseId) async {
    final db = await instance.database;
    return await db.query(
      'media_entities',
      where: 'franchise_id = ? OR title = ?',
      whereArgs: [franchiseId, franchiseId], // Fallback to title matching if ID is missing
      orderBy: 'year ASC',
    );
  }

  Future<int> deleteMediaEntity(String id) async {
    final db = await instance.database;
    final entity = await getMediaEntity(id);
    final String? folderPath = entity?['folder_path'];
    final String? franchiseId = entity?['franchise_id'];

    int count = 0;
    await db.transaction((txn) async {
      // 1. Identify all IDs in the franchise bundle
      final List<Map<String, dynamic>> related = await txn.query(
        'media_entities',
        columns: ['id'],
        where: 'id = ? OR franchise_id = ? OR (folder_path IS NOT NULL AND folder_path = ?)',
        whereArgs: [id, franchiseId, folderPath],
      );
      final List<String> targetIds = related.map((e) => e['id'] as String).toList();

      if (targetIds.isEmpty) return;

      // 2. Unlink local_files
      await txn.update(
        'local_files',
        {'media_entity_id': null, 'episode_id': null},
        where: 'media_entity_id IN (${targetIds.map((_) => '?').join(',')})',
        whereArgs: targetIds,
      );

      // 3. Delete episodes
      await txn.delete(
        'episodes',
        where: 'media_entity_id IN (${targetIds.map((_) => '?').join(',')})',
        whereArgs: targetIds,
      );

      // 4. Delete media_entities
      count = await txn.delete(
        'media_entities',
        where: 'id IN (${targetIds.map((_) => '?').join(',')})',
        whereArgs: targetIds,
      );
    });

    notifyListeners();
    return count;
  }

  Future<int> deleteFranchise(String id) async => deleteMediaEntity(id);

  // --- CRUD for episodes ---

  Future<int> upsertEpisode(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert(
      'episodes',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getEpisode(String entityId, int season, int episode) async {
    final db = await instance.database;
    final maps = await db.query(
      'episodes',
      where: 'media_entity_id = ? AND season_number = ? AND episode_number = ?',
      whereArgs: [entityId, season, episode],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getEpisodesForEntity(String entityId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT ep.*, lf.file_path, lf.last_position_ms, lf.duration_ms, lf.watch_state
      FROM episodes ep
      LEFT JOIN local_files lf ON ep.id = lf.episode_id
      WHERE ep.media_entity_id = ?
      ORDER BY ep.season_number ASC, ep.episode_number ASC
    ''', [entityId]);
  }

  // --- CRUD for local_files ---

  Future<int> upsertLocalFile(Map<String, dynamic> row) async {
    final db = await instance.database;
    final res = await db.insert(
      'local_files',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
    return res;
  }

  Future<int> updateLocalFileLinks(String filePath, String? entityId, String? episodeId) async {
    final db = await instance.database;
    final res = await db.update(
      'local_files',
      {
        'media_entity_id': entityId,
        'episode_id': episodeId,
      },
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    notifyListeners();
    return res;
  }

  Future<int> updateProgress(String filePath, int positionMs, int durationMs) async {
    final db = await instance.database;
    final res = await db.update(
      'local_files',
      {
        'last_position_ms': positionMs,
        'duration_ms': durationMs,
      },
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    notifyListeners();
    return res;
  }

  Future<int> updateWatchState(String filePath, int state) async {
    final db = await instance.database;
    final res = await db.update(
      'local_files',
      {'watch_state': state},
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    notifyListeners();
    return res;
  }

  Future<int> unlinkAllFilesForEntity(String entityId) async {
    final db = await instance.database;
    final res = await db.update(
      'local_files',
      {
        'media_entity_id': null,
        'episode_id': null,
      },
      where: 'media_entity_id = ?',
      whereArgs: [entityId],
    );
    notifyListeners();
    return res;
  }

  Future<Map<String, dynamic>?> getLocalFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.rawQuery('''
      SELECT local_files.*, episodes.episode_number, episodes.season_number, episodes.title AS ep_title
      FROM local_files
      LEFT JOIN episodes ON local_files.episode_id = episodes.id
      WHERE local_files.file_path = ?
    ''', [filePath]);

    if (maps.isNotEmpty) {
      return maps.first;
    } else {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getLocalFilesForEntity(String entityId) async {
    final db = await instance.database;
    return await db.query(
      'local_files',
      where: 'media_entity_id = ?',
      whereArgs: [entityId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllLocalFiles() async {
    final db = await instance.database;
    return await db.query('local_files');
  }

  Future<int> deleteLocalFile(String filePath) async {
    final db = await instance.database;
    final res = await db.delete(
      'local_files',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    notifyListeners();
    return res;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
