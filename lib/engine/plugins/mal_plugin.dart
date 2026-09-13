// lib/engine/plugins/mal_plugin.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/logger.dart';
import '../auth/auth_credentials_store.dart';
import 'media_plugin.dart';
import 'models/plugin_models.dart';

class MALPlugin implements MediaPlugin {
  @override
  String get id => 'mal';
  @override
  String get name => 'MyAnimeList';
  @override
  PluginType get supportedType => PluginType.anime;

  static const String _malBaseUrl = 'https://api.myanimelist.net/v2';
  static const String _jikanBaseUrl = 'https://api.jikan.moe/v4';
  static const String _malFields =
      'id,title,main_picture,alternative_titles,start_date,synopsis,mean,num_episodes,status,media_type,related_anime';

  Future<String?> _getClientId() async {
    return await AuthCredentialsStore.instance.getMALClientId();
  }

  String _sanitizeQuery(String query) {
    return query
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ')
        .replaceAll(
      RegExp(
        r'\b(?:1080p|720p|480p|2160p|4k|uhd|hevc|x264|x265|av1|aac|flac|opus|web-dl|bluray|bdrip|remux|mkv|mp4)\b',
        caseSensitive: false,
      ),
      ' ',
    )
        .replaceAll(RegExp(r'[\._\s\-]+'), ' ')
        .trim();
  }

  @override
  Future<List<MediaSearchResult>> search(String query, {bool isManualSearch = false}) async {
    final clean = _sanitizeQuery(query);
    if (clean.isEmpty) return [];

    final clientId = await _getClientId();
    if (clientId != null && clientId.isNotEmpty) {
      return _searchMAL(clean, clientId);
    } else {
      return _searchJikan(clean);
    }
  }

  Future<List<MediaSearchResult>> _searchMAL(String query, String clientId) async {
    final url = Uri.parse(
      '$_malBaseUrl/anime?q=${Uri.encodeComponent(query)}&limit=10&fields=id,title,main_picture,alternative_titles,start_date,num_episodes,media_type,status,mean',
    );
    appLog('Searching MAL API for: "$query"', tag: 'MAL');
    try {
      final res = await http.get(
        url,
        headers: {'X-MAL-CLIENT-ID': clientId},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['data'] ?? [];
        return list.map((item) => _parseMALMedia(item['node'])).toList();
      }
    } catch (e) {
      appLog('MAL search error: $e', tag: 'MAL');
    }
    return [];
  }

  Future<List<MediaSearchResult>> _searchJikan(String query) async {
    final url = Uri.parse('$_jikanBaseUrl/anime?q=${Uri.encodeComponent(query)}&limit=10');
    appLog('Searching Jikan for: "$query"', tag: 'MAL');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic>? list = data['data'];
        if (list != null) {
          return list.map((item) => _parseJikanMedia(item)).toList();
        }
      }
    } catch (e) {
      appLog('Jikan search error: $e', tag: 'MAL');
    }
    return [];
  }

  @override
  Future<List<EpisodeManifest>> fetchManifest(String mediaId) async {
    final cleanId = mediaId.replaceAll(RegExp(r'^(mal_|anilist_)'), '');
    final clientId = await _getClientId();
    int? count;

    if (clientId != null && clientId.isNotEmpty) {
      final data = await _fetchMALDetails(cleanId, clientId);
      count = data?['num_episodes'];
    } else {
      final data = await _fetchJikanDetailsWithRetry(cleanId);
      count = data?['episodes'];
    }

    if (count == null || count == 0) return [];
    return List.generate(
      count,
          (i) => EpisodeManifest(
        id: 'mal_${cleanId}_${i + 1}',
        seasonNumber: 1,
        episodeNumber: i + 1,
        title: 'Episode ${i + 1}',
        isFiller: false,
      ),
    );
  }

  @override
  Future<FranchiseManifest> fetchFranchise(String id) async {
    String cleanId = id.replaceAll(RegExp(r'^(mal_|anilist_)'), '');

    // AniList to MAL ID Bridge check
    final int? parsedNum = int.tryParse(cleanId);
    if (parsedNum != null && parsedNum > 60000) {
      try {
        final bridgeRes = await http.get(Uri.parse('https://api.ani.zip/mappings?anilist_id=$cleanId'));
        if (bridgeRes.statusCode == 200) {
          final bridgeJson = jsonDecode(bridgeRes.body);
          final int? bridgedMalId = bridgeJson['mappings']?['mal_id'];
          if (bridgedMalId != null) {
            appLog('Bridged AniList ID $cleanId -> MAL ID $bridgedMalId', tag: 'MAL');
            cleanId = bridgedMalId.toString();
          }
        }
      } catch (_) {}
    }

    final Map<String, SeriesManifest> entryMap = {};
    final Set<String> visited = {};
    final List<MapEntry<String, int>> queue = [MapEntry(cleanId, 0)];
    visited.add(cleanId);

    final clientId = await _getClientId();
    final bool useMAL = clientId != null && clientId.isNotEmpty;

    appLog(
      'Starting franchise traversal for MAL ID $cleanId (Mode: ${useMAL ? "Official MAL API" : "Jikan v4"})...',
      tag: 'MAL',
    );

    const allowedRelations = {
      'sequel',
      'prequel',
      'side_story',
      'side story',
      'alternative_version',
      'alternative setting',
      'parent_story',
      'parent story',
      'spin_off',
      'spin-off',
      'full_story',
      'summary',
      'other',
    };

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentId = current.key;
      final depth = current.value;

      if (depth >= 3) continue;

      dynamic data;
      if (useMAL) {
        data = await _fetchMALDetails(currentId, clientId);
      } else {
        data = await _fetchJikanDetailsWithRetry(currentId);
        await Future.delayed(const Duration(milliseconds: 350));
      }

      if (data == null) continue;

      final media = useMAL ? _parseMALMedia(data) : _parseJikanMedia(data);
      if (!entryMap.containsKey(media.id)) {
        final episodes = await fetchManifest(media.id);
        entryMap[media.id] = SeriesManifest(series: media, episodes: episodes);
      }

      // Official MAL Traversal
      if (useMAL) {
        final List<dynamic> related = data['related_anime'] ?? [];
        for (var item in related) {
          final node = item['node'];
          if (node == null) continue;
          final String nodeId = node['id'].toString();
          final String relType = item['relation_type']?.toString().toLowerCase() ?? '';

          if (allowedRelations.contains(relType)) {
            if (!visited.contains(nodeId)) {
              visited.add(nodeId);
              queue.add(MapEntry(nodeId, depth + 1));
            }
          }
        }
      }
      // Jikan Traversal
      else {
        final List<dynamic> relations = data['relations'] ?? [];
        for (var rel in relations) {
          final String relType = rel['relation']?.toString().toLowerCase() ?? '';
          if (allowedRelations.contains(relType)) {
            final List<dynamic> entries = rel['entry'] ?? [];
            for (var entry in entries) {
              if (entry['type'] == 'anime') {
                final String nodeId = entry['mal_id'].toString();
                if (!visited.contains(nodeId)) {
                  visited.add(nodeId);
                  queue.add(MapEntry(nodeId, depth + 1));
                }
              }
            }
          }
        }
      }
    }

    final sortedEntries = entryMap.values.toList();
    sortedEntries.sort((a, b) => (a.series.year ?? 0).compareTo(b.series.year ?? 0));
    appLog('Discovered ${sortedEntries.length} installments.', tag: 'MAL');
    return FranchiseManifest(entries: sortedEntries);
  }

  Future<dynamic> _fetchMALDetails(String id, String clientId) async {
    final url = Uri.parse('$_malBaseUrl/anime/$id?fields=$_malFields');
    try {
      final res = await http.get(
        url,
        headers: {'X-MAL-CLIENT-ID': clientId},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) {
      appLog('MAL details error for $id: $e', tag: 'MAL');
    }
    return null;
  }

  Future<dynamic> _fetchJikanDetailsWithRetry(String id, {int retries = 2}) async {
    final url = Uri.parse('$_jikanBaseUrl/anime/$id/full');
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body != null && body['data'] != null) {
            return body['data'];
          }
        } else if (res.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        appLog('Jikan details attempt $attempt error for $id: $e', tag: 'MAL');
      }
    }
    return null;
  }

