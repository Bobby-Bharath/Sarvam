import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../engine/plugins/models/plugin_models.dart';
import '../../engine/plugins/plugin_registry.dart';
import '../../engine/metadata/filename_tokenizer.dart';
import '../../database/media_database.dart';
import '../../main.dart'; 

class InteractiveMappingPage extends StatefulWidget {
  final List<AssetEntity> files;
  final MediaSearchResult media;
  final String? folderId;
  final String? folderPath;

  const InteractiveMappingPage({
    super.key,
    required this.files,
    required this.media,
    this.folderId,
    this.folderPath,
  });

  @override
  State<InteractiveMappingPage> createState() => _InteractiveMappingPageState();
}

class _InteractiveMappingPageState extends State<InteractiveMappingPage> with TickerProviderStateMixin {
  late TabController _tabController;
  FranchiseManifest? _franchise;
  bool _isLoadingFranchise = true;
  String _currentProvider = 'kitsu';

  // Global Mapping State: Episode ID (from manifest) -> Local Asset
  final Map<String, AssetEntity?> _mapping = {};
  final Set<String> _ignoredAssetIds = {};
  AssetEntity? _selectedAsset;

  @override
  void initState() {
    super.initState();
    _currentProvider = widget.media.providerId;
    _fetchFranchise(widget.media.id, _currentProvider);
  }

  @override
  void dispose() {
    if (mounted) _tabController.dispose();
    super.dispose();
  }

  // lib/ui/pairing/interactive_mapping_page.dart

  // lib/ui/pairing/interactive_mapping_page.dart

  Future<void> _fetchFranchise(String mediaId, String providerId) async {
    setState(() {
      _isLoadingFranchise = true;
      _franchise = null;
    });

    final plugin = PluginRegistry.instance.getPlugin(providerId);
    if (plugin != null) {
      String actualId = mediaId;

      // When switching providers, resolve the correct ID for the new provider
      if (providerId != widget.media.providerId || actualId.startsWith('anilist_') || actualId.startsWith('mal_')) {
        final cleanTitle = widget.media.title
            .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '')
            .trim();

        final searchResults = await plugin.search(cleanTitle);
        if (searchResults.isNotEmpty) {
          actualId = searchResults.first.id;
        } else if (widget.media.idMal != null && providerId == 'mal') {
          actualId = widget.media.idMal.toString();
        }
      }

      final franchise = await plugin.fetchFranchise(actualId);
      if (mounted) {
        setState(() {
          _franchise = franchise;
          _tabController = TabController(length: franchise.entries.length, vsync: this);
          _isLoadingFranchise = false;
          _mapping.clear();
          _autoMatchByToken();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Switched to ${plugin.name}. Discovered ${franchise.entries.length} installments.')),
        );
      }
    }
  }

