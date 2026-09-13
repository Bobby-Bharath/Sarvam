import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../database/media_database.dart';
import '../../utils/logger.dart';

class JikanService {
  static final Map<int, Map<int, String>> _typeCache = {};

  // Static canon-accurate filler ranges for major long-runners when scrapers fail
  static const Map<int, List<int>> _offlineFillerDB = {
    // Bleach (MAL ID 244)
    244: [
      33, 50,
      // Bount Arc
      64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
      // Standoff / Forest of Menos / New Captain Amagai
      128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 147, 148, 149,
      168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189,
      204, 205, 213, 214,
      // Zanpakuto Rebellion
      228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265,
      287, 298, 299, 303, 304, 305,
      // Gotei 13 Invading Army
      311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341,
      355
    ],
  };

  static Future<Map<int, String>> getEpisodeTypeFlags(int? malId) async {
    if (malId == null || malId == 0) return {};
    if (_typeCache.containsKey(malId)) return _typeCache[malId]!;

    final Map<int, String> typeMap = {};

    // 1. Instant check: Hardcoded offline fallback for popular long-runners
    if (_offlineFillerDB.containsKey(malId)) {
      for (final epNum in _offlineFillerDB[malId]!) {
        typeMap[epNum] = 'FILLER';
      }
      _typeCache[malId] = typeMap;
      appLog('Used offline verified filler database for $malId. Mapped ${typeMap.length} fillers.', tag: 'Jikan');
      return typeMap;
    }

    // 2. Fallback to ani.zip API (Fast, single-shot)
    try {
      final res = await http.get(Uri.parse('https://api.ani.zip/mappings?mal_id=$malId')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final eps = body['episodes'] as Map<String, dynamic>? ?? {};
        for (final entry in eps.entries) {
          final epNum = int.tryParse(entry.key);
          final epData = entry.value as Map<String, dynamic>? ?? {};
          
          final isFiller = epData['isFiller'] == true || epData['type']?.toString().toLowerCase() == 'filler';
          final isRecap = epData['isRecap'] == true || epData['type']?.toString().toLowerCase() == 'recap';
          final isSpecial = epData['type']?.toString().toLowerCase() == 'special';

          if (epNum != null) {
            if (isRecap) typeMap[epNum] = 'RECAP';
            else if (isFiller) typeMap[epNum] = 'FILLER';
            else if (isSpecial) typeMap[epNum] = 'SPECIAL';
          }
        }
        if (typeMap.isNotEmpty) {
          _typeCache[malId] = typeMap;
          appLog('[FillerEngine] ani.zip resolved ${typeMap.length} flags for $malId.', tag: 'Jikan');
          return typeMap;
        }
      }
    } catch (_) {}

    // 3. Fallback to Jikan (Slow, paginated)
    try {
      final res = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/$malId/episodes')).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List<dynamic> episodes = body['data'] ?? [];
        for (var ep in episodes) {
          final int? epNum = ep['mal_id'] is int ? ep['mal_id'] : int.tryParse(ep['mal_id'].toString());
          final bool isFiller = ep['filler'] == true;
          final bool isRecap = ep['recap'] == true;

          if (epNum != null) {
            if (isRecap) typeMap[epNum] = 'RECAP';
            else if (isFiller) typeMap[epNum] = 'FILLER';
          }
        }
        _typeCache[malId] = typeMap;
        appLog('[FillerEngine] Jikan resolved ${typeMap.length} flags for $malId.', tag: 'Jikan');
      }
    } catch (_) {}

    return typeMap;
  }

  static Future<void> persistFillersToDb(String entityId, int? malId) async {
    if (malId == null || malId == 0) return;
    final flags = await getEpisodeTypeFlags(malId);
    if (flags.isEmpty) return;

    final db = await MediaDatabase.instance.database;
    await db.transaction((txn) async {
      for (var entry in flags.entries) {
        await txn.execute(
          'UPDATE episodes SET is_filler = ?, episode_type = ? WHERE media_entity_id = ? AND episode_number = ?',
          [entry.value == 'FILLER' ? 1 : 0, entry.value, entityId, entry.key],
        );
      }
    });
    appLog('Persisted ${flags.length} episode flags for $entityId', tag: 'Jikan');
  }

  static Future<int?> resolveMalIdFromAnilist(int anilistId) async {
    try {
      final response = await http.get(Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId')).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['mappings']?['mal_id'];
      }
    } catch (e) {
      appLog('Failed to resolve MAL ID from AniZip: $e', tag: 'Jikan');
    }
    return null;
  }

  static Future<int?> resolveMalIdFromKitsu(String kitsuId) async {
    try {
      final response = await http.get(Uri.parse('https://api.ani.zip/mappings?kitsu_id=$kitsuId')).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['mappings']?['mal_id'];
      }
    } catch (e) {
      appLog('Failed to resolve MAL ID for Kitsu $kitsuId: $e', tag: 'Jikan');
    }
    return null;
  }

  static Future<int?> resolveAnilistIdFromKitsu(String kitsuId) async {
    try {
      final response = await http.get(Uri.parse('https://api.ani.zip/mappings?kitsu_id=$kitsuId')).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['mappings']?['anilist_id'];
      }
    } catch (e) {
      appLog('Failed to resolve AniList ID for Kitsu $kitsuId: $e', tag: 'Jikan');
    }
    return null;
  }

  static Future<int?> resolveMalIdBySearch(String title, int? year) async {
    final cleanTitle = title
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\mid.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(S\d+|E\d+|1080p|720p|x265|x264|HEVC|AVC|AMZN|WEB-DL|DDP\d+\.\d+|Dual-Audio|Multi-Audio)\b.*', caseSensitive: false), '')
        .trim();
        
    final url = Uri.parse('https://api.jikan.moe/v4/anime?q=${Uri.encodeComponent(cleanTitle)}&limit=1');
    
    appLog('Searching MAL ID for "$cleanTitle"...', tag: 'Jikan');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> results = data['data'] ?? [];
        if (results.isNotEmpty) {
           final malId = results.first['mal_id'];
           appLog('Resolved MAL ID: $malId for "$title"', tag: 'Jikan');
           return malId;
        }
      }
    } catch (e) {
      appLog('Search resolution failed: $e', tag: 'Jikan');
    }
    return null;
  }
}
