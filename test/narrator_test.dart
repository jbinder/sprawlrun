import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/services/narrator.dart';

void main() {
  group('voices handed to characters', () {
    Map<String, String> voice(String name, {String locale = 'en-US', bool network = false, String features = ''}) => {
      'name': name,
      'locale': locale,
      'network_required': network ? '1' : '0',
      'features': features,
    };

    test('only English ones that work offline and are installed', () {
      final usable = AudioNarrator.usableVoices([
        voice('en-us-x-sfg-local'),
        voice('en-us-x-sfg-network', network: true),
        voice('en-gb-x-rjs-local', locale: 'en-GB', features: 'networkTimeoutMs\tnotInstalled'),
        voice('de-de-x-nfh-local', locale: 'de-DE'),
        voice('en-au-x-aub-local', locale: 'en-AU', features: 'networkTimeoutMs\tnetworkRetriesCount'),
      ]).map((v) => v['name']);
      expect(usable, ['en-us-x-sfg-local', 'en-au-x-aub-local']);
    });
  });

  group('how long a line may take', () {
    test('outlasts the line at the speech rate it is spoken at', () {
      const line =
          'Seven years on file under Ossuary Row, in case anybody wants to sue you. Then the purge takes you. Every October.';
      // Roughly 14 characters a second at the engine's normal rate of 0.5.
      expect(AudioNarrator.speechBudget(line, 0.5), greaterThan(Duration(milliseconds: line.length * 1000 ~/ 14)));
      // The slowest voice at a slow setting still gets its time.
      expect(
        AudioNarrator.speechBudget(line, 0.15),
        greaterThan(Duration(milliseconds: (line.length * 1000 / 14 * 0.5 / 0.15).round())),
      );
    });

    test('is not open-ended', () {
      expect(AudioNarrator.speechBudget('x' * 180, 0.5), lessThan(const Duration(seconds: 30)));
    });
  });
}
