import 'dart:io';
import 'package:flutter/material.dart';
import '../../database/media_database.dart';
import '../../player/player_screen.dart';
import '../pairing/manual_matcher_dialog.dart';
import '../../engine/metadata/jikan_service.dart';
import '../../engine/sync/sync_dispatcher.dart';
import 'widgets/tracker_bottom_sheet.dart';
import '../browser/local_folder_browser_page.dart';
import '../../utils/logger.dart';

class SeriesDetailsScreen extends StatefulWidget {
  final String mediaEntityId;

  const SeriesDetailsScreen({super.key, required this.mediaEntityId});

  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _franchiseEntities = [];
  final Map<String, List<Map<String, dynamic>>> _episodesByEntity = {};
  final Map<String, String> _localFileMap = {}; 
  bool _isLoading = true;
  int _selectedTabIndex = 0;
  TabController? _tabController;
  bool _isDescriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    MediaDatabase.instance.addListener(_loadData);
  }

  @override
  void dispose() {
    MediaDatabase.instance.removeListener(_loadData);
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController != null && !_tabController!.indexIsChanging && _tabController!.index != _selectedTabIndex) {
      setState(() {
        _selectedTabIndex = _tabController!.index;
      });
      _ensureAndLoadFillers();
    }
  }

  Future<void> _loadData() async {
    final db = MediaDatabase.instance;
    final target = await db.getMediaEntity(widget.mediaEntityId);
    if (target == null) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isLoading = false);
        });
      }
      return;
    }

    final franchiseId = target['franchise_id'] ?? target['title'];
    final entities = await db.getFranchiseEntities(franchiseId);
    
    final Map<String, List<Map<String, dynamic>>> episodesMap = {};
    final Map<String, String> fileMap = {};

    for (var entity in entities) {
      final eps = await db.getEpisodesForEntity(entity['id']);
      episodesMap[entity['id']] = eps;

      final localFiles = await db.getLocalFilesForEntity(entity['id']);
      for (var f in localFiles) {
        if (f['episode_id'] != null) {
          fileMap[f['episode_id']] = f['file_path'];
        }
      }
    }

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _franchiseEntities = entities;
            _episodesByEntity.clear();
            _episodesByEntity.addAll(episodesMap);
            _localFileMap.clear();
            _localFileMap.addAll(fileMap);
            
            final initialIdx = entities.indexWhere((e) => e['id'] == widget.mediaEntityId);
            final previousIndex = _tabController?.index ?? (initialIdx >= 0 ? initialIdx : 0);
            
            _tabController?.removeListener(_handleTabChange);
            _tabController?.dispose();
            _tabController = TabController(
              length: entities.length, 
              vsync: this,
              initialIndex: previousIndex.clamp(0, (entities.length - 1).clamp(0, 999)),
            );
            _tabController!.addListener(_handleTabChange);
            _selectedTabIndex = _tabController!.index;
            _isLoading = false;
          });
          // Trigger filler audit now that data is ready
          _ensureAndLoadFillers();
        }
      });
    }
  }

  Future<void> _ensureAndLoadFillers() async {
    if (_franchiseEntities.isEmpty) return;
    final active = _franchiseEntities[_selectedTabIndex];
    int? malId = active['id_mal'];

    // 1. Direct match for Bleach to avoid rate-limited web searches
    if ((malId == null || malId == 0) && active['title'].toString().toLowerCase().contains('bleach')) {
      malId = 244;
    }

    // 2. Kitsu / AniList ID resolution fallback
    if (malId == null || malId == 0) {
      appLog('Missing MAL ID for "${active['title']}". Checking ID resolvers...', tag: 'SeriesDetails');
      if (active['id'].toString().startsWith('anilist_')) {
        final aniId = int.tryParse(active['id'].toString().split('_').last);
        if (aniId != null) malId = await JikanService.resolveMalIdFromAnilist(aniId);
      } else {
        final kitsuId = active['id'].toString().split('_').last;
        malId = await JikanService.resolveMalIdFromKitsu(kitsuId);
      }
    }

    // 3. Search only if ID mapping is unavailable
    if (malId == null || malId == 0) {
      malId = await JikanService.resolveMalIdBySearch(active['title'], active['year']);
    }

    if (malId != null && malId > 0) {
      await JikanService.persistFillersToDb(active['id'], malId);

      // Reload the episodes directly from SQLite so the cards pick up is_filler = 1
      final refreshedEps = await MediaDatabase.instance.getEpisodesForEntity(active['id']);
      if (mounted) {
        setState(() {
          _episodesByEntity[active['id']] = refreshedEps;
        });
      }
    } else {
      appLog('Could not resolve MAL ID for "${active['title']}".', tag: 'SeriesDetails');
    }
  }

  Future<void> _healMalId(Map<String, dynamic> entity) async {
    debugPrint('[SeriesDetails] Running self-healing for MAL ID: ${entity['title']}');
    int? resolved;
    if (entity['id'].toString().startsWith('anilist_')) {
      final aniId = int.tryParse(entity['id'].toString().split('_').last);
      if (aniId != null) resolved = await JikanService.resolveMalIdFromAnilist(aniId);
    }
    if (resolved == null || resolved == 0) {
      resolved = await JikanService.resolveMalIdBySearch(entity['title'], entity['year']);
    }
    if (resolved != null && resolved > 0) {
      final db = await MediaDatabase.instance.database;
      await db.rawUpdate('UPDATE media_entities SET id_mal = ? WHERE id = ?', [resolved, entity['id']]);
      JikanService.persistFillersToDb(entity['id'], resolved).then((_) {
        if (mounted) _loadData();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_franchiseEntities.isEmpty) return const Scaffold(body: Center(child: Text('Series not found')));

    final activeEntity = _franchiseEntities[_selectedTabIndex];

    return ExcludeSemantics(
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: _tabController == null 
          ? const SizedBox.shrink() 
          : Column(
              children: [
                _buildHeroHeader(activeEntity),
                _buildInfoSection(activeEntity),
                Container(
                  color: const Color(0xFF0F0F0F),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: Colors.redAccent,
                    labelColor: Colors.redAccent,
                    unselectedLabelColor: Colors.white38,
                    tabs: _franchiseEntities.map((e) => Tab(text: e['title'])).toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: _franchiseEntities.map((e) => EpisodeListView(
                      key: PageStorageKey('entity_${e['id']}'),
                      entity: e,
                      episodes: _episodesByEntity[e['id']] ?? [],
                      localFileMap: _localFileMap,
                      onRefresh: _loadData,
                    )).toList(),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildHeroHeader(Map<String, dynamic> entity) {
    return Stack(
      children: [
        SizedBox(
          height: 240,
          width: double.infinity,
          child: entity['backdrop_url'] != null
              ? Image.network(
                  entity['backdrop_url'], 
                  fit: BoxFit.cover, 
                  cacheWidth: 1000,
                  errorBuilder: (_, __, ___) => _buildFallbackBackdrop(entity)
                )
              : _buildFallbackBackdrop(entity),
        ),
        Container(
          height: 241,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xFF0F0F0F)],
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 10,
          child: Container(
            width: 80,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: entity['poster_url'] != null
                  ? Image.network(
                      entity['poster_url'], 
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                    )
                  : Container(color: Colors.white10),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top,
          left: 8,
          child: const BackButton(color: Colors.white),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top,
          right: 8,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.sync_alt, color: Colors.white),
                tooltip: 'Trackers',
                onPressed: () => TrackerBottomSheet.show(context, entity, _loadData),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.white),
                onPressed: () => ManualMatcherDialog.show(context, onComplete: _loadData),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackBackdrop(Map<String, dynamic> entity) {
    if (entity['poster_url'] != null) {
       return Image.network(entity['poster_url'], fit: BoxFit.cover, cacheWidth: 600);
    }
    return Container(color: Colors.white.withValues(alpha: 0.05));
  }

  Widget _buildInfoSection(Map<String, dynamic> entity) {
    final episodes = _episodesByEntity[entity['id']] ?? [];
    final nextEp = episodes.firstWhere((e) => (e['watch_state'] ?? 0) != 1, orElse: () => episodes.isEmpty ? {} : episodes.first);
    final hasNext = nextEp.isNotEmpty && nextEp['file_path'] != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(entity['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white))),
              if (hasNext)
                 ElevatedButton.icon(
                   onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(filePath: nextEp['file_path'], title: 'Ep ${nextEp['episode_number']} · ${entity['title']}'))).then((_) => _loadData()),
                   icon: const Icon(Icons.play_arrow, size: 18),
                   label: Text((nextEp['last_position_ms'] ?? 0) > 0 ? 'Resume E${nextEp['episode_number']}' : 'Play E${nextEp['episode_number']}', style: const TextStyle(fontSize: 11)),
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12)),
                 ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusBadge(entity['status']),
              _buildMetaChip(Icons.calendar_today, _formatDate(entity['start_date'])),
              _buildMetaChip(Icons.layers, '${entity['total_episodes'] ?? "?"} Eps'),
              if (entity['average_score'] != null)
                _buildMetaChip(Icons.star, '${entity['average_score']}%', color: Colors.amber),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entity['overview'] ?? 'No description available.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  maxLines: _isDescriptionExpanded ? 20 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isDescriptionExpanded ? 'Read Less' : 'Read More',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color = Colors.blueGrey;
    String label = status?.toUpperCase() ?? 'UNKNOWN';
    if (status == 'current' || status == 'airing' || status == 'releasing') {
      color = Colors.green;
      label = 'AIRING';
    } else if (status == 'finished') {
      color = Colors.blue;
      label = 'FINISHED';
    } else if (status == 'tba' || status == 'unreleased') {
      color = Colors.orange;
      label = 'UPCOMING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, {Color color = Colors.white38}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDate(String? date) {
    if (date == null) return 'N/A';
    try {
      final dt = DateTime.parse(date);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return date;
    }
  }
}

class EpisodeListView extends StatelessWidget {
  final Map<String, dynamic> entity;
  final List<Map<String, dynamic>> episodes;
  final Map<String, String> localFileMap;
  final VoidCallback onRefresh;

  const EpisodeListView({
    super.key,
    required this.entity,
    required this.episodes,
    required this.localFileMap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_outlined, size: 64, color: Colors.white10),
              const SizedBox(height: 16),
              Text('No local files mapped for ${entity['title']} yet.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ManualMatcherDialog.show(context, onComplete: onRefresh),
                icon: const Icon(Icons.add_link),
                label: const Text('Map Files to This Installment'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      key: PageStorageKey('season_list_${entity['id']}'),
      padding: const EdgeInsets.all(16),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final ep = episodes[index];
        final filePath = localFileMap[ep['id']];
        bool isAvailable = false;
        if (filePath != null) isAvailable = File(filePath).existsSync();

        return Opacity(
          opacity: isAvailable ? 1.0 : 0.45,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: isAvailable ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isAvailable ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isAvailable 
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(filePath: filePath!, title: 'Ep ${ep['episode_number']} · ${entity['title']}'))).then((_) => onRefresh())
                  : () => _showRemapFolder(context, onRefresh),
                onLongPress: isAvailable ? () => _showEpisodeOptions(context, ep, onRefresh) : null,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 110, height: 62,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (ep['still_path'] != null && ep['still_path'].toString().isNotEmpty)
                                    Image.network(
                                      ep['still_path'],
                                      fit: BoxFit.cover, 
                                      cacheWidth: 300,
                                      errorBuilder: (_, __, ___) => Container(color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24, size: 20))
                                    )
                                  else
                                    Container(color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24, size: 20)),
                                  
                                  if (isAvailable)
                                    Builder(
                                      builder: (context) {
                                        final double progress = (ep['duration_ms'] != null && ep['duration_ms'] > 0) ? (ep['last_position_ms'] ?? 0) / ep['duration_ms'] : 0.0;
                                        final bool isWatched = (ep['watch_state'] ?? 0) == 1;
                                        final bool isWatching = (ep['watch_state'] ?? 0) == 2;

                                        return Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (isWatched)
                                              Positioned.fill(
                                                child: Container(
                                                  color: Colors.black45,
                                                  child: const Center(child: Icon(Icons.check_circle, color: Colors.green, size: 24)),
                                                ),
                                              )
                                            else if (progress > 0.05)
                                              Positioned(
                                                bottom: 0,
                                                left: 0,
                                                right: 0,
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                  backgroundColor: Colors.white10,
                                                  valueColor: AlwaysStoppedAnimation<Color>(isWatching ? Colors.redAccent : Colors.white38),
                                                  minHeight: 2,
                                                ),
                                              ),
                                            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32)),
                                          ],
                                        );
                                      },
                                    )
                                  else
                                    const Center(child: Icon(Icons.cloud_download_outlined, color: Colors.white24, size: 24)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Episode ${ep['episode_number']}', style: TextStyle(color: isAvailable ? Colors.redAccent : Colors.white24, fontWeight: FontWeight.bold, fontSize: 11)),
                                    if (ep['episode_type'] == 'RECAP') ...[
                                      _buildTypeTag('RECAP', Colors.deepPurpleAccent),
                                    ] else if (ep['episode_type'] == 'FILLER' || ep['is_filler'] == 1 || ep['is_filler'] == true || ep['is_filler'].toString() == '1') ...[
                                      _buildTypeTag('FILLER', Colors.amber),
                                    ] else if (ep['episode_type'] == 'SPECIAL') ...[
                                      _buildTypeTag('SPECIAL', Colors.tealAccent),
                                    ],
                                    if (ep['watch_state'] == 1) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('WATCHED', style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                    ] else if (ep['watch_state'] == 2) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('WATCHING', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(ep['title'] ?? 'Unknown Title', style: TextStyle(color: isAvailable ? Colors.white : Colors.white10, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (!isAvailable)
                             const Icon(Icons.add_link, color: Colors.redAccent, size: 24),
                        ],
                      ),
                      if (ep['overview'] != null && ep['overview'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(
                            ep['overview'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypeTag(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _showRemapFolder(BuildContext context, VoidCallback onRefresh) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalFolderBrowserPage(
          onDirectorySelected: (selectedPath) {
            Navigator.pop(context);
            ManualMatcherDialog.show(context, onComplete: onRefresh);
          },
        ),
      ),
    );
  }

  void _showEpisodeOptions(BuildContext context, Map<String, dynamic> ep, VoidCallback onRefresh) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: const Text('Mark as Watched'),
                onTap: () async {
                  Navigator.pop(context);
                  await MediaDatabase.instance.updateWatchState(ep['file_path'], 1);
                  onRefresh();
                  SyncDispatcher.instance.scrobbleEpisode(
                    entityId: ep['media_entity_id'],
                    episodeNumber: ep['episode_number'],
                    context: context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Colors.white70),
                title: const Text('Mark as Unwatched'),
                onTap: () async {
                  Navigator.pop(context);
                  await MediaDatabase.instance.updateWatchState(ep['file_path'], 0);
                  await MediaDatabase.instance.updateProgress(ep['file_path'], 0, ep['duration_ms'] ?? 0);
                  onRefresh();
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.amber),
                title: const Text('Unpair / Re-pair File'),
                onTap: () async {
                  Navigator.pop(context);
                  _showRemapFolder(context, onRefresh);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Local File', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(context);
                  _confirmDeleteFile(context, ep, onRefresh);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteFile(BuildContext context, Map<String, dynamic> ep, VoidCallback onRefresh) {
     showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete File?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to permanently delete \'${ep['file_path'].split(Platform.pathSeparator).last}\' from storage? This cannot be undone.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                final file = File(ep['file_path']);
                if (await file.exists()) {
                  await file.delete();
                }
                await MediaDatabase.instance.deleteLocalFile(ep['file_path']);
                Navigator.pop(ctx);
                onRefresh();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting file: $e')));
              }
            },
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
