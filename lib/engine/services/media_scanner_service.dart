// lib/engine/services/media_scanner_service.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../database/media_database.dart';
import '../plugins/simkl_plugin.dart';
import '../plugins/mal_plugin.dart';

class MediaScannerService {
  final SimklPlugin _simkl = SimklPlugin();
  final MALPlugin _mal = MALPlugin();
  final MediaDatabase _db = MediaDatabase.instance;

  // Scans a local directory path for media files and automatically maps them
  Future<void> scanAndMapDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final videoExtensions = {'.mkv', '.mp4', '.avi', '.m4v', '.webm'};

    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (videoExtensions.contains(ext)) {
          await processFile(entity.path);
        }
      }
    }
  }

  Future<void> processFile(String filePath) async {
    final filename = p.basename(filePath);

    // 1. Check if file is already registered in local_files
    final existing = await _db.getLocalFile(filePath);
    if (existing != null && existing['media_entity_id'] != null) {
      return; // Already mapped
    }

    print('Scanning file: "$filename"...');

    // 2. Query Simkl's file parser endpoint
    final match = await _simkl.matchFile(filename);
    if (match == null) {
      print('  -> No automated Simkl match found for $filename');
      // Fallback: Save as unmapped local file for manual pairing deck
      await _db.upsertLocalFile({
        'file_path': filePath,
        'file_size': await File(filePath).length(),
      });
      return;
    }

    print('  -> Matched via Simkl: ${match.title} (ID: ${match.id})');

    // 3. Ensure the media entity exists in SQLite database
    await _db.upsertMediaEntity({
      'id': 'simkl_${match.id}',
      'display_provider': 'simkl',
      'entity_type': 'anime',
      'title': match.title,
      'original_title': match.originalTitle,
      'poster_url': match.posterUrl,
      'overview': match.overview,
      'year': match.year,
      'total_episodes': match.totalEpisodes,
      'status': match.status,
      'average_score': match.averageScore,
      'simkl_id': int.tryParse(match.id),
      'mal_id': match.idMal,
      'franchise_id': match.title.toUpperCase(),
    });

    // 4. Fetch and cache episodes if not already populated
    final episodes = await _simkl.fetchManifest(match.id);
    for (var ep in episodes) {
      await _db.upsertEpisode({
        'id': ep.id,
        'media_entity_id': 'simkl_${match.id}',
        'season_number': ep.seasonNumber,
        'episode_number': ep.episodeNumber,
        'title': ep.title,
        'is_filler': ep.isFiller ? 1 : 0,
      });
    }

    // 5. Link the physical file to the corresponding episode row
    // (Simkl file match returns episode number directly in its metadata payload if available)
    // For now, we link the file path to its media entity bundle.
    await _db.upsertLocalFile({
      'file_path': filePath,
      'media_entity_id': 'simkl_${match.id}',
      'file_size': await File(filePath).length(),
    });

    print('  -> Successfully mapped and linked to local library database.\n');
  }
}