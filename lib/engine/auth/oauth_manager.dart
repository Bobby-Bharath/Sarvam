import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

class OAuthManager {
  static final OAuthManager instance = OAuthManager._();
  OAuthManager._();

  final _secureStorage = const FlutterSecureStorage();
  
  static const String anilistClientId = "22510";
  static const String malClientId = "226acbf293f6dabf8c2417c06dfb6662";
  static const String simklClientId = "2e9e4a59b3053e770f2b5c2154bb8321386b2271826c2d2fe8f5f22268722b4b";

  // --- PKCE Helpers ---
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(128, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  // --- General Auth Flow ---
  Future<String?> openAuthWindow(BuildContext context, {
    required String url,
    required String callbackUrl,
  }) async {
    String? resultUrl;
    
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(callbackUrl)) {
              resultUrl = request.url;
              Navigator.pop(context);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            AppBar(
              title: const Text('Login', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              leading: IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            Expanded(child: WebViewWidget(controller: controller)),
          ],
        ),
      ),
    );

    return resultUrl;
  }

  // --- AniList Flow ---
  Future<bool> loginAniList(BuildContext context) async {
    const String authUrl = "https://anilist.co/api/v2/oauth/authorize?client_id=$anilistClientId&response_type=token";
    const String callbackUrl = "https://anilist.co/api/v2/oauth/pin";

    final result = await openAuthWindow(context, url: authUrl, callbackUrl: callbackUrl);
    if (result != null) {
      final fragment = Uri.parse(result.replaceFirst('#', '?')).queryParameters;
      final token = fragment['access_token'];
      if (token != null) {
        await _secureStorage.write(key: 'anilist_token', value: token);
        return await _fetchAniListUser(token);
      }
    }
    return false;
  }

  Future<bool> _fetchAniListUser(String token) async {
    const String query = r'''
      query {
        Viewer {
          name
          avatar { medium }
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
        await prefs.setString('anilist_username', data['name']);
        await prefs.setString('anilist_avatar', data['avatar']['medium']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // --- MAL Flow ---
  Future<bool> loginMAL(BuildContext context) async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);
    
    final String authUrl = "https://myanimelist.net/v1/oauth2/authorize?response_type=code&client_id=$malClientId&code_challenge=$challenge";
    const String callbackUrl = "omni://oauth/mal";

    final result = await openAuthWindow(context, url: authUrl, callbackUrl: callbackUrl);
    if (result != null) {
      final code = Uri.parse(result).queryParameters['code'];
      if (code != null) {
        return await _exchangeMALCode(code, verifier);
      }
    }
    return false;
  }

  Future<bool> _exchangeMALCode(String code, String verifier) async {
    try {
      final response = await http.post(
        Uri.parse('https://myanimelist.net/v1/oauth2/token'),
        body: {
          'client_id': malClientId,
          'grant_type': 'authorization_code',
          'code': code,
          'code_verifier': verifier,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _secureStorage.write(key: 'mal_token', value: data['access_token']);
        await _secureStorage.write(key: 'mal_refresh_token', value: data['refresh_token']);
        return await _fetchMALUser(data['access_token']);
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _fetchMALUser(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.myanimelist.net/v2/users/@me'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('mal_username', data['name']);
        await prefs.setString('mal_avatar', data['picture']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // --- SIMKL Flow ---
  Future<bool> loginSIMKL(BuildContext context) async {
    const String authUrl = "https://simkl.com/oauth/authorize?response_type=code&client_id=$simklClientId&redirect_uri=omni://oauth/simkl";
    const String callbackUrl = "omni://oauth/simkl";

    final result = await openAuthWindow(context, url: authUrl, callbackUrl: callbackUrl);
    if (result != null) {
      final code = Uri.parse(result).queryParameters['code'];
      if (code != null) {
        return await _exchangeSIMKLCode(code);
      }
    }
    return false;
  }

  Future<bool> _exchangeSIMKLCode(String code) async {
    return true;
  }

  // --- Logout ---
  Future<void> logout(String provider) async {
    await _secureStorage.delete(key: '${provider.toLowerCase()}_token');
    await _secureStorage.delete(key: '${provider.toLowerCase()}_refresh_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${provider.toLowerCase()}_username');
    await prefs.remove('${provider.toLowerCase()}_avatar');
  }

  Future<String?> getToken(String provider) async {
    return await _secureStorage.read(key: '${provider.toLowerCase()}_token');
  }
}
