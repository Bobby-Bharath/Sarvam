import 'dart:async';
import '../plugins/models/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../../utils/logger.dart';

enum MediaCategory { anime, movieOrSeries }

class ProviderSearchResult {
  final String providerId;
  final String providerName;
  final List<MediaSearchResult> results;
  final String? error;

  ProviderSearchResult({
    required this.providerId,
    required this.providerName,
    required this.results,
    this.error,
  });
}

class AggregatedSearchGroup {
  final Map<String, List<MediaSearchResult>> providerResults;
  final List<MediaSearchResult> allResults;
  final MediaSearchResult? primarySuggestion;
  final double? primaryConfidenceScore;

  AggregatedSearchGroup({
    required this.providerResults,
    required this.allResults,
    this.primarySuggestion,
    this.primaryConfidenceScore,
  });
}

class MultiProviderSearchService {
  static final MultiProviderSearchService instance = MultiProviderSearchService._();
  MultiProviderSearchService._();

  Future<AggregatedSearchGroup> searchAll({
    required String query,
    required List<String> providerIds,
    required MediaCategory category,
    bool isManualSearch = false,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || providerIds.isEmpty) {
      return AggregatedSearchGroup(providerResults: {}, allResults: []);
    }

    final registry = PluginRegistry.instance;

    // Run parallel queries across selected providers
    final futures = providerIds.map((pid) async {
      final plugin = registry.getPlugin(pid);
      if (plugin == null) {
        return ProviderSearchResult(
          providerId: pid,
          providerName: pid.toUpperCase(),
          results: [],
          error: 'Plugin not registered',
        );
      }

      try {
        final results = await plugin.search(cleanQuery, isManualSearch: isManualSearch).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            appLog('Provider $pid search timed out for query "$cleanQuery"', tag: 'MULTI_SEARCH');
            return [];
          },
        );
        return ProviderSearchResult(
          providerId: pid,
          providerName: plugin.name,
          results: results,
        );
      } catch (e) {
        appLog('Provider $pid search error: $e', tag: 'MULTI_SEARCH');
        return ProviderSearchResult(
          providerId: pid,
          providerName: plugin.name,
          results: [],
          error: e.toString(),
        );
      }
    });

    final providerResponses = await Future.wait(futures);

    final Map<String, List<MediaSearchResult>> providerMap = {};
    final List<MediaSearchResult> combinedList = [];

    for (var resp in providerResponses) {
      providerMap[resp.providerId] = resp.results;
      combinedList.addAll(resp.results);
    }

    // Rank results to find primary high-confidence automated mapping suggestion
    MediaSearchResult? primary;
    double? confidence;

    if (combinedList.isNotEmpty) {
      final ranked = _rankCandidateResults(cleanQuery, combinedList);
      primary = ranked.$1;
      confidence = ranked.$2;
    }

    return AggregatedSearchGroup(
      providerResults: providerMap,
      allResults: combinedList,
      primarySuggestion: primary,
      primaryConfidenceScore: confidence,
    );
  }

  (MediaSearchResult, double) _rankCandidateResults(String query, List<MediaSearchResult> candidates) {
    final cleanQ = query.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

    MediaSearchResult bestMatch = candidates.first;
    double maxScore = -1;

    for (var item in candidates) {
      double score = 0;
      final cleanTitle = item.title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

      // 1. Exact or title match ratio
      if (cleanTitle == cleanQ) {
        score += 50;
      } else if (cleanTitle.contains(cleanQ) || cleanQ.contains(cleanTitle)) {
        score += 30;
      }

      // 2. Rating bonus
      if (item.averageScore != null) {
        score += (item.averageScore! / 10).clamp(0, 10);
      }

      // 3. Poster presence bonus
      if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
        score += 5;
      }

      // 4. Primary provider bias (e.g., AniList / Kitsu / Simkl)
      if (item.providerId == 'anilist' || item.providerId == 'kitsu' || item.providerId == 'simkl') {
        score += 5;
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = item;
      }
    }

    // Normalize confidence score to percentage (65% - 98%)
    final confidencePct = ((maxScore / 70.0) * 100).clamp(65.0, 98.0);
    return (bestMatch, confidencePct);
  }
}
