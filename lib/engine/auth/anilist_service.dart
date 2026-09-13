// lib/engine/auth/anilist_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AniListService {
  static const String _graphqlEndpoint = 'https://graphql.anilist.co';

  // Standard public Client ID for desktop/mobile clients; override if using custom keys
  static const String clientId = '18966';

  // --- TOKEN SANITIZER ---
  static final RegExp _releaseTagsRegex = RegExp(
    r'(\[.*?\]|\(.*?\)|(?:\b(?:1080p|720p|480p|2160p|4k|uhd|hevc|x264|x265|av1|aac|flac|opus|web-dl|bluray|bdrip|remux|dual[-\s]audio)\b)|S\d{1,2}(?:E\d{1,3})?|E\d{1,3}|-\s*\d{1,3})',
    caseSensitive: false,
  );
  static final RegExp _cleanWhitespaceRegex = RegExp(r'[\._\s\-]+');

  static String sanitizeSearchQuery(String rawTitle) {
    String cleaned = rawTitle.replaceAll(_releaseTagsRegex, ' ');
    cleaned = cleaned.replaceAll(_cleanWhitespaceRegex, ' ').trim();
    return cleaned.isEmpty ? rawTitle.trim() : cleaned;
  }

  // --- AUTH LIFECYCLE ---

  /// Launches the AniList OAuth2 implicit grant page in the external browser.
  Future<void> login() async {
    final authUrl = Uri.parse(
      'https://anilist.co/api/v2/oauth/authorize?client_id=$clientId&response_type=token',
    );
    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not launch AniList OAuth URL');
    }
  }

  /// Verifies token validity by fetching viewer profile, then saves credentials to SharedPreferences.
  Future<bool> verifyAndSaveToken(String token) async {
    const viewerQuery = r'''
      query {
        Viewer {
          id
          name
          avatar {
            large
          }
        }
      }
    ''';

    try {
      final res = await http.post(
        Uri.parse(_graphqlEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': viewerQuery}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final viewer = data['data']?['Viewer'];
        if (viewer != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('anilist_access_token', token);
          await prefs.setInt('anilist_user_id', viewer['id'] as int);
          await prefs.setString('anilist_username', viewer['name'] as String);
          await prefs.setString('anilist_avatar', viewer['avatar']?['large'] ?? '');
          await prefs.setBool('anilist_logged_in', true);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Logs out and purges stored credentials.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('anilist_access_token');
    await prefs.remove('anilist_user_id');
    await prefs.remove('anilist_username');
    await prefs.remove('anilist_avatar');
    await prefs.setBool('anilist_logged_in', false);
  }

  Future<String?> _getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('anilist_access_token');
  }

  Future<int?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('anilist_user_id');
  }

  // --- QUERY METHODS ---

  /// Searches AniList with automatic regex title sanitation.
  Future<List<Map<String, dynamic>>> search(String title, {int page = 1, int perPage = 10}) async {
    final clean = sanitizeSearchQuery(title);
    if (clean.isEmpty) return [];

    const searchQuery = r'''
      query SearchAnime($search: String, $page: Int, $perPage: Int) {
        Page(page: $page, perPage: $perPage) {
          media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { large medium }
            bannerImage
            format
            episodes
            status
            averageScore
            startDate { year month day }
            description(asHtml: false)
          }
        }
      }
    ''';

    final response = await http.post(
      Uri.parse(_graphqlEndpoint),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'query': searchQuery,
        'variables': {'search': clean, 'page': page, 'perPage': perPage},
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic>? mediaList = data['data']?['Page']?['media'];
      if (mediaList == null) return [];
      return mediaList.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return [];
  }

  /// Fetches an individual user list entry for an anime title.
  Future<Map<String, dynamic>?> fetchEntry(int mediaId) async {
    final token = await _getAccessToken();
    final userId = await _getUserId();
    if (token == null || userId == null) return null;

    const entryQuery = r'''
      query GetMediaEntry($userId: Int, $mediaId: Int) {
        MediaList(userId: $userId, mediaId: $mediaId) {
          id
          mediaId
          status
          score
          progress
          repeat
          updatedAt
        }
      }
    ''';

    final res = await http.post(
      Uri.parse(_graphqlEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'query': entryQuery,
        'variables': {'userId': userId, 'mediaId': mediaId},
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['data']?['MediaList'] as Map<String, dynamic>?;
    }
    return null;
  }

  /// Required by `tracker_watchlist_page.dart`.
  Future<Map<String, List<Map<String, dynamic>>>> fetchUserLists() async {
    final userId = await _getUserId();
    final token = await _getAccessToken();

    const userListsQuery = r'''
      query GetUserAnimeList($userId: Int) {
        MediaListCollection(userId: $userId, type: ANIME) {
          lists {
            name
            isCustomList
            status
            entries {
              id
              mediaId
              status
              score
              progress
              repeat
              updatedAt
              media {
                id
                idMal
                title { romaji english native userPreferred }
                coverImage { large medium }
                bannerImage
                episodes
                format
                status
                averageScore
                startDate { year month day }
                description(asHtml: false)
              }
            }
          }
        }
      }
    ''';

    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final response = await http.post(
      Uri.parse(_graphqlEndpoint),
      headers: headers,
      body: jsonEncode({
        'query': userListsQuery,
        'variables': {'userId': userId},
      }),
    );

    final Map<String, List<Map<String, dynamic>>> grouped = {
      'Watching': [],
      'Planning': [],
      'Completed': [],
      'Paused': [],
      'Dropped': [],
      'All': [],
    };

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic>? lists = data['data']?['MediaListCollection']?['lists'];
      if (lists == null) return grouped;

      for (var list in lists) {
        final List<dynamic>? entries = list['entries'];
        if (entries == null) continue;

        for (var rawEntry in entries) {
          final entry = Map<String, dynamic>.from(rawEntry);
          final status = entry['status']?.toString().toUpperCase();

          switch (status) {
            case 'CURRENT':
              grouped['Watching']!.add(entry);
              break;
            case 'PLANNING':
              grouped['Planning']!.add(entry);
              break;
            case 'COMPLETED':
              grouped['Completed']!.add(entry);
              break;
            case 'PAUSED':
              grouped['Paused']!.add(entry);
              break;
            case 'DROPPED':
              grouped['Dropped']!.add(entry);
              break;
          }
          grouped['All']!.add(entry);
        }
      }
    }
    return grouped;
  }

  // --- MUTATION METHODS ---

  /// Required by `sync_dispatcher.dart` scrobble loop.
  /// Accepts both positional arguments: scrobble(mediaId, episodeNumber, progressPercent)
  /// or optional progressPercent
  Future<bool> scrobble(
      int mediaId,
      int episodeNumber, [
        double? progressPercent,
      ]) async {
    final String status = (progressPercent != null && progressPercent >= 0.85)
        ? 'COMPLETED'
        : 'CURRENT';

    return updateEntryProgress(
      mediaId: mediaId,
      episodeProgress: episodeNumber,
      status: status,
    );
  }

  /// Required by `tracker_bottom_sheet.dart` manual updates.
  Future<bool> updateEntry({
    required int mediaId,
    required int progress,
    double? score,
    String? status,
  }) async {
    return updateEntryProgress(
      mediaId: mediaId,
      episodeProgress: progress,
      score: score,
      status: status,
    );
  }

  /// Unified mutation execution for saving anime entries.
  Future<bool> updateEntryProgress({
    required int mediaId,
    required int episodeProgress,
    String? status,
    double? score,
  }) async {
    final token = await _getAccessToken();
    if (token == null || token.isEmpty) return false;

    const mutation = r'''
      mutation UpdateMediaList($mediaId: Int, $progress: Int, $status: MediaListStatus, $score: Float) {
        SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status, score: $score) {
          id
          progress
          status
          score
        }
      }
    ''';

    final res = await http.post(
      Uri.parse(_graphqlEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'query': mutation,
        'variables': {
          'mediaId': mediaId,
          'progress': episodeProgress,
          if (status != null) 'status': status,
          if (score != null) 'score': score,
        },
      }),
    );

    return res.statusCode == 200;
  }

  // --- PLAYER X-RAY CAST ---

  /// Netflix / Prime-style Player X-Ray Cast Tray.
  Future<List<Map<String, dynamic>>> fetchCastForXRay(int anilistId) async {
    const castXRayQuery = r'''
      query GetCastXRay($id: Int, $perPage: Int) {
        Media(id: $id, type: ANIME) {
          characters(sort: [ROLE, RELEVANCE], perPage: $perPage) {
            edges {
              role
              node {
                id
                name { full native userPreferred }
                image { medium large }
              }
              voiceActors(language: JAPANESE) {
                id
                name { full native }
                image { medium large }
              }
            }
          }
        }
      }
    ''';

    final res = await http.post(
      Uri.parse(_graphqlEndpoint),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'query': castXRayQuery,
        'variables': {'id': anilistId, 'perPage': 25},
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final List<dynamic>? edges = data['data']?['Media']?['characters']?['edges'];
      if (edges == null) return [];

      return edges.map((e) {
        final char = e['node'];
        final vaList = e['voiceActors'] as List<dynamic>?;
        final va = (vaList != null && vaList.isNotEmpty) ? vaList.first : null;

        return {
          'role': e['role'],
          'character_name': char?['name']?['userPreferred'] ?? char?['name']?['full'] ?? 'Unknown',
          'character_image': char?['image']?['large'] ?? char?['image']?['medium'],
          'va_name': va?['name']?['full'] ?? va?['name']?['native'],
          'va_image': va?['image']?['large'] ?? va?['image']?['medium'],
        };
      }).toList();
    }
    return [];
  }
}