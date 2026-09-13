class TechnicalBadges {
  final String resolutionBadge;
  final String hdrBadge;
  final String fpsBadge;
  final String audioCodecBadge;
  final String audioChannelsBadge;
  final int audioTracksCount;
  final int subtitleTracksCount;

  TechnicalBadges({
    required this.resolutionBadge,
    required this.hdrBadge,
    required this.fpsBadge,
    required this.audioCodecBadge,
    required this.audioChannelsBadge,
    required this.audioTracksCount,
    required this.subtitleTracksCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'resolution_badge': resolutionBadge,
      'hdr_badge': hdrBadge,
      'fps_badge': fpsBadge,
      'audio_codec_badge': audioCodecBadge,
      'audio_channels_badge': audioChannelsBadge,
      'audio_tracks_count': audioTracksCount,
      'subtitle_tracks_count': subtitleTracksCount,
    };
  }

  factory TechnicalBadges.fromMap(Map<String, dynamic> map) {
    return TechnicalBadges(
      resolutionBadge: map['resolution_badge'] ?? "SD",
      hdrBadge: map['hdr_badge'] ?? "SDR",
      fpsBadge: map['fps_badge'] ?? "Unknown FPS",
      audioCodecBadge: map['audio_codec_badge'] ?? "Unknown",
      audioChannelsBadge: map['audio_channels_badge'] ?? "Stereo",
      audioTracksCount: map['audio_tracks_count'] ?? 0,
      subtitleTracksCount: map['subtitle_tracks_count'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'TechnicalBadges(res: $resolutionBadge, hdr: $hdrBadge, fps: $fpsBadge, audio: $audioCodecBadge ($audioChannelsBadge), aTracks: $audioTracksCount, sTracks: $subtitleTracksCount)';
  }
}
