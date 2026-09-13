import 'dart:async';
import '../../database/media_database.dart';
import 'filename_tokenizer.dart';
import '../plugins/models/plugin_models.dart';
import '../plugins/plugin_registry.dart';

class MediaMatcherService {
  final MediaDatabase _db = MediaDatabase.instance;

  Future<void> pairFileWithResult(String filePath, MediaSearchResult result, {int? episodeOverride}) async {
    final fileName = filePath.split(RegExp(r'[\\/]')).last;
    final token = FilenameTokenizer.parse(fileName);
    final String entityId = '${result.providerId}_${result.id}';

    await _upsertResult(result);

    final int epNum = episodeOverride ?? token.episodeNumber ?? 1;
    final String targetEpId = '${entityId}_E$epNum';
    await _db.updateLocalFileLinks(filePath, entityId, targetEpId);
  }

  Future<void> pairFolderWithResult(String folderPath, List<String> filePaths, MediaSearchResult result) async {
    final String entityId = '${result.providerId}_${result.id}';

    await _upsertResult(result, folderPath: folderPath);

    for (var path in filePaths) {
      final fileName = path.split(RegExp(r'[\\/]')).last;
      final token = FilenameTokenizer.parse(fileName);
      final int epNum = token.episodeNumber ?? 1;
      final String targetEpId = '${entityId}_E$epNum';
      await _db.updateLocalFileLinks(path, entityId, targetEpId);
    }
  }

  Future<void> _upsertResult(MediaSearchResult result, {String? folderPath}) async {
    final String entityId = '${result.providerId}_${result.id}';
    
    await _db.upsertMediaEntity({
      'id': entityId,
      'display_provider': result.providerId.toUpperCase(),
      'entity_type': result.type.name.toUpperCase(),
      'folder_path': folderPath,
      'title': result.title,
      'original_title': result.originalTitle ?? result.title,
      'poster_url': result.posterUrl,
      'backdrop_url': result.backdropUrl,
      'overview': result.overview,
      'year': result.year,
      'total_episodes': result.totalEpisodes,
    });

    // If it's a plugin that supports manifest fetching, get real episodes
    final plugin = PluginRegistry.instance.getPlugin(result.providerId);
    if (plugin != null) {
      final manifest = await plugin.fetchManifest(result.id);
      if (manifest.isNotEmpty) {
        for (var ep in manifest) {
          await _db.upsertEpisode({
            'id': '${entityId}_E${ep.episodeNumber}',
            'media_entity_id': entityId,
            'season_number': ep.seasonNumber,
            'episode_number': ep.episodeNumber,
            'title': ep.title ?? 'Episode ${ep.episodeNumber}',
            'overview': ep.overview,
            'still_path': ep.stillPath,
            'air_date': ep.airDate,
          });
        }
        return;
      }
    }

    // Fallback: Generate ghost manifest if no real manifest found
    final int totalEps = result.totalEpisodes ?? 24;
    for (int i = 1; i <= totalEps; i++) {
      final String epId = '${entityId}_E$i';
      await _db.upsertEpisode({
        'id': epId,
        'media_entity_id': entityId,
        'season_number': 1,
        'episode_number': i,
        'title': 'Episode $i',
      });
    }
  }

  Future<void> matchAndIndexFile(String filePath) async {
    final fileName = filePath.split(RegExp(r'[\\/]')).last;
    final token = FilenameTokenizer.parse(fileName);

    final results = await PluginRegistry.instance.searchUnified(token.cleanTitle);
    if (results.isNotEmpty) {
      await pairFileWithResult(filePath, results.first);
    }
  }
}
