import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../engine/auth/anilist_service.dart';
import '../../engine/auth/mal_service.dart';
import '../../engine/auth/simkl_service.dart';
import 'developer_keys_page.dart';

class TrackerAccountsPage extends StatefulWidget {
  const TrackerAccountsPage({super.key});

  @override
  State<TrackerAccountsPage> createState() => _TrackerAccountsPageState();
}

class _TrackerAccountsPageState extends State<TrackerAccountsPage> {
  final _anilistService = AniListService();
  final _malService = MALService();
  final _simklService = SIMKLService();

  bool _isAutoScrobbleEnabled = true;
  Map<String, TrackerAccountInfo> _accounts = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAutoScrobbleEnabled = prefs.getBool('auto_scrobble_enabled') ?? true;
      _accounts = {
        'anilist': TrackerAccountInfo(
          id: 'anilist',
          name: 'AniList',
          username: prefs.getString('anilist_username'),
          avatar: prefs.getString('anilist_avatar'),
          isConnected: prefs.getBool('anilist_logged_in') ?? false,
          color: Colors.blue,
          icon: Icons.auto_awesome_motion,
        ),
        'mal': TrackerAccountInfo(
          id: 'mal',
          name: 'MyAnimeList',
          username: prefs.getString('mal_username'),
          avatar: prefs.getString('mal_avatar'),
          isConnected: prefs.getBool('mal_logged_in') ?? false,
          color: const Color(0xFF2E51A2),
          icon: Icons.list_alt,
        ),
        'simkl': TrackerAccountInfo(
          id: 'simkl',
          name: 'SIMKL',
          username: prefs.getString('simkl_username'),
          avatar: prefs.getString('simkl_avatar'),
          isConnected: prefs.getBool('simkl_logged_in') ?? false,
          color: Colors.cyan,
          icon: Icons.tv,
        ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Tracker Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Sync Settings'),
          SwitchListTile(
            title: const Text('Auto-scrobble at 85%'),
            subtitle: const Text('Sync playback progress to active trackers'),
            value: _isAutoScrobbleEnabled,
            activeThumbColor: Colors.redAccent,
            onChanged: (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('auto_scrobble_enabled', v);
              setState(() => _isAutoScrobbleEnabled = v);
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Trackers'),
          ..._accounts.values.map((acc) => _buildTrackerCard(acc)).toList(),
          const SizedBox(height: 32),
          _buildAdvancedSettings(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _buildTrackerCard(TrackerAccountInfo acc) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: acc.isConnected ? BorderSide(color: acc.color.withValues(alpha: 0.3)) : BorderSide.none),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: acc.color.withValues(alpha: 0.1), child: Icon(acc.icon, color: acc.color, size: 20)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(acc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(acc.isConnected ? 'Connected as @${acc.username}' : 'Disconnected', style: TextStyle(color: acc.isConnected ? Colors.green : Colors.white24, fontSize: 11)),
                    ],
                  ),
                ),
                if (!acc.isConnected)
                  ElevatedButton(
                    onPressed: () => _showLoginOptions(acc.id),
                    style: ElevatedButton.styleFrom(backgroundColor: acc.color.withValues(alpha: 0.2), foregroundColor: acc.color, elevation: 0),
                    child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.logout, size: 18, color: Colors.white38),
                    onPressed: () => _handleLogout(acc.id),
                  ),
              ],
            ),
            if (acc.isConnected && acc.avatar != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(acc.avatar!, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.person, size: 20)),
                  ),
                  const SizedBox(width: 12),
                  const Text('Sync is Active', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLoginOptions(String id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_browser, color: Colors.redAccent),
              title: const Text('Login via Browser'),
              onTap: () {
                Navigator.pop(context);
                if (id == 'anilist') _anilistService.login();
                if (id == 'mal') _malService.login();
                if (id == 'simkl') _simklService.login();
              },
            ),
            ListTile(
              leading: const Icon(Icons.paste, color: Colors.white70),
              title: const Text('Paste Access Token / Code'),
              onTap: () {
                Navigator.pop(context);
                _showTokenInputDialog(id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenInputDialog(String id) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Connect to ${id.toUpperCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(id == 'anilist' ? 'Paste your Personal Access Token:' : 'Paste the "code" from the URL after login:', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(filled: true, fillColor: Colors.black26, hintText: 'Token / Code...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final val = controller.text.trim();
              if (val.isEmpty) return;
              Navigator.pop(ctx);
              bool success = false;
              if (id == 'anilist') success = await _anilistService.verifyAndSaveToken(val);
              if (id == 'mal') success = await _malService.handleAuthCode(val);
              if (id == 'simkl') success = await _simklService.handleAuthCode(val);
              
              if (success) {
                if (mounted) {
                   _loadSettings();
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$id connected!')));
                }
              } else {
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to connect $id. Check your token.')));
                }
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(String id) async {
    if (id == 'anilist') await _anilistService.logout();
    if (id == 'mal') await _malService.logout();
    if (id == 'simkl') await _simklService.logout();
    _loadSettings();
  }

  Widget _buildAdvancedSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Advanced Settings'),
        ListTile(
          title: const Text('Custom API Configuration'),
          subtitle: const Text('Provide your own Client IDs and Secrets'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperKeysPage()));
          },
        ),
      ],
    );
  }
}

class TrackerAccountInfo {
  final String id;
  final String name;
  final String? username;
  final String? avatar;
  final bool isConnected;
  final Color color;
  final IconData icon;

  TrackerAccountInfo({
    required this.id,
    required this.name,
    this.username,
    this.avatar,
    required this.isConnected,
    required this.color,
    required this.icon,
  });
}
