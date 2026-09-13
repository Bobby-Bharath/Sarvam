import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/anilist_service.dart';
import '../auth/mal_service.dart';
import '../auth/simkl_service.dart';
import '../../utils/logger.dart';
import '../../database/media_database.dart';

class SyncDispatcher {
  static final SyncDispatcher instance = SyncDispatcher._internal();
  SyncDispatcher._internal();

  final _anilist = AniListService();
  final _mal = MALService();
  final _simkl = SIMKLService();

  Future<void> scrobbleEpisode({
    required String entityId,
    required int episodeNumber,
    int seasonNumber = 1,
    BuildContext? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('auto_scrobble_enabled') ?? true)) return;

    final String id = entityId.split('_').last;
    final int? anilistId = int.tryParse(id);
    if (anilistId == null) return;

    appLog('SyncDispatcher: Resolving mappings for AniList ID $anilistId', tag: 'Sync');

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scrobbling Ep $episodeNumber to active trackers...'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }

    try {
      final response = await http.get(Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId')).timeout(const Duration(seconds: 8));
      int? malId;
      int? simklId;
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mappings = data['mappings'];
        malId = mappings?['mal_id'];
        simklId = mappings?['simkl_id'];
      }

      final List<String> successes = [];
      final List<String> failures = [];

      final List<Future> jobs = [];

      if (prefs.getBool('anilist_logged_in') ?? false) {
        jobs.add(_anilist.scrobble(anilistId, episodeNumber)
            .then((_) => successes.add('AniList'))
            .catchError((e) {
              failures.add('AniList');
              _queueForRetry('anilist', anilistId, seasonNumber, episodeNumber);
              return null;
            }));
      }

      if (malId != null && (prefs.getBool('mal_logged_in') ?? false)) {
        jobs.add(_mal.scrobble(malId, episodeNumber)
            .then((_) => successes.add('MAL'))
            .catchError((e) {
              failures.add('MAL');
              _queueForRetry('mal', malId!, seasonNumber, episodeNumber);
              return null;
            }));
      }

      if (simklId != null && (prefs.getBool('simkl_logged_in') ?? false)) {
        jobs.add(_simkl.scrobble(simklId, seasonNumber, episodeNumber)
            .then((_) => successes.add('SIMKL'))
            .catchError((e) {
              failures.add('SIMKL');
              _queueForRetry('simkl', simklId!, seasonNumber, episodeNumber);
              return null;
            }));
      }

      await Future.wait(jobs);

      if (successes.isNotEmpty) {
         appLog('Successfully synced with ${successes.join(", ")}', tag: 'Sync');
      }
      
      if (context != null && context.mounted) {
        if (successes.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Synced with ${successes.join(", ")}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        if (failures.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Failed to sync with ${failures.join(", ")} (Queued for retry)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      appLog('Mapping/Scrobble error: $e', tag: 'Sync');
    }
  }

  Future<void> _queueForRetry(String service, int remoteId, int season, int episode) async {
    try {
      final db = await MediaDatabase.instance.database;
      await db.insert('pending_sync_queue', {
        'target_service': service,
        'remote_id': remoteId,
        'season_number': season,
        'episode_number': episode,
        'retry_count': 0,
        'last_error': 'Network/Service error',
      });
      appLog('Queued $service scrobble (Ep $episode) for retry', tag: 'Sync');
    } catch (e) {
      appLog('Failed to queue retry: $e', tag: 'Sync');
    }
  }

  Future<void> processRetryQueue() async {
    final db = await MediaDatabase.instance.database;
    final List<Map<String, dynamic>> pending = await db.query('pending_sync_queue', limit: 10);
    
    if (pending.isEmpty) return;
    appLog('Processing ${pending.length} pending scrobbles...', tag: 'Sync');

    final prefs = await SharedPreferences.getInstance();

    for (final job in pending) {
      final String service = job['target_service'];
      final int remoteId = job['remote_id'];
      final int ep = job['episode_number'];
      final int season = job['season_number'];
      final int jobId = job['id'];

      bool success = false;
      try {
        if (service == 'anilist' && (prefs.getBool('anilist_logged_in') ?? false)) {
          await _anilist.scrobble(remoteId, ep);
          success = true;
        } else if (service == 'mal' && (prefs.getBool('mal_logged_in') ?? false)) {
          await _mal.scrobble(remoteId, ep);
          success = true;
        } else if (service == 'simkl' && (prefs.getBool('simkl_logged_in') ?? false)) {
          await _simkl.scrobble(remoteId, season, ep);
          success = true;
        }

        if (success) {
          await db.delete('pending_sync_queue', where: 'id = ?', whereArgs: [jobId]);
          appLog('Successfully retried $service scrobble (Ep $ep)', tag: 'Sync');
        } else {
          // Increment retry count or just wait for next cycle
          await db.rawUpdate('UPDATE pending_sync_queue SET retry_count = retry_count + 1 WHERE id = ?', [jobId]);
        }
      } catch (e) {
        appLog('Retry failed for $service (Ep $ep): $e', tag: 'Sync');
        await db.rawUpdate('UPDATE pending_sync_queue SET retry_count = retry_count + 1 WHERE id = ?', [jobId]);
      }
    }
  }
}
