import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../engine/services/multi_provider_search_service.dart';
import 'aggregated_results_dashboard.dart';

class PreFlightMappingDialog {
  static void show(
    BuildContext context, {
    required List<AssetEntity> files,
    required String initialQuery,
    String? folderId,
    String? folderPath,
    VoidCallback? onComplete,
  }) {
    showDialog(
      context: context,
      builder: (context) => _PreFlightDialogWidget(
        files: files,
        initialQuery: initialQuery,
        folderId: folderId,
        folderPath: folderPath,
        onComplete: onComplete,
      ),
    );
  }
}

class _PreFlightDialogWidget extends StatefulWidget {
  final List<AssetEntity> files;
  final String initialQuery;
  final String? folderId;
  final String? folderPath;
  final VoidCallback? onComplete;

  const _PreFlightDialogWidget({
    required this.files,
    required this.initialQuery,
    this.folderId,
    this.folderPath,
    this.onComplete,
  });

  @override
  State<_PreFlightDialogWidget> createState() => _PreFlightDialogWidgetState();
}

class _PreFlightDialogWidgetState extends State<_PreFlightDialogWidget> {
  MediaCategory _selectedCategory = MediaCategory.anime;
  final Set<String> _selectedProviders = {'anilist', 'kitsu', 'mal', 'simkl'};

  void _onCategoryChanged(MediaCategory category) {
    setState(() {
      _selectedCategory = category;
      _selectedProviders.clear();
      if (category == MediaCategory.anime) {
        _selectedProviders.addAll({'anilist', 'kitsu', 'mal', 'simkl'});
      } else {
        _selectedProviders.add('simkl');
      }
    });
  }

  void _toggleProvider(String providerId) {
    setState(() {
      if (_selectedProviders.contains(providerId)) {
        if (_selectedProviders.length > 1) {
          _selectedProviders.remove(providerId);
        }
      } else {
        _selectedProviders.add(providerId);
      }
    });
  }

  void _startSearch() {
    if (_selectedProviders.isEmpty) return;

    Navigator.pop(context); // Close pre-flight dialog

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AggregatedResultsDashboardPage(
          files: widget.files,
          initialQuery: widget.initialQuery,
          selectedProviders: _selectedProviders.toList(),
          category: _selectedCategory,
          folderId: widget.folderId,
          folderPath: widget.folderPath,
          onComplete: widget.onComplete,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.redAccent, size: 22),
              const SizedBox(width: 8),
              const Text('Media Mapping Pre-Flight', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Target: "${widget.initialQuery}" (${widget.files.length} files)',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. SELECT CONTENT CLASSIFICATION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildCategoryCard(
                      category: MediaCategory.anime,
                      title: 'Anime',
                      subtitle: 'Series, Movies & OVAs',
                      icon: Icons.filter_hdr,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildCategoryCard(
                      category: MediaCategory.movieOrSeries,
                      title: 'Movies / Series',
                      subtitle: 'Live-action TV & Cinema',
                      icon: Icons.movie_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('2. TARGET METADATA PROVIDERS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 10),
              if (_selectedCategory == MediaCategory.anime) ...[
                _buildProviderCheckbox('anilist', 'AniList', 'GraphQL Anime Database'),
                _buildProviderCheckbox('kitsu', 'Kitsu', 'Anime & Manga Platform'),
                _buildProviderCheckbox('mal', 'MyAnimeList', 'MAL REST / Jikan API'),
                _buildProviderCheckbox('simkl', 'Simkl', 'Universal Anime & Show Tracker'),
              ] else ...[
                _buildProviderCheckbox('simkl', 'Simkl', 'Primary Provider for TV & Movies'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _selectedProviders.isNotEmpty ? _startSearch : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Start Multi-Provider Search', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required MediaCategory category,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedCategory == category;

    return GestureDetector(
      onTap: () => _onCategoryChanged(category),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.redAccent : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.redAccent : Colors.white54, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.redAccent : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCheckbox(String id, String title, String subtitle) {
    final isChecked = _selectedProviders.contains(id);

    return InkWell(
      onTap: () => _toggleProvider(id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Checkbox(
              value: isChecked,
              onChanged: (_) => _toggleProvider(id),
              activeColor: Colors.redAccent,
              checkColor: Colors.white,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isChecked ? Colors.white : Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
