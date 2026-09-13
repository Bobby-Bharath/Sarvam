import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'media_plugin.dart';
import 'models/plugin_models.dart';
import '../../utils/logger.dart';

class KitsuPlugin implements MediaPlugin {
  @override
  String get id => 'kitsu';
  @override
  String get name => 'Kitsu';
  @override
  PluginType get supportedType => PluginType.anime;

  @override
  Future<List<MediaSearchResult>> search(String query, {bool isManualSearch = false}) async {
    final cleanQuery = query.replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\b(S\d+|E\d+|1080p|720p|x265|x264|HEVC|AVC|AMZN|WEB-DL|DDP\d+\.\d+|Dual-Audio|Multi-Audio)\b.*', caseSensitive: false), '')
        .trim();
        
    final encodedQuery = Uri.encodeComponent(cleanQuery);
    final url = 'https://kitsu.io/api/edge/anime?filter[text]=$encodedQuery&page[limit]=10';

    appLog('Searching Kitsu for: "$cleanQuery"', tag: 'Kitsu');

    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/vnd.api+json',
        'Content-Type': 'application/vnd.api+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> list = data['data'];

        return list.map((item) => _parseMedia(item)).toList();
      }
    } on TimeoutException {
       appLog('Search request timed out.', tag: 'Kitsu');
    } catch (e) {
      appLog('Search error: $e', tag: 'Kitsu');
    }
    return [];
  }

  @override
  Future<List<EpisodeManifest>> fetchManifest(String mediaId) async {
    List<EpisodeManifest> allEpisodes = [];
    int offset = 0;
    bool hasMore = true;

    while (hasMore) {
      final url = 'https://kitsu.io/api/edge/anime/$mediaId/episodes?page[limit]=20&page[offset]=$offset&sort=number';
      try {
        final response = await http.get(Uri.parse(url), headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        }).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> list = data['data'];
          if (list.isEmpty) {
            hasMore = false;
            break;
          }

          allEpisodes.addAll(list.map((item) {
            final attr = item['attributes'];
            return EpisodeManifest(
              id: item['id'],
              seasonNumber: 1,
              episodeNumber: attr['number'] ?? 0,
              title: attr['canonicalTitle'] ?? attr['titles']?['en_jp'],
              overview: attr['synopsis'],
              stillPath: attr['thumbnail']?['original'],
              airDate: attr['airdate'],
              isFiller: false,
            );
          }));

          offset += 20;
          if (list.length < 20) hasMore = false;
        } else {
          hasMore = false;
        }
      } catch (e) {
        appLog('Manifest error for $mediaId: $e', tag: 'Kitsu');
        hasMore = false;
      }
    }
    return allEpisodes;
  }

  @override
  Future<FranchiseManifest> fetchFranchise(String mediaId) async {
    Map<String, SeriesManifest> entryMap = {};
    List<MapEntry<String, int>> queue = [MapEntry(mediaId, 0)];
    Set<String> visited = {mediaId};

    appLog('Starting deep franchise discovery (Kitsu) for $mediaId...', tag: 'Kitsu');

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentId = current.key;
      final depth = current.value;

      if (depth >= 3) continue;

      final url = 'https://kitsu.io/api/edge/anime/$currentId?include=mediaRelationships.destination';
      try {
        final response = await http.get(Uri.parse(url), headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        }).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final data = body['data'];
          final List<dynamic> included = body['included'] ?? [];
          
          final media = _parseMedia(data);
          if (!entryMap.containsKey(media.id)) {
             final episodes = await fetchManifest(currentId);
             entryMap[media.id] = SeriesManifest(series: media, episodes: episodes);
          }

          for (var inc in included) {
            if (inc['type'] == 'mediaRelationships') {
              final role = inc['attributes']?['role'];
              if (['sequel', 'prequel', 'side_story', 'spin_off'].contains(role)) {
                 final destId = inc['relationships']?['destination']?['data']?['id'];
                 if (destId != null && !visited.contains(destId.toString())) {
                    visited.add(destId.toString());
                    queue.add(MapEntry(destId.toString(), depth + 1));
                 }
              }
            }
          }
        }
      } catch (e) {
        appLog('Relationship error at $currentId: $e', tag: 'Kitsu');
      }
    }

    final sorted = entryMap.values.toList();
    sorted.sort((a, b) => (a.series.year ?? 0).compareTo(b.series.year ?? 0));
    
    appLog('Found ${sorted.length} franchise installments.', tag: 'Kitsu');
    return FranchiseManifest(entries: sorted);
  }

  MediaSearchResult _parseMedia(dynamic item) {
    final attr = item['attributes'];
    
    double? parsedScore;
    if (attr['averageRating'] != null) {
      parsedScore = double.tryParse(attr['averageRating'].toString());
    }

    return MediaSearchResult(
      id: item['id'],
      providerId: id,
      title: attr['canonicalTitle'] ?? attr['titles']['en'] ?? attr['titles']['en_jp'] ?? 'Unknown',
      originalTitle: attr['titles']['ja_jp'],
      posterUrl: attr['posterImage']?['large'],
      backdropUrl: attr['coverImage']?['large'],
      overview: attr['synopsis'],
      year: attr['startDate'] != null ? DateTime.tryParse(attr['startDate'])?.year : null,
      totalEpisodes: attr['episodeCount'],
      status: attr['status'],
      averageScore: parsedScore,
      rawFormat: attr['subtype']?.toString(),
      type: _mapSubtypeToType(attr['subtype']),
    );
  }

  MediaType _mapSubtypeToType(String? subtype) {
    if (subtype == null) return MediaType.anime;
    switch (subtype.toLowerCase()) {
      case 'movie': return MediaType.movie;
      case 'special': return MediaType.ova;
      case 'ova': return MediaType.ova;
      case 'ona': return MediaType.ova;
      default: return MediaType.anime;
    }
  }

  @override
  Future<bool> authenticate() async => true;
  @override
  Future<void> logout() async {}
  @override
  Future<void> scrobble(String mediaId, int episode, double progress) async {}
}
