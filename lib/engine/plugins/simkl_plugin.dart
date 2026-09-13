// lib/engine/plugins/simkl_plugin.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/logger.dart';
import '../auth/auth_credentials_store.dart';
import 'media_plugin.dart';
import 'models/plugin_models.dart';

class SimklPlugin implements MediaPlugin {
  @override
  String get id => 'simkl';
  @override
  String get name => 'Simkl';
  @override
  PluginType get supportedType => PluginType.universal;

  static const String _baseUrl = 'https://api.simkl.com';
  static const String _appName = 'sarvam-player';
  static const String _appVersion = '1.0';

  static const Set<String> _genericQueries = {
    'movies',
    'movie',
    'anime',
    'download',
    'downloads',
    'folder',
    'new folder',
    'temp',
    'tmp',
    'stuff',
    'media',
    'files',
    'file',
    'episodes',
    'episode',
    'shows',
    'show',
    'tv',
    'uncategorized',
    'misc',
    'videos',
    'video',
    'default',
    'test',
    'season',
    'seasons',
    'series',
  };

  Future<String> _getClientId() async {
    final storedKey = await AuthCredentialsStore.instance.getSimklClientId();
    final clientId = (storedKey != null && storedKey.isNotEmpty)
        ? storedKey
        : '2e9e4a59b3053e770f2b5c2154bb8321386b2271826c2d2fe8f5f22268722b4b'; // Fallback

    final masked = clientId.length > 8
        ? '${clientId.substring(0, 4)}...${clientId.substring(clientId.length - 4)}'
        : '***';
    appLog('Active Simkl Client ID: $masked', tag: 'SIMKL');
    return clientId;
  }

  Map<String, String> _headers(String clientId) => {
    'User-Agent': '$_appName/$_appVersion',
    'Content-Type': 'application/json',
    'simkl-api-key': clientId,
  };

