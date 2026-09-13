import 'package:path/path.dart' as p;
import 'models/parsed_media_token.dart';

class FilenameTokenizer {
  static ParsedMediaToken parse(String fileName) {
    String name = p.basenameWithoutExtension(fileName);
    String raw = fileName;

    // 1. Extract and strip Release Group [Group]
    String? releaseGroup;
    final groupRegex = RegExp(r'^\[([^\]]+)\]');
    final groupMatch = groupRegex.firstMatch(name);
    if (groupMatch != null) {
      releaseGroup = groupMatch.group(1);
      name = name.replaceFirst(groupRegex, '').trim();
    }

    // 2. Detect Standard TV Format (S01E01)
    int? season;
    int? episode;
    final tvRegex = RegExp(r'[sS](\d+)[eE](\d+)');
    final tvMatch = tvRegex.firstMatch(name);
    bool isAnime = false;

    if (tvMatch != null) {
      season = int.tryParse(tvMatch.group(1) ?? '');
      episode = int.tryParse(tvMatch.group(2) ?? '');
      name = name.split(tvRegex).first.trim();
    } else {
      // 3. Detect Anime absolute format (e.g. "Title - 01" or "Title 01")
      final animeRegex = RegExp(r'-\s*(\d+)');
      final animeMatch = animeRegex.firstMatch(name);
      if (animeMatch != null) {
        episode = int.tryParse(animeMatch.group(1) ?? '');
        name = name.split(animeRegex).first.trim();
        isAnime = true;
      } else {
        final simpleEpRegex = RegExp(r'(?:\s|_|^)(\d{2,3})(?:\s|_|\[|$)');
        final simpleMatch = simpleEpRegex.firstMatch(name);
        if (simpleMatch != null) {
          episode = int.tryParse(simpleMatch.group(1) ?? '');
          // Don't strip here as it might be part of the title (e.g. "2012")
          // But we flag it as anime convention if it looks like a standalone number
          isAnime = true;
        }
      }
    }

    // 4. Extract Resolution
    String? resolution;
    final resRegex = RegExp(r'(4K|2160p|1080p|720p|480p|SD)', caseSensitive: false);
    final resMatch = resRegex.firstMatch(name);
    if (resMatch != null) {
      resolution = resMatch.group(0);
    }

    // 5. Strip common technical tags
    final tagsToStrip = [
      RegExp(r'x264|x265|HEVC|AVC|10bit|12bit', caseSensitive: false),
      RegExp(r'AAC|DTS|FLAC|TrueHD|Atmos|AC3', caseSensitive: false),
      RegExp(r'WEBRip|WEB-DL|BluRay|BDRip|DVDRip', caseSensitive: false),
      RegExp(r'Dual-Audio|Multi-Subs', caseSensitive: false),
      resRegex,
    ];

    String cleanTitle = name;
    for (var tag in tagsToStrip) {
      cleanTitle = cleanTitle.replaceAll(tag, '');
    }

    // 6. Final cleanup: Replace dots and underscores, collapse spaces
    cleanTitle = cleanTitle
        .replaceAll(RegExp(r'[.\-_]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return ParsedMediaToken(
      rawFileName: raw,
      cleanTitle: cleanTitle,
      seasonNumber: season,
      episodeNumber: episode,
      releaseGroup: releaseGroup,
      resolutionTag: resolution,
      isAnimeConvention: isAnime,
    );
  }
}
