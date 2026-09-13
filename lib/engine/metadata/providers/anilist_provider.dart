import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AniListSeries {
  final int id;
  final int? idMal;
  final String romajiTitle;
  final String? englishTitle;
  final String description;
  final String? posterUrl;
  final String? backdropUrl;
  final int? totalEpisodes;
  final int? year;

  AniListSeries({
    required this.id,
    this.idMal,
    required this.romajiTitle,
    this.englishTitle,
    required this.description,
    this.posterUrl,
    this.backdropUrl,
    this.totalEpisodes,
    this.year,
  });
}

class AniListProvider {
  static const String _url = 'https://graphql.anilist.co';

  static String _sanitizeQuery(String query) {
    // Strip [...] release groups
    String sanitized = query.replaceAll(RegExp(r'\[.*?\]'), '');
    // Strip S01E01 tags
    sanitized = sanitized.replaceAll(RegExp(r'[sS]\d+[eE]\d+', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'[eE]\d+', caseSensitive: false), '');
    // Strip punctuation and special chars
    sanitized = sanitized.replaceAll(RegExp(r'[^\w\s]'), ' ');
    // Collapse whitespace and trim
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return sanitized;
  }

  static Future<List<AniListSeries>> searchAnimeList(String query) async {
    final sanitizedQuery = _sanitizeQuery(query);
    debugPrint('AniList: Searching for "$sanitizedQuery" (Original: "$query")');

    const String graphqlQuery = r'''
    query ($search: String) {
      Page (page: 1, perPage: 10) {
        media (search: $search, type: ANIME) {
          id
          idMal
          title {
            romaji
            english
          }
          description
          coverImage {
            large
          }
          bannerImage
          episodes
          startDate {
            year
          }
        }
      }
    }
    ''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'OmniPlayer/1.0',
        },
        body: jsonEncode({
          'query': graphqlQuery,
          'variables': {'search': sanitizedQuery},
        }),
      );

      debugPrint('AniList: Response Status ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> list = body['data']['Page']['media'];
        return list.map((data) => AniListSeries(
          id: data['id'],
          idMal: data['idMal'],
          romajiTitle: data['title']['romaji'],
          englishTitle: data['title']['english'],
          description: data['description'] ?? '',
          posterUrl: data['coverImage']['large'],
          backdropUrl: data['bannerImage'],
          totalEpisodes: data['episodes'],
          year: data['startDate']['year'],
        )).toList();
      } else {
        debugPrint('AniList: Error Body: ${response.body}');
      }
    } catch (e) {
      debugPrint('AniList search list error: $e');
    }
    return [];
  }

  static Future<AniListSeries?> searchAnime(String query) async {
    final results = await searchAnimeList(query);
    return results.isNotEmpty ? results.first : null;
  }
}