  String _sanitizeQuery(String query) {
    return query
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)|<.*?>|\{.*?\}', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:1080p|720p|480p|2160p|4k|uhd|hevc|x264|x265|av1|aac|flac|opus|web-dl|bluray|bdrip|remux|mkv|mp4|avi|sub|dub|dual-audio|multi-audio|subsplease|erai-raws|horriblesubs)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[\._\s\-]+'), ' ')
        .trim();
  }

  bool _isInvalidOrGenericQuery(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 2) return true;
    if (_genericQueries.contains(clean)) return true;
    return false;
  }

  @override
  Future<List<MediaSearchResult>> search(String query, {bool isManualSearch = false}) async {
    final cleanQuery = _sanitizeQuery(query);
    
    // Only apply the generic directory guardrail during automatic folder discovery
    if (!isManualSearch && _isInvalidOrGenericQuery(cleanQuery)) {
      appLog(
        'Simkl search skipped for generic query during automated scan: "$query" (sanitized: "$cleanQuery")',
        tag: 'SIMKL',
      );
      return [];
    }

    if (cleanQuery.trim().isEmpty) return [];

    final clientId = await _getClientId();
    final categories = ['anime', 'tv', 'movie'];

    appLog('Searching Simkl across [anime, tv, movie] for: "$cleanQuery" (manual: $isManualSearch)', tag: 'SIMKL');

    final searchFutures = categories.map((cat) async {
      final url = Uri.parse(
        '$_baseUrl/search/$cat?q=${Uri.encodeComponent(cleanQuery)}&limit=10&extended=full&client_id=$clientId&app-name=$_appName&app-version=$_appVersion',
      );

      try {
        final res = await http.get(url, headers: _headers(clientId)).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final dynamic decoded = jsonDecode(res.body);
          if (decoded is List) {
            return decoded.map((item) => _parseSimklMedia(item)).toList();
          }
        } else {
          appLog('Simkl $cat search failed with status ${res.statusCode}', tag: 'SIMKL');
        }
      } on TimeoutException {
        appLog('Simkl $cat search timed out after 10s for query "$cleanQuery"', tag: 'SIMKL');
      } on FormatException catch (e) {
        appLog('Simkl $cat search JSON decode error for "$cleanQuery": $e', tag: 'SIMKL');
      } catch (e) {
        appLog('Simkl $cat search error: $e', tag: 'SIMKL');
      }
      return <MediaSearchResult>[];
    });

    final resultsList = await Future.wait(searchFutures);

    // Combine and deduplicate results by item.id
    final Map<String, MediaSearchResult> deduplicated = {};
    for (var list in resultsList) {
      for (var item in list) {
        if (item.id.isNotEmpty && !deduplicated.containsKey(item.id)) {
          deduplicated[item.id] = item;
        }
      }
    }

    return deduplicated.values.toList();
  }

  // Finds item by filename using Simkl's file parser
  Future<MediaSearchResult?> matchFile(String filename) async {
    final cleanFilename = _sanitizeQuery(filename);
    if (cleanFilename.isEmpty) return null;

    final clientId = await _getClientId();
    final url = Uri.parse(
      '$_baseUrl/search/file?client_id=$clientId&app-name=$_appName&app-version=$_appVersion',
    );

    try {
      final res = await http.post(
        url,
        headers: _headers(clientId),
        body: jsonEncode({'file': filename}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final dynamic data = jsonDecode(res.body);
        if (data == null || data is List) return null; // 'null' or '[]' means no match

        final showNode = data['show'] ?? data['movie'];
        if (showNode != null) {
          return _parseSimklMedia(showNode);
        }
      } else {
        appLog('Simkl file search failed with status ${res.statusCode} for $filename', tag: 'SIMKL');
      }
    } on TimeoutException {
      appLog('Simkl file search timed out after 10s for $filename', tag: 'SIMKL');
    } on FormatException catch (e) {
      appLog('Simkl file search JSON decode error for $filename: $e', tag: 'SIMKL');
    } catch (e) {
      appLog('Simkl file search error for $filename: $e', tag: 'SIMKL');
    }
    return null;
  }

  // Cross-reference AniList/MAL IDs directly to Simkl metadata
  Future<Map<String, dynamic>?> resolveExternalId({int? malId, int? anilistId}) async {
    final clientId = await _getClientId();
    String queryParam = '';
    if (malId != null) queryParam = 'mal=$malId';
    if (anilistId != null) queryParam = 'anilist=$anilistId';
    if (queryParam.isEmpty) return null;

    final url = Uri.parse(
      '$_baseUrl/search/id?$queryParam&client_id=$clientId&app-name=$_appName&app-version=$_appVersion',
    );

    try {
      final res = await http.get(url, headers: _headers(clientId)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final dynamic list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) return list.first;
      } else {
        appLog('Simkl external ID resolve failed with status ${res.statusCode}', tag: 'SIMKL');
      }
    } on TimeoutException {
      appLog('Simkl external ID resolve timed out after 10s', tag: 'SIMKL');
    } on FormatException catch (e) {
      appLog('Simkl external ID resolve JSON decode error: $e', tag: 'SIMKL');
    } catch (e) {
      appLog('Simkl external ID resolve error: $e', tag: 'SIMKL');
    }
    return null;
  }

  @override
  Future<List<EpisodeManifest>> fetchManifest(String mediaId) async {
    final cleanId = mediaId.replaceAll(RegExp(r'^(simkl_)'), '');
    if (cleanId.trim().isEmpty) return [];

    final clientId = await _getClientId();
    final categories = ['anime', 'tv'];

    for (var cat in categories) {
      final url = Uri.parse(
        '$_baseUrl/$cat/episodes/$cleanId?extended=full&client_id=$clientId&app-name=$_appName&app-version=$_appVersion',
      );

      try {
        final res = await http.get(url, headers: _headers(clientId)).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final dynamic decoded = jsonDecode(res.body);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded.map((ep) {
              return EpisodeManifest(
                id: 'simkl_${cleanId}_${ep['episode']}',
                seasonNumber: ep['season'] ?? 1,
                episodeNumber: ep['episode'] ?? 1,
                title: ep['title'] ?? 'Episode ${ep['episode']}',
                isFiller: ep['type'] == 'filler',
              );
            }).toList();
          }
        }
      } catch (_) {}
    }
    return [];
  }

  @override
  Future<FranchiseManifest> fetchFranchise(String id) async {
    final cleanId = id.replaceAll(RegExp(r'^(simkl_)'), '');
    if (cleanId.trim().isEmpty) return FranchiseManifest(entries: []);

    final Map<String, SeriesManifest> entryMap = {};
    final Set<String> visited = {cleanId};
    final List<MapEntry<String, int>> queue = [MapEntry(cleanId, 0)];

    final clientId = await _getClientId();
    final endpoints = ['anime', 'tv', 'movies'];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentId = current.key;
      final depth = current.value;

      if (depth >= 3) continue;

      dynamic fetchedData;
      for (var endpoint in endpoints) {
        final url = Uri.parse(
          '$_baseUrl/$endpoint/$currentId?extended=full&client_id=$clientId&app-name=$_appName&app-version=$_appVersion',
        );

        try {
          final res = await http.get(url, headers: _headers(clientId)).timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) {
            final dynamic data = jsonDecode(res.body);
            if (data is Map<String, dynamic> && data['title'] != null) {
              fetchedData = data;
              break;
            }
          }
        } catch (_) {}
      }

      if (fetchedData != null && fetchedData is Map<String, dynamic>) {
        final media = _parseSimklMedia(fetchedData);
        if (!entryMap.containsKey(media.id)) {
          final episodes = await fetchManifest(currentId);
          entryMap[media.id] = SeriesManifest(series: media, episodes: episodes);
        }

        final List<dynamic> relations = fetchedData['relations'] ?? fetchedData['related'] ?? [];
        for (var rel in relations) {
          if (rel is Map<String, dynamic>) {
            final relSimklId = rel['ids']?['simkl_id'] ?? rel['ids']?['simkl'] ?? rel['simkl_id'];
            if (relSimklId != null) {
              final String relIdStr = relSimklId.toString();
              if (!visited.contains(relIdStr)) {
                visited.add(relIdStr);
                queue.add(MapEntry(relIdStr, depth + 1));
              }
            }
          }
        }
      }
    }

    final sorted = entryMap.values.toList();
    sorted.sort((a, b) => (a.series.year ?? 0).compareTo(b.series.year ?? 0));

    appLog('Discovered ${sorted.length} Simkl franchise installments.', tag: 'SIMKL');
    return FranchiseManifest(entries: sorted);
  }

  MediaSearchResult _parseSimklMedia(dynamic node) {
    if (node is! Map<String, dynamic>) {
      return MediaSearchResult(
        id: '',
        providerId: 'simkl',
        title: 'Unknown',
      );
    }

    double? rating;
    if (node['ratings']?['simkl']?['rating'] != null) {
      rating = (node['ratings']['simkl']['rating'] as num).toDouble();
    } else if (node['ratings']?['mal']?['rating'] != null) {
      rating = (node['ratings']['mal']['rating'] as num).toDouble();
    }

    final posterPath = node['poster'];
    final posterUrl = (posterPath != null && posterPath is String && posterPath.isNotEmpty)
        ? 'https://wsrv.nl/?url=https://simkl.in/posters/${posterPath}_m.webp'
        : null;

    final ids = node['ids'] as Map<String, dynamic>? ?? {};
    final simklId = ids['simkl_id'] ?? ids['simkl'] ?? node['simkl_id'] ?? '';

    return MediaSearchResult(
      id: simklId.toString(),
      providerId: id,
      title: node['title']?.toString() ?? 'Unknown',
      originalTitle: node['title']?.toString(),
      posterUrl: posterUrl,
      overview: node['overview']?.toString(),
      year: node['year'] as int?,
      totalEpisodes: node['total_episodes'] as int?,
      status: node['status']?.toString().toLowerCase(),
      averageScore: rating,
      idMal: ids['mal'] is int ? ids['mal'] as int : int.tryParse(ids['mal']?.toString() ?? ''),
      rawFormat: node['type']?.toString() ?? node['anime_type']?.toString(),
      type: MediaType.anime,
    );
  }

  @override
  Future<bool> authenticate() async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<void> scrobble(String mediaId, int episode, double progress) async {}
}
