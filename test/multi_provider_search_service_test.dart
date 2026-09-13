import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_player/engine/services/multi_provider_search_service.dart';
import 'package:omni_player/engine/plugins/plugin_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MultiProviderSearchService Tests', () {
    test('returns empty group when query or provider list is empty', () async {
      final service = MultiProviderSearchService.instance;
      
      final emptyQueryGroup = await service.searchAll(
        query: '   ',
        providerIds: ['anilist', 'kitsu'],
        category: MediaCategory.anime,
      );
      expect(emptyQueryGroup.allResults, isEmpty);

      final emptyProvidersGroup = await service.searchAll(
        query: 'Attack on Titan',
        providerIds: [],
        category: MediaCategory.anime,
      );
      expect(emptyProvidersGroup.allResults, isEmpty);
    });

    test('executes parallel queries and handles invalid/unregistered providers gracefully', () async {
      final service = MultiProviderSearchService.instance;

      final group = await service.searchAll(
        query: 'Naruto',
        providerIds: ['invalid_provider', 'kitsu', 'simkl'],
        category: MediaCategory.anime,
      );

      // Should complete without throwing exceptions
      expect(group, isNotNull);
      expect(group.providerResults, contains('invalid_provider'));
    });
  });
}
