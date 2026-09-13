enum PluginType { anime, tv, movie, general }
// lib/engine/plugins/models/plugin_models.dart

enum MediaType { anime, movie, tv, ova }

class MediaSearchResult {
  final String id;
  final String providerId;
  final String title;
  final String? originalTitle;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final int? year;
  final String? status;
  final double? averageScore;
  final int? totalEpisodes;
  final int? idMal;
  final MediaType type;

  MediaSearchResult({
    required this.id,
    required this.providerId,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.year,
    this.status,
    this.averageScore,
    this.totalEpisodes,
    this.idMal,
    this.type = MediaType.anime,
  });
}

class EpisodeManifest {
  final String id;
  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final bool isFiller;

  EpisodeManifest({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.overview,
    this.stillPath,
    this.airDate,
    this.isFiller = false,
  });
}

class SeriesManifest {
  final MediaSearchResult series;
  final List<EpisodeManifest> episodes;

  SeriesManifest({
    required this.series,
    required this.episodes,
  });
}

class FranchiseManifest {
  final List<SeriesManifest> entries;

  FranchiseManifest({required this.entries});
}