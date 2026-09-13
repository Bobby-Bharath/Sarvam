import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../engine/auth/anilist_service.dart';
import '../../engine/plugins/models/plugin_models.dart';
import '../../database/media_database.dart';
import '../pairing/interactive_mapping_page.dart';
import '../settings/tracker_accounts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'series_details_screen.dart';

class TrackerWatchlistPage extends StatefulWidget {
  const TrackerWatchlistPage({super.key});

  @override
  State<TrackerWatchlistPage> createState() => _TrackerWatchlistPageState();
}

class _TrackerWatchlistPageState extends State<TrackerWatchlistPage> with SingleTickerProviderStateMixin {
  final AniListService _anilist = AniListService();
  late TabController _tabController;
  Map<String, List<Map<String, dynamic>>> _lists = {};
  bool _isLoading = true;
  bool _isAniListLoggedIn = false;
  bool _isMALLoggedIn = false;
  final List<String> _categories = ['Watching', 'Planning', 'Completed', 'Paused', 'Dropped', 'All'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _checkLogins();
  }

  Future<void> _checkLogins() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAniListLoggedIn = prefs.getBool('anilist_logged_in') ?? false;
      _isMALLoggedIn = prefs.getBool('mal_logged_in') ?? false;
    });
    if (_isAniListLoggedIn) {
       _loadWatchlist();
    } else {
       setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWatchlist() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final data = await _anilist.fetchUserLists();
    if (mounted) {
      setState(() {
        _lists = data;
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _findLinkedEntity(String aniId, int? idMal, String title) async {
    final db = MediaDatabase.instance;
    // 1. Match by AniList ID
    var entity = await db.getMediaEntity('anilist_$aniId');
    if (entity != null) return entity;
    
    // 2. Match by MAL ID
    if (idMal != null) {
      final all = await db.getAllMediaEntities();
      for (var e in all) {
        if (e['id_mal'] == idMal) return e;
      }
    }
    
    // 3. Match by Title
    final all = await db.getAllMediaEntities();
    for (var e in all) {
      if (e['title'].toString().toLowerCase() == title.toLowerCase()) return e;
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.redAccent,
          labelColor: Colors.redAccent,
          unselectedLabelColor: Colors.white38,
          tabs: _categories.map((c) => Tab(text: '$c (${_lists[c]?.length ?? 0})')).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _categories.map((c) => _buildListCategory(c)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildListCategory(String category) {
    if (!_isAniListLoggedIn && !_isMALLoggedIn) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.white10),
            const SizedBox(height: 16),
            const Text('Connect a tracker to browse your watchlist.', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackerAccountsPage())).then((_) => _checkLogins()),
              child: const Text('Go to Tracker Settings'),
            ),
          ],
        ),
      );
    }

    final entries = _lists[category] ?? [];
    if (entries.isEmpty) {
      return Center(child: Text(_isLoading ? 'Loading...' : 'No items in $category', style: const TextStyle(color: Colors.white24)));
    }

    return RefreshIndicator(
      onRefresh: _loadWatchlist,
      color: Colors.redAccent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final media = entry['media'];
          return _buildMediaCard(entry, media);
        },
      ),
    );
  }

  Widget _buildMediaCard(Map<String, dynamic> entry, Map<String, dynamic> media) {
    final String title = media['title']['userPreferred'] ?? media['title']['romaji'] ?? 'Unknown';
    final int? totalEpisodes = media['episodes'];
    final int progress = entry['progress'] ?? 0;
    final double? score = entry['score']?.toDouble();
    final String aniId = media['id'].toString();
    final int? idMal = media['idMal'];

    return FutureBuilder<Map<String, dynamic>?>(
      future: _findLinkedEntity(aniId, idMal, title),
      builder: (context, snapshot) {
        final paired = snapshot.data;
        final bool isLinked = paired != null;
        final String entityId = paired?['id'] ?? 'anilist_$aniId';

        return Card(
          color: Colors.white.withValues(alpha: 0.05),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: isLinked 
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesDetailsScreen(mediaEntityId: entityId)))
              : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          media['coverImage']['large'],
                          width: 70,
                          height: 100,
                          fit: BoxFit.cover,
                          cacheWidth: 140,
                          errorBuilder: (_, __, ___) => Container(width: 70, height: 100, color: Colors.white10),
                        ),
                      ),
                      if (score != null && score > 0)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                            child: Text('⭐ ${score.toInt()}', style: const TextStyle(fontSize: 8, color: Colors.amber, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${media['startDate']['year'] ?? "?"} · $progress / ${totalEpisodes ?? "?"} eps', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(height: 8),
                        if (totalEpisodes != null && totalEpisodes > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress / totalEpisodes,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                minHeight: 3,
                              ),
                            ),
                          ),
                        if (isLinked)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 10),
                                SizedBox(width: 4),
                                Text('LINKED LOCALLY', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => _handleFolderMapping(media),
                            icon: const Icon(Icons.folder_open, size: 14),
                            label: const Text('Map Local Folder', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                              foregroundColor: Colors.redAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Future<void> _handleFolderMapping(Map<String, dynamic> media) async {
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.video);
    if (!mounted) return;

    final selectedFolder = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FolderPickerSheet(folders: albums),
    );

    if (selectedFolder != null && mounted) {
      final assets = await selectedFolder.getAssetListRange(start: 0, end: 1000);
      String? folderPath;
      if (assets.isNotEmpty) {
        final origin = await assets.first.originFile;
        folderPath = origin?.parent.path;
      }

      double? parsedScore;
      if (media['averageScore'] != null) {
        parsedScore = (media['averageScore'] as num).toDouble();
      }

      final searchResult = MediaSearchResult(
        id: media['id'].toString(),
        providerId: 'anilist',
        title: media['title']['userPreferred'] ?? media['title']['romaji'],
        posterUrl: media['coverImage']['large'],
        backdropUrl: media['bannerImage'],
        overview: media['description'],
        year: media['startDate']['year'],
        totalEpisodes: media['episodes'],
        status: media['status']?.toString().toLowerCase(),
        averageScore: parsedScore,
        idMal: media['idMal'],
        type: MediaType.anime,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InteractiveMappingPage(
              files: assets,
              media: searchResult,
              folderId: selectedFolder.id,
              folderPath: folderPath,
            ),
          ),
        ).then((_) => setState(() {}));
      }
    }
  }
}

class _FolderPickerSheet extends StatelessWidget {
  final List<AssetPathEntity> folders;
  const _FolderPickerSheet({required this.folders});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Select Folder to Map', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final f = folders[index];
                return ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber),
                  title: Text(f.name),
                  onTap: () => Navigator.pop(context, f),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
