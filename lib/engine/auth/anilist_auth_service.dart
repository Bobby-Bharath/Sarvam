import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AniListAuthService {
  static const String defaultClientId = "35224";
  final _secureStorage = const FlutterSecureStorage();

  Future<String> _getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('anilist_custom_client_id') ?? defaultClientId;
  }

  Future<void> startLogin() async {
    final clientId = await _getClientId();
    final url = Uri.parse(
      'https://anilist.co/api/v2/oauth/authorize?client_id=$clientId&response_type=token'
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch AniList login URL');
    }
  }

  Future<bool> verifyAndSaveToken(String token) async {
    const String query = r'''
      query {
        Viewer {
          id
          name
          avatar { large }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': query}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data']['Viewer'];
        final prefs = await SharedPreferences.getInstance();
        
        await _secureStorage.write(key: 'anilist_token', value: token);
        await prefs.setString('anilist_username', data['name']);
        await prefs.setString('anilist_avatar', data['avatar']['large']);
        await prefs.setBool('anilist_logged_in', true);
        
        return true;
      }
    } catch (e) {
      debugPrint('AniList verify error: $e');
    }
    return false;
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'anilist_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('anilist_username');
    await prefs.remove('anilist_avatar');
    await prefs.setBool('anilist_logged_in', false);
  }
}
