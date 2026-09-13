import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/engine/metadata/media_tag_parser.dart';
import 'package:omni_player/engine/plugins/models/plugin_models.dart';

void main() {
  group('MediaTagParser Classification Tests', () {
    test('correctly classifies TV series', () {
      final classification = MediaTagParser.classify(
        title: 'Attack on Titan Season 1',
        rawFormat: 'TV',
        totalEpisodes: 25,
      );
      expect(classification, equals(MediaClassification.tvSeries));
    });

    test('correctly classifies Movies', () {
      final classification = MediaTagParser.classify(
        title: 'Demon Slayer: Mugen Train The Movie',
        rawFormat: 'MOVIE',
        totalEpisodes: 1,
      );
      expect(classification, equals(MediaClassification.movie));
    });

    test('correctly classifies OVAs', () {
      final classification = MediaTagParser.classify(
        title: 'Attack on Titan: Ilse\'s Notebook OVA',
        rawFormat: 'OVA',
        totalEpisodes: 1,
      );
      expect(classification, equals(MediaClassification.ova));
    });

    test('correctly classifies Specials', () {
      final classification = MediaTagParser.classify(
        title: 'My Hero Academia Picture Drama Special',
        rawFormat: 'SPECIAL',
        totalEpisodes: 1,
      );
      expect(classification, equals(MediaClassification.special));
    });

    test('correctly classifies Trailers / PVs from title keywords', () {
      final classification = MediaTagParser.classify(
        title: 'Chainsaw Man Official PV 1',
        rawFormat: 'PV',
        totalEpisodes: 1,
      );
      expect(classification, equals(MediaClassification.trailer));
    });

    test('MediaSearchResult automatically assigns classification via MediaTagParser', () {
      final result = MediaSearchResult(
        id: '123',
        providerId: 'anilist',
        title: 'Jujutsu Kaisen 0 Movie',
        rawFormat: 'MOVIE',
        totalEpisodes: 1,
      );
      expect(result.classification, equals(MediaClassification.movie));
    });
  });

  group('AiringStatus Parsing Tests', () {
    test('parses MAL finished_airing and finished airing as AiringStatus.aired', () {
      expect(MediaTagParser.parseAiringStatus(status: 'finished_airing'), equals(AiringStatus.aired));
      expect(MediaTagParser.parseAiringStatus(status: 'finished airing'), equals(AiringStatus.aired));
      expect(MediaTagParser.parseAiringStatus(status: 'FINISHED'), equals(AiringStatus.aired));
      expect(MediaTagParser.parseAiringStatus(status: 'ended'), equals(AiringStatus.aired));
    });

    test('parses MAL currently_airing and currently airing as AiringStatus.airing', () {
      expect(MediaTagParser.parseAiringStatus(status: 'currently_airing'), equals(AiringStatus.airing));
      expect(MediaTagParser.parseAiringStatus(status: 'currently airing'), equals(AiringStatus.airing));
      expect(MediaTagParser.parseAiringStatus(status: 'RELEASING'), equals(AiringStatus.airing));
    });

    test('parses MAL not_yet_aired and not yet aired as AiringStatus.upcoming', () {
      expect(MediaTagParser.parseAiringStatus(status: 'not_yet_aired'), equals(AiringStatus.upcoming));
      expect(MediaTagParser.parseAiringStatus(status: 'not yet aired'), equals(AiringStatus.upcoming));
      expect(MediaTagParser.parseAiringStatus(status: 'NOT_YET_RELEASED'), equals(AiringStatus.upcoming));
    });

    test('uses past end_date to evaluate AiringStatus.aired', () {
      final pastDate = '2020-09-28';
      expect(MediaTagParser.parseAiringStatus(endDate: pastDate), equals(AiringStatus.aired));
    });

    test('parses future release year as AiringStatus.upcoming', () {
      final futureYear = DateTime.now().year + 2;
      expect(MediaTagParser.parseAiringStatus(year: futureYear), equals(AiringStatus.upcoming));
    });

    test('MediaSearchResult automatically assigns airingStatus for MAL finished_airing', () {
      final item = MediaSearchResult(
        id: '1',
        providerId: 'mal',
        title: 'Fullmetal Alchemist: Brotherhood',
        status: 'finished_airing',
      );
      expect(item.airingStatus, equals(AiringStatus.aired));
    });
  });
}
