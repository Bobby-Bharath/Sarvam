class ParsedMediaToken {
  final String rawFileName;
  final String cleanTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? releaseGroup;
  final String? resolutionTag;
  final bool isAnimeConvention;

  ParsedMediaToken({
    required this.rawFileName,
    required this.cleanTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.releaseGroup,
    this.resolutionTag,
    required this.isAnimeConvention,
  });

  String get formattedDisplayTitle {
    if (seasonNumber != null && episodeNumber != null) {
      return 'S${seasonNumber.toString().padLeft(2, '0')} E${episodeNumber.toString().padLeft(2, '0')}';
    } else if (episodeNumber != null) {
      return 'Episode $episodeNumber';
    }
    return cleanTitle;
  }

  @override
  String toString() {
    return 'ParsedToken(title: $cleanTitle, S: $seasonNumber, E: $episodeNumber, group: $releaseGroup, res: $resolutionTag, anime: $isAnimeConvention)';
  }
}