// lib/engine/plugins/mal_plugin.dart
  MediaSearchResult _parseMALMedia(dynamic node) {
    double? parsedScore;
    if (node['mean'] != null) {
      parsedScore = (node['mean'] as num).toDouble();
    }

    // Robust year parsing (handles "YYYY-MM-DD", "YYYY-MM", or "YYYY")
    int? parsedYear;
    final rawStartDate = node['start_date']?.toString();
    if (rawStartDate != null && rawStartDate.isNotEmpty) {
      final yearMatch = RegExp(r'^(\d{4})').firstMatch(rawStartDate);
      if (yearMatch != null) {
        parsedYear = int.tryParse(yearMatch.group(1)!);
      }
    }

    final altTitles = node['alternative_titles'] as Map<String, dynamic>? ?? {};
    final String title = altTitles['en']?.isNotEmpty == true
        ? altTitles['en']
        : (node['title'] ?? 'Unknown');

    return MediaSearchResult(
      id: node['id'].toString(),
      providerId: id,
      title: title,
      originalTitle: node['title'],
      posterUrl: node['main_picture']?['large'] ?? node['main_picture']?['medium'],
      overview: node['synopsis'],
      year: parsedYear,
      totalEpisodes: node['num_episodes'],
      status: node['status']?.toString().toLowerCase(),
      averageScore: parsedScore,
      idMal: node['id'] as int?,
      rawFormat: node['media_type']?.toString(),
      endDate: node['end_date']?.toString(),
      type: _mapMediaType(node['media_type']),
    );
  }

  MediaSearchResult _parseJikanMedia(dynamic data) {
    double? parsedScore;
    if (data['score'] != null) {
      parsedScore = (data['score'] as num).toDouble();
    }

    return MediaSearchResult(
      id: data['mal_id'].toString(),
      providerId: id,
      title: data['title_english'] ?? data['title'] ?? 'Unknown',
      originalTitle: data['title_japanese'],
      posterUrl: data['images']?['jpg']?['large_image_url'] ?? data['images']?['jpg']?['image_url'],
      overview: data['synopsis'],
      year: data['year'] ?? (data['aired']?['prop']?['from']?['year']),
      totalEpisodes: data['episodes'],
      status: data['status']?.toString().toLowerCase(),
      averageScore: parsedScore,
      idMal: data['mal_id'] as int?,
      rawFormat: data['type']?.toString(),
      endDate: data['aired']?['to']?.toString(),
      type: _mapMediaType(data['type']),
    );
  }

  MediaType _mapMediaType(String? typeStr) {
    if (typeStr == null) return MediaType.anime;
    switch (typeStr.toLowerCase()) {
      case 'movie':
        return MediaType.movie;
      case 'tv':
        return MediaType.tv;
      case 'ova':
      case 'ona':
      case 'special':
        return MediaType.ova;
      default:
        return MediaType.anime;
    }
  }

  @override
  Future<bool> authenticate() async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<void> scrobble(String mediaId, int episode, double progress) async {}
}