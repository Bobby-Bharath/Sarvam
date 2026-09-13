import 'models/plugin_models.dart';

abstract class MediaPlugin {
  String get id;
  String get name;
  PluginType get supportedType;

  Future<List<MediaSearchResult>> search(String query);
  Future<List<EpisodeManifest>> fetchManifest(String mediaId);
  Future<FranchiseManifest> fetchFranchise(String mediaId);
  
  // Future methods for future tiers
  Future<bool> authenticate();
  Future<void> logout();
  Future<void> scrobble(String mediaId, int episode, double progress);
}
