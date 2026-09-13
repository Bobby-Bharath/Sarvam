class Episode {
  final String id;
  final String mediaEntityId;
  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final bool isFiller;
  final String episodeType; // 'CANON', 'FILLER', 'RECAP', 'SPECIAL'

  // Joined fields from SQLite `local_files` table
  final String? filePath;
  final int? fileSize;
  final int durationMs;
  final int progressMs;
  final String watchState; // 'UNWATCHED', 'WATCHING', 'WATCHED'

  const Episode({
    required this.id,
    required this.mediaEntityId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.overview,
    this.stillPath,
    this.airDate,
    this.isFiller = false,
    this.episodeType = 'CANON',
    this.filePath,
    this.fileSize,
    this.durationMs = 0,
    this.progressMs = 0,
    this.watchState = 'UNWATCHED',
  });

  bool get isDownloaded => filePath != null && filePath!.isNotEmpty;
  bool get isWatched => watchState == 'WATCHED';
  bool get isWatching => watchState == 'WATCHING' || (progressMs > 0 && !isWatched);

  double get progressRatio {
    if (durationMs <= 0) return 0.0;
    return (progressMs / durationMs).clamp(0.0, 1.0);
  }

  factory Episode.fromMap(Map<String, dynamic> map) {
    final rawFiller = map['is_filler'];
    final bool parsedIsFiller = rawFiller == 1 ||
        rawFiller == true ||
        rawFiller?.toString() == '1' ||
        map['episode_type']?.toString().toUpperCase() == 'FILLER';

    return Episode(
      id: map['id']?.toString() ?? '',
      mediaEntityId: map['media_entity_id']?.toString() ?? '',
      seasonNumber: map['season_number'] is int
          ? map['season_number']
          : int.tryParse(map['season_number']?.toString() ?? '') ?? 1,
      episodeNumber: map['episode_number'] is int
          ? map['episode_number']
          : int.tryParse(map['episode_number']?.toString() ?? '') ?? 1,
      title: map['title']?.toString(),
      overview: map['overview']?.toString(),
      stillPath: map['still_path']?.toString(),
      airDate: map['air_date']?.toString(),
      isFiller: parsedIsFiller,
      episodeType: map['episode_type']?.toString().toUpperCase() ?? (parsedIsFiller ? 'FILLER' : 'CANON'),
      filePath: map['file_path']?.toString(),
      fileSize: map['file_size'] is int ? map['file_size'] : int.tryParse(map['file_size']?.toString() ?? ''),
      durationMs: map['duration_ms'] is int
          ? map['duration_ms']
          : int.tryParse(map['duration_ms']?.toString() ?? '') ?? 0,
      progressMs: map['progress_ms'] is int
          ? map['progress_ms']
          : int.tryParse(map['progress_ms']?.toString() ?? '') ?? 0,
      watchState: map['watch_state']?.toString() ?? 'UNWATCHED',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'media_entity_id': mediaEntityId,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      'title': title,
      'overview': overview,
      'still_path': stillPath,
      'air_date': airDate,
      'is_filler': isFiller ? 1 : 0,
      'episode_type': episodeType,
    };
  }

  Episode copyWith({
    String? id,
    String? mediaEntityId,
    int? seasonNumber,
    int? episodeNumber,
    String? title,
    String? overview,
    String? stillPath,
    String? airDate,
    bool? isFiller,
    String? episodeType,
    String? filePath,
    int? fileSize,
    int? durationMs,
    int? progressMs,
    String? watchState,
  }) {
    return Episode(
      id: id ?? this.id,
      mediaEntityId: mediaEntityId ?? this.mediaEntityId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      stillPath: stillPath ?? this.stillPath,
      airDate: airDate ?? this.airDate,
      isFiller: isFiller ?? this.isFiller,
      episodeType: episodeType ?? this.episodeType,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      durationMs: durationMs ?? this.durationMs,
      progressMs: progressMs ?? this.progressMs,
      watchState: watchState ?? this.watchState,
    );
  }
}