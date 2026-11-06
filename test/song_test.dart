import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/audio/song.dart';
import 'package:sprawl_run/audio/song_stream.dart';

String shipped(String id) => File('assets/songs/$id.json').readAsStringSync();

/// A small valid song, for breaking one thing at a time.
Map<String, dynamic> minimal() => {
  'format': 1,
  'id': 'test',
  'name': 'Test',
  'bpm': 170,
  'seed': 1,
  'bars': 2,
  'loopFrom': 0,
  'buses': [
    {'id': 'dry'},
  ],
  'patterns': {
    'kick': [
      {'hits': 'x...x...x...x...'},
    ],
    'tune': [
      {
        'phrase': [
          ['c4', 2],
          [null, 2],
        ],
      },
    ],
  },
  'tracks': [
    {
      'id': 'kick',
      'bus': 'dry',
      'voice': {'type': 'drum', 'drum': 'kick'},
      'clips': [
        {'from': 0, 'to': 2, 'pattern': 'kick'},
      ],
    },
    {
      'id': 'tune',
      'bus': 'dry',
      'voice': {'type': 'saw', 'release': 1},
      'clips': [
        {'from': 0, 'to': 2, 'pattern': 'tune'},
      ],
    },
  ],
};

void main() {
  group('every shipped song', () {
    final files = Directory('assets/songs').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));

    test('there is at least one', () => expect(files, isNotEmpty));

    for (final file in files) {
      final name = file.uri.pathSegments.last;

      test('$name parses, under the name of its file', () {
        final song = Song.parse(file.readAsStringSync());
        expect('${song.id}.json', name);
        expect(song.author, isNotNull, reason: 'a shipped song credits who wrote it');
      });

      test('$name makes sound within limits', () {
        final stream = SongStream(Song.parse(file.readAsStringSync()), fromBar: 24);
        var peak = 0.0;
        for (var n = 0; n < 4; n++) {
          final bar = stream.nextBar();
          for (final sample in bar.left) {
            expect(sample.isFinite, isTrue);
            if (sample.abs() > peak) peak = sample.abs();
          }
        }
        expect(peak, greaterThan(0.1));
        expect(peak, lessThanOrEqualTo(1.0));
      });
    }
  });

  group('Neon Pursuit', () {
    final song = Song.parse(shipped('neon_pursuit'));

    test('loops into the drive and not the intro', () {
      expect(song.songBar(79), 79);
      expect(song.songBar(80), 8);
      expect(song.songBar(151), 79);
      expect(song.songBar(152), 8);
    });

    test('hits the bar length its tempo implies', () {
      final bar = SongStream(song).nextBar();
      expect(bar.seconds, closeTo(4 * 60 / 170, 0.001));
    });

    test('renders the same samples every time', () {
      final a = SongStream(song, fromBar: 40), b = SongStream(song, fromBar: 40);
      for (var n = 0; n < 3; n++) {
        expect(a.nextBar().left, b.nextBar().left);
      }
    });

    test('keeps going past the end of its first pass', () {
      final stream = SongStream(song, fromBar: 78);
      for (var n = 0; n < 4; n++) {
        expect(stream.nextBar().left, isNotEmpty);
      }
    });
  });

  group('a song file is checked', () {
    Matcher fails(String message) =>
        throwsA(isA<SongFormatException>().having((e) => e.message, 'message', contains(message)));

    Song parse(void Function(Map<String, dynamic>) change) {
      final json = minimal();
      change(json);
      return Song.parse(jsonEncode(json));
    }

    test('the minimal song is fine', () => expect(parse((_) {}).id, 'test'));

    test('text that is not JSON is refused', () {
      expect(() => Song.parse('not json'), fails('not JSON'));
      expect(() => Song.parse('[]'), fails('not a song'));
    });

    test('a very large file is refused', () {
      expect(() => Song.parse(' ' * (Song.maxBytes + 1)), fails('too large'));
    });

    test('a newer format asks for a newer app', () {
      expect(() => parse((j) => j['format'] = 2), fails('newer version'));
    });

    test('an id that could not be a file name is refused', () {
      expect(() => parse((j) => j['id'] = '../evil'), fails('Bad id'));
    });

    test('values outside their range are refused', () {
      expect(() => parse((j) => j['bpm'] = 1000), fails('"bpm"'));
      expect(() => parse((j) => j['bars'] = 100000), fails('"bars"'));
    });

    test('only known voices, drums and effects are accepted', () {
      expect(
        () => parse((j) => (j['tracks'] as List).first['voice'] = {'type': 'script'}),
        fails('Unknown voice'),
      );
      expect(
        () => parse((j) => (j['tracks'] as List).first['voice'] = {'type': 'drum', 'drum': 'cowbell'}),
        fails('Unknown drum'),
      );
      expect(
        () => parse(
          (j) => j['buses'] = [
            {
              'id': 'dry',
              'effects': [
                {'type': 'distortion'},
              ],
            },
          ],
        ),
        fails('Unknown effect'),
      );
    });

    test('a reverb must come last on its bus', () {
      expect(
        () => parse(
          (j) => j['buses'] = [
            {
              'id': 'dry',
              'effects': [
                {'type': 'reverb', 'room': 0.5, 'damp': 0.5, 'mix': 0.5},
                {'type': 'echo', 'phase': 1, 'decay': 2, 'mix': 0.5},
              ],
            },
          ],
        ),
        fails('must come last'),
      );
    });

    test('a track must name a bus and pattern that exist', () {
      expect(() => parse((j) => (j['tracks'] as List).first['bus'] = 'nope'), fails('unknown bus'));
      expect(
        () => parse((j) => (j['tracks'] as List).first['clips'].first['pattern'] = 'nope'),
        fails('unknown pattern'),
      );
    });

    test('a synth can not play drum hits, nor a drum play notes', () {
      expect(
        () => parse((j) => (j['tracks'] as List).first['clips'].first['pattern'] = 'tune'),
        fails('drums use hits'),
      );
    });

    test('a bad note is refused', () {
      expect(
        () => parse((j) => j['patterns']['tune'] = [
          {'chord': ['h4']},
        ]),
        fails('Bad note'),
      );
    });

    test('a pattern that overruns its bar is refused', () {
      expect(
        () => parse((j) => j['patterns']['kick'] = [
          {'hits': 'x' * 17},
        ]),
        fails('runs past'),
      );
    });

    test('a note too long for a bus is refused', () {
      expect(
        () => parse((j) => (j['tracks'] as List)[1]['voice'] = {'type': 'saw', 'release': 60}),
        fails('longer than'),
      );
    });

    test('notes with accidentals are read as Sonic Pi reads them', () {
      final song = parse((j) => j['patterns']['tune'] = [
        {'chord': ['a4', 'c#4', 'eb3']},
      ]);
      final notes = song.tracks[1].clips.first.pattern.at(0).map((e) => e.note);
      expect(notes, [69, 61, 51]);
    });
  });
}
