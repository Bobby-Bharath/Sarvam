import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../engine/metadata/media_tag_parser.dart';
import '../../engine/plugins/models/plugin_models.dart';
import '../../engine/services/multi_provider_search_service.dart';
import 'interactive_mapping_page.dart';

class AggregatedResultsDashboardPage extends StatefulWidget {
  final List<AssetEntity> files;
  final String initialQuery;
  final List<String> selectedProviders;
  final MediaCategory category;
  final String? folderId;
  final String? folderPath;
  final VoidCallback? onComplete;

  const AggregatedResultsDashboardPage({
    super.key,
    required this.files,
    required this.initialQuery,
    required this.selectedProviders,
    required this.category,
    this.folderId,
    this.folderPath,
    this.onComplete,
  });

  @override
  State<AggregatedResultsDashboardPage> createState() => _AggregatedResultsDashboardPageState();
}

class _AggregatedResultsDashboardPageState extends State<AggregatedResultsDashboardPage> with TickerProviderStateMixin {
  late TextEditingController _searchController;
  bool _isSearching = true;
  AggregatedSearchGroup? _searchGroup;
  TabController? _tabController;

  // Active filter states
  final Set<MediaClassification> _selectedClassifications = {};
  final Set<AiringStatus> _selectedAiringStatuses = {};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _performSearch(widget.initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query, {bool isManualSearch = false}) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
    });

    final group = await MultiProviderSearchService.instance.searchAll(
      query: query,
      providerIds: widget.selectedProviders,
      category: widget.category,
      isManualSearch: isManualSearch,
    );

    if (!mounted) return;

    _tabController?.dispose();
    final tabCount = widget.selectedProviders.length + 1; // "All" + each provider
    _tabController = TabController(length: tabCount, vsync: this);

    setState(() {
      _searchGroup = group;
      _isSearching = false;
    });
  }

  List<MediaSearchResult> _getFilteredResults(List<MediaSearchResult> input) {
    return input.where((item) {
      final matchesCls = _selectedClassifications.isEmpty ||
          _selectedClassifications.contains(item.classification);
      final matchesStatus = _selectedAiringStatuses.isEmpty ||
          _selectedAiringStatuses.contains(item.airingStatus);
      return matchesCls && matchesStatus;
    }).toList();
  }

  MediaSearchResult? _getFilteredPrimarySuggestion() {
    if (_searchGroup == null) return null;
    final allFiltered = _getFilteredResults(_searchGroup!.allResults);
    if (allFiltered.isEmpty) return null;

    if (_searchGroup!.primarySuggestion != null) {
      final primary = _searchGroup!.primarySuggestion!;
      final matchesCls = _selectedClassifications.isEmpty ||
          _selectedClassifications.contains(primary.classification);
      final matchesStatus = _selectedAiringStatuses.isEmpty ||
          _selectedAiringStatuses.contains(primary.airingStatus);
      if (matchesCls && matchesStatus) return primary;
    }
    return allFiltered.first;
  }

  void _toggleClassificationFilter(MediaClassification classification) {
    setState(() {
      if (_selectedClassifications.contains(classification)) {
        _selectedClassifications.remove(classification);
      } else {
        _selectedClassifications.add(classification);
      }
    });
  }

  void _toggleAiringStatusFilter(AiringStatus status) {
    setState(() {
      if (_selectedAiringStatuses.contains(status)) {
        _selectedAiringStatuses.remove(status);
      } else {
        _selectedAiringStatuses.add(status);
      }
    });
  }

  void _clearAllFilters() {
    setState(() {
      _selectedClassifications.clear();
      _selectedAiringStatuses.clear();
    });
  }

  void _navigateToMapping(MediaSearchResult selectedMedia) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InteractiveMappingPage(
          files: widget.files,
          media: selectedMedia,
          folderId: widget.folderId,
          folderPath: widget.folderPath,
        ),
      ),
    ).then((_) {
      if (mounted) {
        widget.onComplete?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allUnfiltered = _searchGroup?.allResults ?? [];
    final allFiltered = _getFilteredResults(allUnfiltered);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pre-Flight Media Aggregator',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  widget.category == MediaCategory.anime ? Icons.filter_hdr : Icons.movie_outlined,
                  size: 12,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.category == MediaCategory.anime ? "Anime Classification" : "Movies / Series"} · ${widget.selectedProviders.length} Providers',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (!_isSearching && allUnfiltered.isNotEmpty) _buildTagFilterBar(allUnfiltered),
          if (_isSearching)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text(
                      'Querying ${widget.selectedProviders.map((p) => p.toUpperCase()).join(", ")} in parallel...',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchGroup == null || allUnfiltered.isEmpty)
            Expanded(child: _buildEmptyState())
          else if (allFiltered.isEmpty)
            Expanded(child: _buildNoFilterMatchState())
          else
            Expanded(
              child: Column(
                children: [
                  if (_getFilteredPrimarySuggestion() != null)
                    _buildPrimarySuggestionCard(_getFilteredPrimarySuggestion()!),
                  _buildProviderTabBar(),
                  Expanded(child: _buildTabBarView()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.search,
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) _performSearch(val.trim(), isManualSearch: true);
              },
              decoration: InputDecoration(
                hintText: 'Search title across providers...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.3),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final query = _searchController.text.trim();
              if (query.isNotEmpty) _performSearch(query, isManualSearch: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTagFilterBar(List<MediaSearchResult> allItems) {
    final bool hasNoFilters = _selectedClassifications.isEmpty && _selectedAiringStatuses.isEmpty;

    // Counts for classifications
    final Map<MediaClassification, int> clsCounts = {};
    for (var cls in MediaClassification.values) {
      clsCounts[cls] = allItems.where((item) => item.classification == cls).length;
    }

    // Counts for airing statuses
    final Map<AiringStatus, int> statusCounts = {};
    for (var status in [AiringStatus.airing, AiringStatus.aired, AiringStatus.upcoming]) {
      statusCounts[status] = allItems.where((item) => item.airingStatus == status).length;
    }

    // Sort classifications: active chips first
    final sortedClassifications = MediaClassification.values.toList()
      ..sort((a, b) => (_selectedClassifications.contains(b) ? 1 : 0)
          .compareTo(_selectedClassifications.contains(a) ? 1 : 0));

    // Sort airing statuses: active chips first
    final sortedStatuses = [AiringStatus.airing, AiringStatus.aired, AiringStatus.upcoming]
      ..sort((a, b) => (_selectedAiringStatuses.contains(b) ? 1 : 0)
          .compareTo(_selectedAiringStatuses.contains(a) ? 1 : 0));

    return Container(
      width: double.infinity,
      color: const Color(0xFF181818),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // "All" Reset Chip
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                selected: hasNoFilters,
                label: Text('All (${allItems.length})'),
                labelStyle: TextStyle(
                  color: hasNoFilters ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                selectedColor: Colors.redAccent,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(
                  color: hasNoFilters ? Colors.redAccent : Colors.white10,
                ),
                onSelected: (_) => _clearAllFilters(),
              ),
            ),
            // Format / Classification Chips (Active First)
            ...sortedClassifications.map((cls) {
              final count = clsCounts[cls] ?? 0;
              final isSelected = _selectedClassifications.contains(cls);
              final chipColor = _getClassificationColor(cls);

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  selected: isSelected,
                  label: Text('${cls.shortCode} ($count)'),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : (count > 0 ? Colors.white70 : Colors.white24),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  selectedColor: chipColor,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(
                    color: isSelected ? chipColor : Colors.white10,
                  ),
                  onSelected: (count > 0 || isSelected)
                      ? (_) => _toggleClassificationFilter(cls)
                      : null,
                ),
              );
            }),
            // Airing Status Chips (Active First)
            ...sortedStatuses.map((status) {
              final count = statusCounts[status] ?? 0;
              final isSelected = _selectedAiringStatuses.contains(status);
              final chipColor = _getAiringStatusColor(status);

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  selected: isSelected,
                  label: Text('${_getAiringStatusIcon(status)} ${status.shortCode} ($count)'),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : (count > 0 ? Colors.white70 : Colors.white24),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  selectedColor: chipColor,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(
                    color: isSelected ? chipColor : Colors.white10,
                  ),
                  onSelected: (count > 0 || isSelected)
                      ? (_) => _toggleAiringStatusFilter(status)
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimarySuggestionCard(MediaSearchResult primary) {
    final confidencePct = _searchGroup!.primaryConfidenceScore?.toStringAsFixed(0) ?? '90';

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.redAccent.withValues(alpha: 0.25),
            Colors.purple.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'HIGH-CONFIDENCE AUTOMATED MATCH',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '$confidencePct% Confidence',
                    style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: primary.posterUrl != null && primary.posterUrl!.isNotEmpty
                      ? Image.network(primary.posterUrl!, width: 55, height: 80, fit: BoxFit.cover)
                      : Container(
                          width: 55,
                          height: 80,
                          color: Colors.white10,
                          child: const Icon(Icons.movie, color: Colors.white24),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primary.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _buildBadge(primary.providerId.toUpperCase(), Colors.amber),
                          _buildClassificationBadge(primary.classification),
                          _buildAiringBadge(primary.airingStatus),
                          if (primary.year != null)
                            Text('${primary.year}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          if (primary.totalEpisodes != null) ...[
                            Text('· ${primary.totalEpisodes} Eps', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ],
                      ),
                      if (primary.overview != null && primary.overview!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          primary.overview!,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _navigateToMapping(primary),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: Colors.white),
                      SizedBox(height: 2),
                      Text('Select', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderTabBar() {
    if (_tabController == null) return const SizedBox.shrink();

    final allFiltered = _getFilteredResults(_searchGroup?.allResults ?? []);

    final tabs = <Widget>[
      Tab(text: 'All (${allFiltered.length})'),
    ];

    for (var pid in widget.selectedProviders) {
      final providerList = _searchGroup?.providerResults[pid] ?? [];
      final filteredList = _getFilteredResults(providerList);
      tabs.add(Tab(text: '${pid.toUpperCase()} (${filteredList.length})'));
    }

    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: Colors.redAccent,
      labelColor: Colors.redAccent,
      unselectedLabelColor: Colors.white38,
      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      tabs: tabs,
    );
  }

  Widget _buildTabBarView() {
    if (_tabController == null || _searchGroup == null) return const SizedBox.shrink();

    final allFiltered = _getFilteredResults(_searchGroup!.allResults);

    final views = <Widget>[
      _buildResultsList(allFiltered),
    ];

    for (var pid in widget.selectedProviders) {
      final providerList = _searchGroup!.providerResults[pid] ?? [];
      final filteredList = _getFilteredResults(providerList);
      views.add(_buildResultsList(filteredList));
    }

    return TabBarView(
      controller: _tabController,
      children: views,
    );
  }

  Widget _buildResultsList(List<MediaSearchResult> results) {
    if (results.isEmpty) {
      return const Center(
        child: Text('No matching results for current filters.', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    final primaryFiltered = _getFilteredPrimarySuggestion();

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final media = results[index];
        final isPrimary = primaryFiltered?.id == media.id && primaryFiltered?.providerId == media.providerId;

        return Card(
          color: Colors.white.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isPrimary ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white10),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: media.posterUrl != null && media.posterUrl!.isNotEmpty
                  ? Image.network(media.posterUrl!, width: 42, height: 62, fit: BoxFit.cover)
                  : Container(width: 42, height: 62, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24)),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    media.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                _buildClassificationBadge(media.classification),
                const SizedBox(width: 4),
                _buildAiringBadge(media.airingStatus),
                const SizedBox(width: 4),
                _buildBadge(media.providerId.toUpperCase(), Colors.redAccent),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${media.year ?? "Unknown Year"}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    if (media.totalEpisodes != null) ...[
                      const Text(' · ', style: TextStyle(color: Colors.white38)),
                      Text('${media.totalEpisodes} Episodes', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                    if (media.averageScore != null) ...[
                      const Text(' · ', style: TextStyle(color: Colors.white38)),
                      Icon(Icons.star, size: 12, color: Colors.amber.shade600),
                      Text(' ${media.averageScore!.toStringAsFixed(1)}', style: TextStyle(color: Colors.amber.shade600, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
                if (media.overview != null && media.overview!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(media.overview!, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.redAccent, size: 16),
              onPressed: () => _navigateToMapping(media),
            ),
            onTap: () => _navigateToMapping(media),
          ),
        );
      },
    );
  }

  Widget _buildClassificationBadge(MediaClassification classification) {
    final color = _getClassificationColor(classification);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        classification.shortCode,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAiringBadge(AiringStatus status) {
    if (status == AiringStatus.unknown) return const SizedBox.shrink();
    final color = _getAiringStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        '${_getAiringStatusIcon(status)} ${status.shortCode}',
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getClassificationColor(MediaClassification classification) {
    switch (classification) {
      case MediaClassification.tvSeries:
        return Colors.blue;
      case MediaClassification.movie:
        return Colors.purpleAccent;
      case MediaClassification.ova:
        return Colors.orangeAccent;
      case MediaClassification.special:
        return Colors.amber;
      case MediaClassification.trailer:
        return Colors.redAccent;
    }
  }

  Color _getAiringStatusColor(AiringStatus status) {
    switch (status) {
      case AiringStatus.airing:
        return Colors.redAccent;
      case AiringStatus.aired:
        return Colors.green;
      case AiringStatus.upcoming:
        return Colors.tealAccent;
      case AiringStatus.unknown:
        return Colors.grey;
    }
  }

  String _getAiringStatusIcon(AiringStatus status) {
    switch (status) {
      case AiringStatus.airing:
        return '🔴';
      case AiringStatus.aired:
        return '🟢';
      case AiringStatus.upcoming:
        return '📅';
      case AiringStatus.unknown:
        return '❓';
    }
  }

  Widget _buildNoFilterMatchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list_off, size: 56, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No Results Match Selected Filters', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _clearAllFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Clear Active Filters', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            const Text('No Results Found Across Selected Providers', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting the search title or select different providers.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
