import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_credentials_store.dart';

class MALService {
  static const String fallbackClientId = "YOUR_DEFAULT_MAL_CLIENT_ID";
  final _secureStorage = const FlutterSecureStorage();

  String _generateCodeVerifier() {
    final secureRandom = Random.secure();
    final codeVerifierBytes = List<int>.generate(96, (_) => secureRandom.nextInt(256));
    return base64UrlEncode(codeVerifierBytes)
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
  }

  Future<void> login() async {
    final clientId = await AuthCredentialsStore.instance.getMALClientId() ?? fallbackClientId;
    
    final codeVerifier = _generateCodeVerifier();
    await _secureStorage.write(key: 'mal_code_verifier', value: codeVerifier);

    final url = Uri.parse(
        'https://myanimelist.net/v1/oauth2/authorize?response_type=code&client_id=$clientId&code_challenge=$codeVerifier&code_challenge_method=plain');
    
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch MAL login URL');
    }
  }

  Future<bool> handleAuthCode(String code) async {
    final clientId = await AuthCredentialsStore.instance.getMALClientId() ?? fallbackClientId;
    final clientSecret = await AuthCredentialsStore.instance.getMALClientSecret() ?? "";
    final codeVerifier = await _secureStorage.read(key: 'mal_code_verifier');

    if (codeVerifier == null) return false;

    try {
      final response = await http.post(
        Uri.parse('https://myanimelist.net/v1/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'OmniPlayer/1.0',
        },
        body: {
          'client_id': clientId,
          'code': code,
          'code_verifier': codeVerifier,
          'grant_type': 'authorization_code',
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _secureStorage.write(key: 'mal_token', value: data['access_token']);
        await _secureStorage.write(key: 'mal_refresh_token', value: data['refresh_token']);
        
        return await _verifyAndSaveProfile(data['access_token']);
      }
    } on TimeoutException {
       debugPrint('MAL: Token exchange timed out.');
    } catch (e) {
      debugPrint('MAL token exchange error: $e');
    }
    return false;
  }

  Future<bool> _verifyAndSaveProfile(String token) async {
    final clientId = await AuthCredentialsStore.instance.getMALClientId() ?? fallbackClientId;
    try {
      final response = await http.get(
        Uri.parse('https://api.myanimelist.net/v2/users/@me'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-MAL-CLIENT-ID': clientId,
          'User-Agent': 'OmniPlayer/1.0',
        },
      ).timeout(const Duration(seconds: 10));

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

  Future<void> scrobble(int malId, int progress, {bool isCompleted = false}) async {
    final token = await _secureStorage.read(key: 'mal_token');
    final clientId = await AuthCredentialsStore.instance.getMALClientId() ?? fallbackClientId;
    if (token == null) return;

    final status = isCompleted ? 'completed' : 'watching';

    try {
      final response = await http.put(
        Uri.parse('https://api.myanimelist.net/v2/anime/$malId/my_list_status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-MAL-CLIENT-ID': clientId,
          'User-Agent': 'OmniPlayer/1.0',
        },
        body: {
          'num_watched_episodes': '$progress',
          'status': status,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('MAL: Successfully scrobbled EP $progress for ID $malId');
      }
    } catch (e) {
      debugPrint('MAL scrobble error: $e');
    }
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'mal_token');
    await _secureStorage.delete(key: 'mal_refresh_token');
    await _secureStorage.delete(key: 'mal_code_verifier');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mal_username');
    await prefs.remove('mal_avatar');
    await prefs.setBool('mal_logged_in', false);
  }
}
