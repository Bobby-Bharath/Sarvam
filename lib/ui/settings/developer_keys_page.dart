import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../engine/auth/auth_credentials_store.dart';

class DeveloperKeysPage extends StatefulWidget {
  const DeveloperKeysPage({super.key});

  @override
  State<DeveloperKeysPage> createState() => _DeveloperKeysPageState();
}

class _DeveloperKeysPageState extends State<DeveloperKeysPage> {
  final _anilistIdController = TextEditingController();
  final _malIdController = TextEditingController();
  final _malSecretController = TextEditingController();
  final _simklIdController = TextEditingController();
  final _simklSecretController = TextEditingController();
  final _tmdbKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final store = AuthCredentialsStore.instance;
    _anilistIdController.text = await store.getAnilistClientId() ?? "";
    _malIdController.text = await store.getMALClientId() ?? "";
    _malSecretController.text = await store.getMALClientSecret() ?? "";
    _simklIdController.text = await store.getSimklClientId() ?? "";
    _simklSecretController.text = await store.getSimklClientSecret() ?? "";
    _tmdbKeyController.text = await store.getTmdbApiKey() ?? "";
  }

  Future<void> _saveAll() async {
    final store = AuthCredentialsStore.instance;
    await store.setAnilistClientId(_anilistIdController.text.trim());
    await store.setMALCredentials(_malIdController.text.trim(), _malSecretController.text.trim());
    await store.setSimklCredentials(_simklIdController.text.trim(), _simklSecretController.text.trim());
    await store.setTmdbApiKey(_tmdbKeyController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Keys saved successfully!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('API Keys & App Registration', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.save, color: Colors.redAccent), onPressed: _saveAll),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Use these settings to provide your own developer credentials if the default ones are blocked or restricted.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),
          
          _buildKeySection(
            title: 'AniList',
            buttonLabel: 'Create App on AniList',
            url: 'https://anilist.co/settings/developer',
            fields: [
              _KeyField(label: 'Client ID', controller: _anilistIdController),
            ],
          ),

          _buildKeySection(
            title: 'MyAnimeList',
            buttonLabel: 'Create App on MAL',
            url: 'https://myanimelist.net/apiconfig',
            fields: [
              _KeyField(label: 'Client ID', controller: _malIdController),
              _KeyField(label: 'Client Secret (Optional for PKCE)', controller: _malSecretController),
            ],
          ),

          _buildKeySection(
            title: 'SIMKL',
            buttonLabel: 'Create App on SIMKL',
            url: 'https://simkl.com/settings/developer/new',
            fields: [
              _KeyField(label: 'Client ID', controller: _simklIdController),
              _KeyField(label: 'Client Secret', controller: _simklSecretController),
            ],
          ),

          _buildKeySection(
            title: 'TMDB',
            buttonLabel: 'Get TMDB API Key',
            url: 'https://www.themoviedb.org/settings/api',
            fields: [
              _KeyField(label: 'API Key (v3) / Access Token (v4)', controller: _tmdbKeyController),
            ],
          ),
          
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildKeySection({required String title, required String buttonLabel, required String url, required List<_KeyField> fields}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(buttonLabel, style: const TextStyle(fontSize: 11)),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...fields.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: f.controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: f.label,
              labelStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        )).toList(),
        const Divider(height: 32, color: Colors.white10),
      ],
    );
  }
}

class _KeyField {
  final String label;
  final TextEditingController controller;
  _KeyField({required this.label, required this.controller});
}
