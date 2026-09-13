class MediaEntity {
  final String id;
  final String franchiseId;
  final String displayProvider;
  final String title;
  final String? originalTitle;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final int? year;
  final String? startDate;
  final String? status;
  final double? averageScore;
  final String? subtype;
  final int? totalEpisodes;
  final int? anilistId;
  final int? idMal;
  final int? simklId;
  final String? folderPath;
  final bool allowSync;
  final bool isManualMatch;

  const MediaEntity({
    required this.id,
    required this.franchiseId,
    required this.displayProvider,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.year,
    this.startDate,
    this.status,
    this.averageScore,
    this.subtype,
    this.totalEpisodes,
    this.anilistId,
    this.idMal,
    this.simklId,
    this.folderPath,
    this.allowSync = true,
    this.isManualMatch = false,
  });

  String get displayTitle => title.isNotEmpty ? title : (originalTitle ?? 'Unknown Series');

  factory MediaEntity.fromMap(Map<String, dynamic> map) {
    return MediaEntity(
      id: map['id']?.toString() ?? '',
      franchiseId: map['franchise_id']?.toString() ?? map['id']?.toString() ?? '',
      displayProvider: map['display_provider']?.toString() ?? 'ANILIST',
      title: map['title']?.toString() ?? '',
      originalTitle: map['original_title']?.toString(),
      posterUrl: map['poster_url']?.toString(),
      backdropUrl: map['backdrop_url']?.toString(),
      overview: map['overview']?.toString(),
      year: map['year'] is int ? map['year'] : int.tryParse(map['year']?.toString() ?? ''),
      startDate: map['start_date']?.toString(),
      status: map['status']?.toString(),
      averageScore: map['average_score'] is num
          ? (map['average_score'] as num).toDouble()
          : double.tryParse(map['average_score']?.toString() ?? ''),
      subtype: map['subtype']?.toString() ?? 'TV',
      totalEpisodes: map['total_episodes'] is int
          ? map['total_episodes']
          : int.tryParse(map['total_episodes']?.toString() ?? ''),
      anilistId: map['anilist_id'] is int
          ? map['anilist_id']
          : int.tryParse(map['anilist_id']?.toString() ?? ''),
      idMal: map['id_mal'] is int
          ? map['id_mal']
          : int.tryParse(map['id_mal']?.toString() ?? ''),
      simklId: map['simkl_id'] is int
          ? map['simkl_id']
          : int.tryParse(map['simkl_id']?.toString() ?? ''),
      folderPath: map['folder_path']?.toString(),
      allowSync: map['allow_sync'] == 1 || map['allow_sync'] == true,
      isManualMatch: map['is_manual_match'] == 1 || map['is_manual_match'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'franchise_id': franchiseId,
      'display_provider': displayProvider,
      'title': title,
      'original_title': originalTitle,
      'poster_url': posterUrl,
      'backdrop_url': backdropUrl,
      'overview': overview,
      'year': year,
      'start_date': startDate,
      'status': status,
      'average_score': averageScore,
      'subtype': subtype,
      'total_episodes': totalEpisodes,
      'anilist_id': anilistId,
      'id_mal': idMal,
      'simkl_id': simklId,
      'folder_path': folderPath,
      'allow_sync': allowSync ? 1 : 0,
      'is_manual_match': isManualMatch ? 1 : 0,
    };
  }

  MediaEntity copyWith({
    String? id,
    String? franchiseId,
    String? displayProvider,
    String? title,
    String? originalTitle,
    String? posterUrl,
    String? backdropUrl,
    String? overview,
    int? year,
    String? startDate,
    String? status,
    double? averageScore,
    String? subtype,
    int? totalEpisodes,
    int? anilistId,
    int? idMal,
    int? simklId,
    String? folderPath,
    bool? allowSync,
    bool? isManualMatch,
  }) {
    return MediaEntity(
      id: id ?? this.id,
      franchiseId: franchiseId ?? this.franchiseId,
      displayProvider: displayProvider ?? this.displayProvider,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      overview: overview ?? this.overview,
      year: year ?? this.year,
      startDate: startDate ?? this.startDate,
      status: status ?? this.status,
      averageScore: averageScore ?? this.averageScore,
      subtype: subtype ?? this.subtype,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      anilistId: anilistId ?? this.anilistId,
      idMal: idMal ?? this.idMal,
      simklId: simklId ?? this.simklId,
      folderPath: folderPath ?? this.folderPath,
      allowSync: allowSync ?? this.allowSync,
      isManualMatch: isManualMatch ?? this.isManualMatch,
    );
  }
}