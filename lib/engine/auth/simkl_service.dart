import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_credentials_store.dart';

class SIMKLService {
  static const String fallbackClientId = "YOUR_DEFAULT_SIMKL_CLIENT_ID";
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
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _secureStorage.write(key: 'simkl_token', value: data['access_token']);
        return await _verifyAndSaveProfile(data['access_token'], clientId);
      }
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
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('simkl_username', user['name']);
        await prefs.setString('simkl_avatar', user['avatar']);
        await prefs.setBool('simkl_logged_in', true);
        return true;
      }
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
      );

      if (response.statusCode == 200) {
        debugPrint('SIMKL: Successfully scrobbled S$seasonNumber E$episodeNumber for ID $simklId');
      } else {
        debugPrint('SIMKL: Scrobble failed ${response.body}');
      }
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
