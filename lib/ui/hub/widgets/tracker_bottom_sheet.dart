import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../database/media_database.dart';
import '../../../engine/auth/anilist_service.dart';
import '../../settings/tracker_accounts_page.dart';
import '../../../utils/logger.dart';
import '../../../engine/metadata/jikan_service.dart';
import '../../../engine/community_service.dart';

class TrackerBottomSheet extends StatefulWidget {
  final Map<String, dynamic> entity;
  final VoidCallback onUpdate;

  const TrackerBottomSheet({
    super.key,
    required this.entity,
    required this.onUpdate,
  });

  @override
  State<TrackerBottomSheet> createState() => _TrackerBottomSheetState();

  static void show(BuildContext context, Map<String, dynamic> entity, VoidCallback onUpdate) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (context) => TrackerBottomSheet(entity: entity, onUpdate: onUpdate),
    );
  }
}

class _TrackerBottomSheetState extends State<TrackerBottomSheet> {
  final AniListService _anilist = AniListService();
  bool _isAniListLoggedIn = false;
  Map<String, dynamic>? _anilistEntry;
  bool _isLoading = true;
  int? _resolvedAniListId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _isAniListLoggedIn = prefs.getBool('anilist_logged_in') ?? false;
    
    if (_isAniListLoggedIn) {
      final String idStr = widget.entity['id'].toString();
      if (idStr.startsWith('anilist_')) {
        _resolvedAniListId = int.tryParse(idStr.split('_').last);
      } else {
        appLog('Resolving AniList ID for ${widget.entity['title']}...', tag: 'Tracker');
        final kitsuId = idStr.split('_').last;
        _resolvedAniListId = await JikanService.resolveAnilistIdFromKitsu(kitsuId);

        if (_resolvedAniListId == null) {
          final results = await _anilist.search(widget.entity['title']);
          if (results.isNotEmpty) {
            final topMatch = results.first;
            _resolvedAniListId = int.tryParse(topMatch['id'].toString());
            final int? matchedMalId = topMatch['idMal'] is int ? topMatch['idMal'] : int.tryParse(topMatch['idMal']?.toString() ?? '');

            if (matchedMalId != null) {
              final db = await MediaDatabase.instance.database;
              await db.rawUpdate(
                'UPDATE media_entities SET id_mal = ? WHERE id = ?',
                [matchedMalId, widget.entity['id']],
              );
            }
          }
        }
      }

      if (_resolvedAniListId != null) {
        _anilistEntry = await _anilist.fetchEntry(_resolvedAniListId!);
      }
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Trackers & Sync', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : ListView(
                    controller: scrollController,
                    children: [
                      _buildTrackerTile(
                        name: 'AniList',
                        icon: Icons.auto_awesome_motion,
                        color: Colors.blue,
                        isLoggedIn: _isAniListLoggedIn,
                        entry: _anilistEntry,
                        onSync: (progress, status, score) async {
                          if (_resolvedAniListId != null) {
                            final success = await _anilist.updateEntry(
                              mediaId: _resolvedAniListId!,
                              progress: progress,
                              status: status,
                              score: score,
                            );
                            if (success && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Successfully synced ${widget.entity['title']} to AniList (Ep $progress · ${score.toStringAsFixed(1)} ⭐)'), 
                                  backgroundColor: Colors.green
                                )
                              );
                              widget.onUpdate();
                              Navigator.pop(context);
                            } else if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Sync Failed. Check console logs.'), backgroundColor: Colors.redAccent));
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildPlaceholderTile('MyAnimeList', Icons.list_alt, const Color(0xFF2E51A2)),
                      const SizedBox(height: 12),
                      _buildPlaceholderTile('SIMKL', Icons.tv, Colors.cyan),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackerTile({
    required String name,
    required IconData icon,
    required Color color,
    required bool isLoggedIn,
    required Map<String, dynamic>? entry,
    required Function(int progress, String status, double score) onSync,
  }) {
    if (!isLoggedIn) {
      return Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: const Text('Login Required in Settings', style: TextStyle(color: Colors.white24, fontSize: 11)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackerAccountsPage())),
          trailing: const Icon(Icons.chevron_right, color: Colors.white10),
        ),
      );
    }

    return _TrackerInteractiveCard(
      name: name,
      icon: icon,
      color: color,
      entry: entry,
      totalEpisodes: widget.entity['total_episodes'],
      onSync: onSync,
    );
  }

  Widget _buildPlaceholderTile(String name, IconData icon, Color color) {
    return Opacity(
      opacity: 0.5,
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: const Text('Coming Soon', style: TextStyle(color: Colors.white24, fontSize: 11)),
        ),
      ),
    );
  }
}

class _TrackerInteractiveCard extends StatefulWidget {
  final String name;
  final IconData icon;
  final Color color;
  final Map<String, dynamic>? entry;
  final int? totalEpisodes;
  final Function(int progress, String status, double score) onSync;

  const _TrackerInteractiveCard({
    required this.name,
    required this.icon,
    required this.color,
    this.entry,
    this.totalEpisodes,
    required this.onSync,
  });

  @override
  State<_TrackerInteractiveCard> createState() => _TrackerInteractiveCardState();
}

class _TrackerInteractiveCardState extends State<_TrackerInteractiveCard> {
  late int _progress;
  late String _status;
  late double _score;
  bool _isSaving = false;

  final Map<String, String> _statusMap = {
    'CURRENT': 'Watching',
    'PLANNING': 'Plan to Watch',
    'COMPLETED': 'Completed',
    'PAUSED': 'On Hold',
    'DROPPED': 'Dropped',
  };

  @override
  void initState() {
    super.initState();
    _progress = widget.entry?['progress'] ?? 0;
    _status = widget.entry?['status'] ?? 'PLANNING';
    _score = CommunityService.normalizeScore(widget.entry?['score']) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.color.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: widget.color.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(widget.icon, color: widget.color, size: 18),
                const SizedBox(width: 8),
                Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                const Spacer(),
                Text(_statusMap[_status] ?? _status, style: TextStyle(color: widget.color, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStepper(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('SCORE', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                    Text(_score > 0 ? _score.toStringAsFixed(1) : '--', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: widget.color,
                thumbColor: widget.color,
                overlayColor: widget.color.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _score,
                min: 0,
                max: 10,
                divisions: 100,
                onChanged: (v) => setState(() => _score = v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    children: _statusMap.keys.map((s) => _statusChip(s)).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSaving ? null : () async {
                setState(() => _isSaving = true);
                await widget.onSync(_progress, _status, _score * 10.0); // Convert back to 100-scale
                if (mounted) setState(() => _isSaving = false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.color,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save & Sync Now', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.remove, size: 16, color: Colors.white38), onPressed: () => setState(() => _progress = (_progress - 1).clamp(0, 9999))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$_progress / ${widget.totalEpisodes ?? "?"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          ),
          IconButton(icon: const Icon(Icons.add, size: 16, color: Colors.redAccent), onPressed: () => setState(() => _progress = (_progress + 1).clamp(0, 9999))),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final bool isSelected = _status == status;
    return GestureDetector(
      onTap: () => setState(() => _status = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? widget.color : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _statusMap[status]!,
          style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }
}
