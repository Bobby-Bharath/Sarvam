enum MediaClassification {
  tvSeries,
  movie,
  ova,
  special,
  trailer,
}

enum AiringStatus {
  airing,
  aired,
  upcoming,
  unknown,
}

extension MediaClassificationExt on MediaClassification {
  String get label {
    switch (this) {
      case MediaClassification.tvSeries:
        return 'TV Series';
      case MediaClassification.movie:
        return 'Movie';
      case MediaClassification.ova:
        return 'OVA / ONA';
      case MediaClassification.special:
        return 'Special';
      case MediaClassification.trailer:
        return 'Trailer / PV';
    }
  }

  String get shortCode {
    switch (this) {
      case MediaClassification.tvSeries:
        return 'TV';
      case MediaClassification.movie:
        return 'MOVIE';
      case MediaClassification.ova:
        return 'OVA';
      case MediaClassification.special:
        return 'SPECIAL';
      case MediaClassification.trailer:
        return 'TRAILER';
    }
  }
}

extension AiringStatusExt on AiringStatus {
  String get label {
    switch (this) {
      case AiringStatus.airing:
        return 'Currently Airing';
      case AiringStatus.aired:
        return 'Finished / Aired';
      case AiringStatus.upcoming:
        return 'Upcoming';
      case AiringStatus.unknown:
        return 'Unknown Status';
    }
  }

  String get shortCode {
    switch (this) {
      case AiringStatus.airing:
        return 'AIRING';
      case AiringStatus.aired:
        return 'AIRED';
      case AiringStatus.upcoming:
        return 'UPCOMING';
      case AiringStatus.unknown:
        return 'UNKNOWN';
    }
  }
}

class MediaTagParser {
  static MediaClassification classify({
    required String title,
    String? originalTitle,
    String? rawFormat,
    int? totalEpisodes,
    String? overview,
  }) {
    final titleLower = title.toLowerCase();
    final origLower = (originalTitle ?? '').toLowerCase();
    final fmtLower = (rawFormat ?? '').toLowerCase();

    // 1. Check for Trailer / PV / Teaser patterns in title or rawFormat
    if (fmtLower == 'pv' ||
        fmtLower == 'trailer' ||
        fmtLower == 'promo' ||
        RegExp(r'\b(trailer|pv\b|\bpv\d+|teaser|promo|promotional\s+video|preview)\b', caseSensitive: false).hasMatch(titleLower) ||
        RegExp(r'\b(trailer|pv\b|\bpv\d+|teaser|promo|preview)\b', caseSensitive: false).hasMatch(origLower)) {
      return MediaClassification.trailer;
    }

    // 2. Check for Special / SP patterns
    if (fmtLower == 'special' ||
        fmtLower == 'sp' ||
        RegExp(r'\b(special|specials|\bsp\b|\bsp\d+)\b', caseSensitive: false).hasMatch(titleLower)) {
      return MediaClassification.special;
    }

    // 3. Check for Movie patterns
    if (fmtLower == 'movie' ||
        fmtLower == 'cinema' ||
        RegExp(r'\b(movie|theatrical|film)\b', caseSensitive: false).hasMatch(titleLower) ||
        (fmtLower == 'movie' && totalEpisodes == 1)) {
      return MediaClassification.movie;
    }

    // 4. Check for OVA / ONA / OAD
    if (fmtLower == 'ova' ||
        fmtLower == 'ona' ||
        fmtLower == 'oad' ||
        fmtLower == 'tv_short' ||
        RegExp(r'\b(ova|ona|oad)\b', caseSensitive: false).hasMatch(titleLower)) {
      return MediaClassification.ova;
    }

    // 5. Check for TV Series
    if (fmtLower == 'tv' ||
        fmtLower == 'show' ||
        fmtLower == 'series' ||
        fmtLower == 'anime' ||
        (totalEpisodes != null && totalEpisodes > 1)) {
      return MediaClassification.tvSeries;
    }

    // Default fallback based on episode count
    if (totalEpisodes == 1) {
      return MediaClassification.movie;
    }

    return MediaClassification.tvSeries;
  }

  static AiringStatus parseAiringStatus({
    String? status,
    int? year,
    String? endDate,
  }) {
    if (status != null && status.isNotEmpty) {
      final s = status.toLowerCase().trim();

      // 1. Check Upcoming FIRST (handles "not_yet_aired", "not_yet_released", "upcoming", "unreleased")
      if (s == 'not_yet_aired' ||
          s == 'not yet aired' ||
          s == 'not_yet_released' ||
          s == 'not yet released' ||
          s.contains('not_yet') ||
          s.contains('not yet') ||
          s.contains('upcoming') ||
          s.contains('unreleased') ||
          s.contains('cancelled') ||
          s.contains('in development')) {
        return AiringStatus.upcoming;
      }

      // 2. Check Finished / Aired SECOND (handles MAL's "finished_airing" or "finished airing")
      if (s == 'finished_airing' ||
          s == 'finished airing' ||
          s == 'finished' ||
          s.contains('finished') ||
          s.contains('ended') ||
          s.contains('completed') ||
          s.contains('released')) {
        return AiringStatus.aired;
      }

      // 3. Check Currently Airing THIRD (handles MAL's "currently_airing" or "currently airing")
      if (s == 'currently_airing' ||
          s == 'currently airing' ||
          s.contains('releasing') ||
          s.contains('currently') ||
          s.contains('airing') ||
          s.contains('current') ||
          s.contains('running')) {
        return AiringStatus.airing;
      }
    }

    // Defensive check against end_date
    if (endDate != null && endDate.isNotEmpty) {
      final endDt = DateTime.tryParse(endDate);
      if (endDt != null && endDt.isBefore(DateTime.now())) {
        return AiringStatus.aired;
      }
    }

    if (year != null) {
      final currentYear = DateTime.now().year;
      if (year > currentYear) return AiringStatus.upcoming;
    }

    return AiringStatus.unknown;
  }
}
