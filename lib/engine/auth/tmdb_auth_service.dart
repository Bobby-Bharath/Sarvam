import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TMDBAuthService {
  final _secureStorage = const FlutterSecureStorage();

  Future<bool> verifyAndSaveToken(String token) async {
    // Validate by calling v3 authentication/test or fetching account details
    // Here we use v4 Access Token as standard for Read/Write
    try {
      final response = await http.get(
        Uri.parse('https://api.themoviedb.org/3/account'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        
        await _secureStorage.write(key: 'tmdb_token', value: token);
        await prefs.setString('tmdb_username', data['username']);
        await prefs.setBool('tmdb_logged_in', true);
        
        return true;
      }
    } catch (e) {
      debugPrint('TMDB verify error: $e');
    }
    return false;
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'tmdb_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tmdb_username');
    await prefs.setBool('tmdb_logged_in', false);
  }
}
