import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'media_plugin.dart';
import 'models/plugin_models.dart';
import '../auth/auth_credentials_store.dart';
import '../../utils/logger.dart';

class SimklPlugin implements MediaPlugin {
  @override
  String get id => 'simkl';
  @override
  String get name => 'Simkl';
  @override
  PluginType get supportedType => PluginType.anime;

  static const String _baseUrl = 'https://api.simkl.com';

  Future<String?> _getClientId() async {
    return await AuthCredentialsStore.instance.getSimklClientId();
  }

  @override
  Future<List<MediaSearchResult>> search(String query) async {
    final clientId = await _getClientId();
    if (clientId == null) return [];

    final cleanQuery = query.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    final url = Uri.parse('$_baseUrl/search/anime?q=${Uri.encodeComponent(cleanQuery)}&client_id=$clientId&extended=full');

    appLog('Searching Simkl for: "$cleanQuery"', tag: 'Simkl');

    try {
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        return list.map((item) => _parseMedia(item)).toList();
      }
    } catch (e) {
      appLog('Simkl Search error: $e', tag: 'Simkl');
    }
    return [];
  }

  @override
  Future<List<EpisodeManifest>> fetchManifest(String mediaId) async {
    return [];
  }

  @override
  Future<FranchiseManifest> fetchFranchise(String id) async {
    final clientId = await _getClientId();
    if (clientId == null) return FranchiseManifest(entries: []);

    Map<String, SeriesManifest> entryMap = {};
    String simklId = id;

    final bool isMalId = id.length > 4 && int.tryParse(id) != null && int.parse(id) > 40000;
    if (isMalId) {
      final bridgeUrl = Uri.parse('$_baseUrl/search/id?mal=$id&client_id=$clientId');
      try {
        final res = await http.get(bridgeUrl).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final List<dynamic> list = jsonDecode(res.body);
          if (list.isNotEmpty) {
            simklId = list.first['ids']['simkl'].toString();
          }
        }
      } catch (_) {}
    }

    appLog('Fetching Simkl details & relations for $simklId...', tag: 'Simkl');
    final url = Uri.parse('$_baseUrl/anime/$simklId?extended=full&client_id=$clientId');
    
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final root = _parseMedia(data);
        entryMap[root.id] = SeriesManifest(series: root, episodes: []);

        final List<dynamic> relations = data['relations'] ?? [];
        for (var rel in relations) {
           final media = _parseMedia(rel);
           if (!entryMap.containsKey(media.id)) {
              entryMap[media.id] = SeriesManifest(series: media, episodes: []);
           }
        }
      }
    } catch (e) {
      appLog('Simkl Franchise error: $e', tag: 'Simkl');
    }

    final sorted = entryMap.values.toList();
    sorted.sort((a, b) => (a.series.year ?? 0).compareTo(b.series.year ?? 0));
    return FranchiseManifest(entries: sorted);
  }

  MediaSearchResult _parseMedia(dynamic item) {
    final ids = item['ids'] ?? {};
    final String sid = ids['simkl']?.toString() ?? item['simkl_id']?.toString() ?? '0';
    
    double? score;
    if (item['ratings']?['mal']?['rating'] != null) {
      score = double.tryParse(item['ratings']['mal']['rating'].toString());
    }

    return MediaSearchResult(
      id: sid,
      providerId: id,
      title: item['title'] ?? 'Unknown',
      posterUrl: item['poster'] != null ? 'https://simkl.in/posters/${item['poster']}_m.jpg' : null,
      overview: item['overview'],
      year: item['year'] is int ? item['year'] : int.tryParse(item['year']?.toString() ?? ''),
      totalEpisodes: item['total_episodes'] is int ? item['total_episodes'] : int.tryParse(item['total_episodes']?.toString() ?? ''),
      status: item['status']?.toString().toLowerCase(),
      averageScore: score,
      idMal: ids['mal'] is int ? ids['mal'] : int.tryParse(ids['mal']?.toString() ?? ''),
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
