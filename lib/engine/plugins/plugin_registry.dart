import 'package:shared_preferences/shared_preferences.dart';
import 'media_plugin.dart';
import 'kitsu_plugin.dart';
import 'anilist_plugin.dart';
import 'mal_plugin.dart';
import 'simkl_plugin.dart';
import 'models/plugin_models.dart';

class PluginRegistry {
  static final PluginRegistry instance = PluginRegistry._internal();
  PluginRegistry._internal();

  final Map<String, MediaPlugin> _plugins = {
    'kitsu': KitsuPlugin(),
    'anilist': AniListPlugin(),
    'mal': MALPlugin(),
    'simkl': SimklPlugin(),
  };

  String _primaryProvider = 'kitsu';
  Set<String> _enabledPlugins = {'kitsu', 'anilist', 'mal', 'simkl'};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _primaryProvider = prefs.getString('primary_metadata_provider') ?? 'kitsu';
    _enabledPlugins = (prefs.getStringList('enabled_plugins') ?? ['kitsu', 'anilist', 'mal', 'simkl']).toSet();
  }

  List<MediaPlugin> get availablePlugins => _plugins.values.toList();
  
  bool isEnabled(String id) => _enabledPlugins.contains(id);
  bool isPrimary(String id) => _primaryProvider == id;

  Future<void> togglePlugin(String id, bool enabled) async {
    if (enabled) {
      _enabledPlugins.add(id);
    } else {
      if (_primaryProvider == id) return; // Can't disable primary
      _enabledPlugins.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('enabled_plugins', _enabledPlugins.toList());
  }

  Future<void> setPrimary(String id) async {
    if (!_plugins.containsKey(id)) return;
    _primaryProvider = id;
    _enabledPlugins.add(id); // Ensure primary is enabled
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('primary_metadata_provider', id);
    await prefs.setStringList('enabled_plugins', _enabledPlugins.toList());
  }

  Future<List<MediaSearchResult>> searchUnified(String query, {bool isManualSearch = false}) async {
    // 1. Try primary
    final primary = _plugins[_primaryProvider];
    if (primary != null && _enabledPlugins.contains(primary.id)) {
      final results = await primary.search(query, isManualSearch: isManualSearch);
      if (results.isNotEmpty) return results;
    }

    // 2. Fallback to others
    for (var plugin in _plugins.values) {
      if (plugin.id == _primaryProvider || !_enabledPlugins.contains(plugin.id)) continue;
      final results = await plugin.search(query, isManualSearch: isManualSearch);
      if (results.isNotEmpty) return results;
    }

    return [];
  }

  MediaPlugin? getPlugin(String id) => _plugins[id];
}
