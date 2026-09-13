// lib/engine/plugins/anilist_plugin.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'media_plugin.dart';
import 'models/plugin_models.dart';
import '../auth/oauth_manager.dart';
import '../../utils/logger.dart';

class AniListPlugin implements MediaPlugin {
  @override
  String get id => 'anilist';
  @override
  String get name => 'AniList';
  @override
  PluginType get supportedType => PluginType.anime;

  static const String _endpoint = 'https://graphql.anilist.co';

  static const String _mediaFragment = r'''
    id
    idMal
    title { userPreferred english romaji }
    format
    status
    episodes
    description(asHtml: false)
    startDate { year month day }
    averageScore
    coverImage { extraLarge large }
    bannerImage
  ''';

  static const String _byIdQuery = '''
    query (\$id: Int) {
      Media(id: \$id, type: ANIME) {
        $_mediaFragment
        relations {
          edges {
            relationType(version: 2)
            node {
              $_mediaFragment
              type
            }
          }
        }
      }
    }
  ''';

  static const String _byMalIdQuery = '''
    query (\$idMal: Int) {
      Media(idMal: \$idMal, type: ANIME) {
        $_mediaFragment
        relations {
          edges {
            relationType(version: 2)
            node {
              $_mediaFragment
              type
            }
          }
        }
      }
    }
  ''';

  static const String _searchPageQuery = '''
    query (\$search: String) {
      Page(page: 1, perPage: 10) {
        media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
          $_mediaFragment
        }
      }
    }
  ''';

