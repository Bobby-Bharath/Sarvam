import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_credentials_store.dart';

class SIMKLService {
  static const String fallbackClientId = "2e9e4a59b3053e770f2b5c2154bb8321386b2271826c2d2fe8f5f22268722b4b";
  final _secureStorage = const FlutterSecureStorage();

  Future<void> login() async {
    final clientId = await AuthCredentialsStore.instance.getSimklClientId() ?? fallbackClientId;
    
    // Simkl requires app-name and app-version
    final url = Uri.parse(
        'https://simkl.com/oauth/authorize?response_type=code&client_id=$clientId&redirect_uri=omni://callback&app-name=omnihub&app-version=1.0');
    
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch SIMKL login URL');
    }
  }

  Future<bool> handleAuthCode(String code) async {
    final clientId = await AuthCredentialsStore.instance.getSimklClientId() ?? fallbackClientId;
    final clientSecret = await AuthCredentialsStore.instance.getSimklClientSecret() ?? "";

    try {
      final response = await http.post(
        Uri.parse('https://api.simkl.com/oauth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'client_id': clientId,
          'client_secret': clientSecret,
          'redirect_uri': 'omni://callback',
          'grant_type': 'authorization_code'
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['access_token'] != null) {
          await _secureStorage.write(key: 'simkl_token', value: data['access_token'].toString());
          return await _verifyAndSaveProfile(data['access_token'].toString(), clientId);
        }
      } else {
        debugPrint('SIMKL token exchange failed with status ${response.statusCode}: ${response.body}');
      }
    } on TimeoutException {
      debugPrint('SIMKL token exchange timed out after 10s');
    } catch (e) {
      debugPrint('SIMKL token exchange error: $e');
    }
    return false;
  }

  Future<bool> _verifyAndSaveProfile(String token, String clientId) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.simkl.com/users/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'simkl-api-key': clientId,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('simkl_username', user['name']?.toString() ?? '');
          await prefs.setString('simkl_avatar', user['avatar']?.toString() ?? '');
          await prefs.setBool('simkl_logged_in', true);
          return true;
        }
      } else {
        debugPrint('SIMKL profile verify failed with status ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('SIMKL profile verify timed out after 10s');
    } catch (e) {
      debugPrint('SIMKL profile verify error: $e');
    }
    return false;
  }

  Future<void> scrobble(int simklId, int seasonNumber, int episodeNumber) async {
    final token = await _secureStorage.read(key: 'simkl_token');
    if (token == null) return;

    final clientId = await AuthCredentialsStore.instance.getSimklClientId() ?? fallbackClientId;

    try {
      final response = await http.post(
        Uri.parse('https://api.simkl.com/sync/history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'simkl-api-key': clientId,
        },
        body: jsonEncode({
          "shows": [
            {
              "ids": {"simkl": simklId},
              "seasons": [
                {
                  "number": seasonNumber,
                  "episodes": [{"number": episodeNumber}]
                }
              ]
            }
          ]
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('SIMKL: Successfully scrobbled S$seasonNumber E$episodeNumber for ID $simklId');
      } else {
        debugPrint('SIMKL: Scrobble failed ${response.statusCode}: ${response.body}');
      }
    } on TimeoutException {
      debugPrint('SIMKL scrobble timed out after 10s for ID $simklId');
    } catch (e) {
      debugPrint('SIMKL scrobble error: $e');
    }
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'simkl_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('simkl_username');
    await prefs.remove('simkl_avatar');
    await prefs.setBool('simkl_logged_in', false);
  }
}
