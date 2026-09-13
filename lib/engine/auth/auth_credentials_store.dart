import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthCredentialsStore {
  static final AuthCredentialsStore instance = AuthCredentialsStore._();
  AuthCredentialsStore._();

  final _secureStorage = const FlutterSecureStorage();

  // Non-sensitive keys (Client IDs) are kept in SharedPreferences for easy access
  // Sensitive keys (Client Secrets) are kept in Secure Storage

  Future<void> setAnilistClientId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anilist_client_id', id);
  }

  Future<String?> getAnilistClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('anilist_client_id');
  }

  Future<void> setMALCredentials(String clientId, String? clientSecret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mal_client_id', clientId);
    if (clientSecret != null) {
      await _secureStorage.write(key: 'mal_client_secret', value: clientSecret);
    }
  }

  Future<String?> getMALClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mal_client_id');
  }

  Future<String?> getMALClientSecret() async {
    return await _secureStorage.read(key: 'mal_client_secret');
  }

  Future<void> setSimklCredentials(String clientId, String? clientSecret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('simkl_client_id', clientId);
    if (clientSecret != null) {
      await _secureStorage.write(key: 'simkl_client_secret', value: clientSecret);
    }
  }

  Future<String?> getSimklClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('simkl_client_id');
  }

  Future<String?> getSimklClientSecret() async {
    return await _secureStorage.read(key: 'simkl_client_secret');
  }

  Future<void> setTmdbApiKey(String apiKey) async {
    await _secureStorage.write(key: 'tmdb_api_key', value: apiKey);
  }

  Future<String?> getTmdbApiKey() async {
    return await _secureStorage.read(key: 'tmdb_api_key');
  }
}