  @override
  Future<List<MediaSearchResult>> search(String query, {bool isManualSearch = false}) async {
    final cleanQuery = query.replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\b(S\d+|E\d+|1080p|720p|x265|x264|HEVC|AVC|AMZN|WEB-DL|DDP\d+\.\d+|Dual-Audio|Multi-Audio)\b.*', caseSensitive: false), '')
        .trim();

    appLog('Searching AniList for: "$cleanQuery"', tag: 'AniList');

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'OmniPlayer/1.0',
        },
        body: jsonEncode({
          'query': _searchPageQuery,
          'variables': {'search': cleanQuery},
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> list = body['data']?['Page']?['media'] ?? [];
        return list.map((data) => _parseMedia(data)).toList();
      }
    } catch (e) {
      appLog('AniList search exception: $e', tag: 'AniList');
    }
    return [];
  }

  @override
  Future<List<EpisodeManifest>> fetchManifest(String mediaId) async {
    final mediaData = await _fetchMediaWithRelations(mediaId);
    if (mediaData == null) return [];

    final int? count = mediaData['episodes'];
    if (count == null || count == 0) return [];

    return List.generate(count, (i) => EpisodeManifest(
      id: '${mediaId}_${i+1}',
      seasonNumber: 1,
      episodeNumber: i + 1,
      title: 'Episode ${i+1}',
      isFiller: false,
    ));
  }

  @override
  Future<FranchiseManifest> fetchFranchise(String mediaId) async {
    Map<String, SeriesManifest> entryMap = {};
    Set<String> visited = {};
    List<MapEntry<String, int>> queue = [];

    bool isMalId = false;
    String cleanId = mediaId;

    if (mediaId.startsWith('mal_')) {
      isMalId = true;
      cleanId = mediaId.substring(4);
    } else if (mediaId.startsWith('anilist_')) {
      isMalId = false;
      cleanId = mediaId.substring(8);
    }

    appLog('Starting deep BFS franchise discovery for $cleanId (isMal: $isMalId)...', tag: 'AniList');

    // Uses fallback inside _fetchMediaWithRelations
    final rootData = await _fetchMediaWithRelations(cleanId, asMal: isMalId);
    if (rootData == null) return FranchiseManifest(entries: []);

    final String rootAniId = rootData['id'].toString();
    queue.add(MapEntry(rootAniId, 0));
    visited.add(rootAniId);

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentId = current.key;
      final depth = current.value;

      if (depth >= 3) continue;

      final data = await _fetchMediaWithRelations(currentId, asMal: false);
      if (data == null) continue;

      final media = _parseMedia(data);
      if (!entryMap.containsKey(media.id)) {
        final episodes = await fetchManifest(media.id);
        entryMap[media.id] = SeriesManifest(series: media, episodes: episodes);
      }

      final List<dynamic> edges = data['relations']?['edges'] ?? [];
      for (var edge in edges) {
        final String? relType = edge['relationType'];
        final node = edge['node'];
        if (node == null) continue;

        final String nodeId = node['id'].toString();

        if (node['type'] == 'ANIME' && ['SEQUEL', 'PREQUEL', 'SIDE_STORY', 'SPIN_OFF', 'ALTERNATIVE', 'PARENT'].contains(relType)) {
          if (!visited.contains(nodeId)) {
            visited.add(nodeId);
            queue.add(MapEntry(nodeId, depth + 1));
          }
        }
      }
    }

    final sortedEntries = entryMap.values.toList();
    sortedEntries.sort((a, b) => (a.series.year ?? 0).compareTo(b.series.year ?? 0));

    appLog('Discovered ${sortedEntries.length} franchise installments.', tag: 'AniList');
    return FranchiseManifest(entries: sortedEntries);
  }

  Future<dynamic> _fetchMediaWithRelations(String id, {bool asMal = false}) async {
    final int? parsedId = int.tryParse(id);
    if (parsedId == null) return null;

    Future<dynamic> executeQuery(String query, Map<String, dynamic> vars) async {
      try {
        final response = await http.post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'query': query, 'variables': vars}),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          return body['data']?['Media'];
        }
      } catch (_) {}
      return null;
    }

    // 1. Primary lookup based on asMal flag
    dynamic data = await executeQuery(
      asMal ? _byMalIdQuery : _byIdQuery,
      asMal ? {'idMal': parsedId} : {'id': parsedId},
    );

    // 2. Safe Fallback: if the primary key returned null, attempt the alternative key
    if (data == null) {
      data = await executeQuery(
        asMal ? _byIdQuery : _byMalIdQuery,
        asMal ? {'id': parsedId} : {'idMal': parsedId},
      );
    }

    return data;
  }

  MediaSearchResult _parseMedia(dynamic data) {
    double? parsedScore;
    if (data['averageScore'] != null) {
      parsedScore = (data['averageScore'] as num).toDouble();
    }

    return MediaSearchResult(
      id: data['id'].toString(),
      providerId: id,
      title: data['title']['userPreferred'] ?? data['title']['romaji'] ?? 'Unknown',
      originalTitle: data['title']['english'],
      overview: data['description'],
      posterUrl: data['coverImage']?['extraLarge'] ?? data['coverImage']?['large'],
      backdropUrl: data['bannerImage'],
      year: data['startDate']?['year'],
      status: data['status']?.toLowerCase(),
      averageScore: parsedScore,
      totalEpisodes: data['episodes'],
      idMal: data['idMal'],
      rawFormat: data['format']?.toString(),
      type: _mapFormatToType(data['format']),
    );
  }

  MediaType _mapFormatToType(String? format) {
    if (format == null) return MediaType.anime;
    switch (format.toUpperCase()) {
      case 'MOVIE': return MediaType.movie;
      case 'TV': return MediaType.tv;
      case 'TV_SHORT': return MediaType.tv;
      case 'OVA': return MediaType.ova;
      case 'ONA': return MediaType.ova;
      case 'SPECIAL': return MediaType.ova;
      default: return MediaType.anime;
    }
  }

  @override
  Future<bool> authenticate() async => false;
  @override
  Future<void> logout() async {}

  @override
  Future<void> scrobble(String mediaId, int episode, double progress) async {
    final token = await OAuthManager.instance.getToken('anilist');
    if (token == null) throw Exception('AniList not connected');

    const String mutation = r'''
      mutation ($mediaId: Int, $progress: Int) {
        SaveMediaListEntry (mediaId: $mediaId, progress: $progress, status: CURRENT) {
          id
          progress
        }
      }
    ''';

    final int? parsedMediaId = int.tryParse(mediaId);
    if (parsedMediaId == null) throw Exception('Invalid mediaId: $mediaId');

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': mutation,
        'variables': {
          'mediaId': parsedMediaId,
          'progress': episode,
        },
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('AniList scrobble failed: ${response.body}');
    }
  }
}