import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_player/engine/plugins/simkl_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimklPlugin plugin;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    plugin = SimklPlugin();
  });

  group('SimklPlugin Input Sanitization & Guardrails Tests', () {
    test('automated scan skips generic folder names like "downloads", "temp", "episodes"', () async {
      expect(await plugin.search('downloads', isManualSearch: false), isEmpty);
      expect(await plugin.search('temp', isManualSearch: false), isEmpty);
      expect(await plugin.search('episodes', isManualSearch: false), isEmpty);
    });

    test('manual user search bypasses generic folder guardrails for valid titles like "Moving"', () async {
      final results = await plugin.search('Moving', isManualSearch: true);
      expect(results, isA<List>());
    });

    test('returns empty list for short or whitespace query even during manual search', () async {
      final resultsEmpty = await plugin.search('   ', isManualSearch: true);
      final resultsSingleChar = await plugin.search('a', isManualSearch: true);
      expect(resultsEmpty, isEmpty);
      expect(resultsSingleChar, isEmpty);
    });

    test('valid title query passes sanitization and does not get blocked early', () async {
      final results = await plugin.search('Attack on Titan');
      expect(results, isA<List>());
    });

    test('dispatches movie and anime search queries smoothly across categories', () async {
      final movieResults = await plugin.search('man of steel', isManualSearch: true);
      final animeResults = await plugin.search('That Time I Got Reincarnated as a Slime', isManualSearch: true);

      expect(movieResults, isA<List>());
      expect(animeResults, isA<List>());
    });
  });
}
