import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MALAuthService {
  static const String defaultClientId = "YOUR_MAL_CLIENT_ID"; // Replace with your real ID
  final _secureStorage = const FlutterSecureStorage();

  String _generateCodeVerifier() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(128, (i) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> startLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('mal_custom_client_id') ?? defaultClientId;
    
    final verifier = _generateCodeVerifier();
    await _secureStorage.write(key: 'mal_temp_verifier', value: verifier);

    // MAL uses plain PKCE: challenge == verifier
    final url = Uri.parse(
      'https://myanimelist.net/v1/oauth2/authorize?response_type=code&client_id=$clientId&code_challenge=$verifier&code_challenge_method=plain'
    );

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch MAL login URL');
    }
  }

  Future<bool> handleAuthCode(String authCode) async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('mal_custom_client_id') ?? defaultClientId;
    final verifier = await _secureStorage.read(key: 'mal_temp_verifier');

    if (verifier == null) return false;

    try {
      final response = await http.post(
        Uri.parse('https://myanimelist.net/v1/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': authCode,
          'code_verifier': verifier,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'];
        final refreshToken = data['refresh_token'];

        await _secureStorage.write(key: 'mal_token', value: accessToken);
        await _secureStorage.write(key: 'mal_refresh_token', value: refreshToken);
        
        return await _verifyAndSaveProfile(accessToken);
      }
    } catch (e) {
      debugPrint('MAL token exchange error: $e');
    }
    return false;
  }

  Future<bool> _verifyAndSaveProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.myanimelist.net/v2/users/@me?fields=anime_statistics'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        
        await prefs.setString('mal_username', data['name']);
        await prefs.setString('mal_avatar', data['picture']);
        await prefs.setBool('mal_logged_in', true);
        
        return true;
      }
    } catch (e) {
      debugPrint('MAL profile verify error: $e');
    }
    return false;
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'mal_token');
    await _secureStorage.delete(key: 'mal_refresh_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mal_username');
    await prefs.remove('mal_avatar');
    await prefs.setBool('mal_logged_in', false);
  }
}