  void _autoMatchByToken() {
    if (_franchise == null) return;
    
    for (var series in _franchise!.entries) {
      int totalEps = series.series.totalEpisodes ?? 0;
      bool isOngoing = series.series.status == 'current' || series.series.status == 'releasing';
      
      if (isOngoing || totalEps == 0) {
         int maxLocal = 0;
         for (var file in widget.files) {
           final token = FilenameTokenizer.parse(file.title ?? '');
           if (token.episodeNumber != null && token.episodeNumber! > maxLocal) {
             maxLocal = token.episodeNumber!;
           }
         }
         if (maxLocal > totalEps) {
            final int diff = maxLocal - totalEps;
            for (int i = 1; i <= diff; i++) {
              series.episodes.add(EpisodeManifest(
                id: 'ghost_${series.series.id}_${totalEps + i}',
                seasonNumber: 1,
                episodeNumber: totalEps + i,
                title: 'Episode ${totalEps + i}',
                isFiller: false,
              ));
            }
         }
      }

      for (var ep in series.episodes) {
        final epUniqueId = '${series.series.providerId}_${series.series.id}_e${ep.episodeNumber}';
        
        for (var file in widget.files) {
          if (_ignoredAssetIds.contains(file.id)) continue;
          if (_mapping.values.contains(file)) continue;

          final token = FilenameTokenizer.parse(file.title ?? '');
          if (token.episodeNumber == ep.episodeNumber) {
             _mapping[epUniqueId] = file;
             break;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Mapping Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _buildProviderSwitcher(),
        ],
        bottom: _franchise == null ? null : TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.redAccent,
          labelColor: Colors.redAccent,
          unselectedLabelColor: Colors.white38,
          tabs: _franchise!.entries.map((e) => Tab(text: e.series.title)).toList(),
        ),
      ),
      body: _isLoadingFranchise 
        ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
        : Column(
            children: [
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _franchise!.entries.map((e) => _buildManifestList(e)).toList(),
                ),
              ),
              _buildUnassignedDock(),
              _buildFooter(),
            ],
          ),
    );
  }

  Widget _buildProviderSwitcher() {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: PopupMenuButton<String>(
        initialValue: _currentProvider,
        tooltip: 'Change Metadata Provider',
        icon: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentProvider.toUpperCase(),
                style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.swap_horiz, color: Colors.redAccent, size: 16),
            ],
          ),
        ),
        onSelected: (providerId) {
          if (providerId != _currentProvider) {
            setState(() => _currentProvider = providerId);
            _fetchFranchise(widget.media.id, providerId);
          }
        },
        itemBuilder: (context) => [
          _buildProviderItem('anilist', 'AniList'),
          _buildProviderItem('mal', 'MyAnimeList'),
          _buildProviderItem('simkl', 'Simkl'),
          _buildProviderItem('kitsu', 'Kitsu'),
        ],
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  PopupMenuItem<String> _buildProviderItem(String id, String label) {
    final bool isSelected = _currentProvider == id;
    return PopupMenuItem(
      value: id,
      child: Row(
        children: [
          Text(label, style: TextStyle(color: isSelected ? Colors.redAccent : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, color: Colors.redAccent, size: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildManifestList(SeriesManifest series) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: series.episodes.length,
      itemBuilder: (context, index) => _buildEpisodeSlot(series, series.episodes[index]),
    );
  }

  Widget _buildEpisodeSlot(SeriesManifest series, EpisodeManifest ep) {
    final epUniqueId = '${series.series.providerId}_${series.series.id}_e${ep.episodeNumber}';
    final assignedAsset = _mapping[epUniqueId];
    final isTarget = _selectedAsset != null && assignedAsset == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: assignedAsset != null ? Colors.green.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: assignedAsset != null ? Colors.green.withValues(alpha: 0.2) : (isTarget ? Colors.redAccent : Colors.white10)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              onTap: () {
                if (_selectedAsset != null && assignedAsset == null) {
                  setState(() {
                    _mapping[epUniqueId] = _selectedAsset;
                    _selectedAsset = null;
                  });
                } else if (assignedAsset == null) {
                  _showFilePickerSheet(epUniqueId, 'Ep ${ep.episodeNumber} · ${ep.title ?? "Untitled"}');
                }
              },
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ep.stillPath != null
                    ? Image.network(ep.stillPath!, width: 80, height: 45, fit: BoxFit.cover, cacheWidth: 160)
                    : Container(width: 80, height: 45, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white12, size: 20)),
              ),
              title: Row(
                children: [
                  Text('EPISODE ${ep.episodeNumber}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10)),
                  if (ep.isFiller) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                      child: const Text('FILLER', style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(ep.title ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: assignedAsset != null
                ? IconButton(icon: const Icon(Icons.link_off, size: 18, color: Colors.white38), onPressed: () => setState(() => _mapping.remove(epUniqueId)))
                : const Icon(Icons.add_link, size: 18, color: Colors.white10),
            ),
            if (assignedAsset != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 12, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        assignedAsset.title ?? 'Unknown File',
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDuration(Duration(seconds: assignedAsset.duration)),
                      style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => _showFilePickerSheet(epUniqueId, 'Ep ${ep.episodeNumber} · ${ep.title ?? "Untitled"}'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: const Text('SWAP', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnassignedDock() {
    final unassigned = widget.files.where((f) => !_mapping.values.contains(f) && !_ignoredAssetIds.contains(f.id)).toList();
    if (unassigned.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('UNASSIGNED FILES (${unassigned.length})', style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: unassigned.length,
              itemBuilder: (context, index) {
                final file = unassigned[index];
                final isSelected = _selectedAsset == file;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAsset = isSelected ? null : file),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? Colors.redAccent : Colors.transparent),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(file.title ?? 'Untitled', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        Row(
                          children: [
                            Text(formatDuration(Duration(seconds: file.duration)), style: const TextStyle(color: Colors.white24, fontSize: 8)),
                            const Spacer(),
                            if (isSelected) const Icon(Icons.check_circle, color: Colors.redAccent, size: 14),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _saveMapping,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Finalize Mapping', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilePickerSheet(String epUniqueId, String title) {
     showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final unassigned = widget.files.where((f) => !_mapping.values.contains(f) && !_ignoredAssetIds.contains(f.id)).toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.all(16), child: Text('Assign File to $title', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              if (unassigned.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Text('No unassigned files left.', style: TextStyle(color: Colors.white38))),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: unassigned.length,
                  itemBuilder: (context, index) {
                    final file = unassigned[index];
                    return ListTile(
                      title: Text(file.title ?? 'Untitled', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text(formatDuration(Duration(seconds: file.duration)), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      onTap: () {
                        setState(() => _mapping[epUniqueId] = file);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Future<void> _saveMapping() async {
    final db = MediaDatabase.instance;
    
    for (var series in _franchise!.entries) {
      await db.upsertMediaEntity({
        'id': series.series.id,
        'display_provider': series.series.providerId,
        'entity_type': series.series.type.name,
        'title': series.series.title,
        'overview': series.series.overview,
        'poster_url': series.series.posterUrl,
        'backdrop_url': series.series.backdropUrl,
        'total_episodes': series.series.totalEpisodes,
        'year': series.series.year,
        'status': series.series.status,
        'average_score': series.series.averageScore?.toString(),
        'id_mal': series.series.idMal,
        'franchise_id': widget.media.title, // Bind all to same franchise
      });

      for (var ep in series.episodes) {
        await db.upsertEpisode({
          'id': '${series.series.id}_${ep.episodeNumber}',
          'media_entity_id': series.series.id,
          'season_number': ep.seasonNumber,
          'episode_number': ep.episodeNumber,
          'title': ep.title,
          'overview': ep.overview,
          'still_path': ep.stillPath,
          'air_date': ep.airDate,
          'is_filler': ep.isFiller ? 1 : 0,
        });

        final epUniqueId = '${series.series.providerId}_${series.series.id}_e${ep.episodeNumber}';
        final asset = _mapping[epUniqueId];
        if (asset != null) {
          final file = await asset.originFile;
          if (file != null) {
            await db.upsertLocalFile({
              'file_path': file.path,
              'media_entity_id': series.series.id,
              'episode_id': '${series.series.id}_${ep.episodeNumber}',
              'file_size': await file.length(),
              'duration_ms': asset.duration * 1000,
            });
          }
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Mapping Saved Successfully'), backgroundColor: Colors.green));
      Navigator.pop(context);
    }
  }
}
