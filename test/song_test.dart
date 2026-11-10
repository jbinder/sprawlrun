import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/audio/song.dart';
import 'package:sprawl_run/audio/song_stream.dart';
import 'package:sprawl_run/audio/synth/drums.dart';
import 'package:sprawl_run/audio/synth/dsp.dart';
import 'package:sprawl_run/audio/synth/effects.dart';
import 'package:sprawl_run/audio/synth/voices.dart';

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

/// What each shipped song sounds like, as a fingerprint: eight bars from bar 24,
/// four at high and four at low, as the 16-bit samples written to the speaker.
const _sounds = {
  'black_ice.json': 0x5f51c5e0,
  'cold_boot.json': 0xb73c43c1,
  'neon_pursuit.json': 0x0762f46c,
  'skyline_breach.json': 0xa9bd7ac6,
  'sodium_rain.json': 0xd898ca39,
  'undercity.json': 0xcae55e1e,
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

      test('$name has something playing in every section at low', () {
        // True by itself of a song that names no levels, since it always plays.
        final song = Song.parse(file.readAsStringSync());
        for (var i = 0; i < song.sections.length; i++) {
          final from = song.sections[i].from;
          final to = i + 1 < song.sections.length ? song.sections[i + 1].from : song.bars;
          final playing = [
            for (final t in song.tracks)
              if (t.level == MusicLevel.low && t.clips.any((c) => c.from < to && c.to > from)) t.id,
          ];
          expect(playing, isNotEmpty, reason: '${song.sections[i].name} would be silent at low');
        }
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

      // What the phone plays, pinned. A synth's sound is part of the format, so
      // making the synth faster must leave these alone; a change that moves one
      // is a change to every runner's song and needs a new format number.
      test('$name sounds as it always has', () {
        final stream = SongStream(Song.parse(file.readAsStringSync()), fromBar: 24, level: MusicLevel.high);
        var hash = 0x811c9dc5;
        for (var i = 0; i < 8; i++) {
          if (i == 4) stream.setLevel(MusicLevel.low, atOnce: true);
          final bar = stream.nextBar();
          for (final channel in [bar.left, bar.right]) {
            for (final x in channel) {
              final v = (x * 32767).round() & 0xffff;
              hash = ((hash ^ (v & 0xff)) * 0x01000193) & 0xffffffff;
              hash = ((hash ^ (v >> 8)) * 0x01000193) & 0xffffffff;
            }
          }
        }
        expect(hash, _sounds[name], reason: 'a new song needs its value added here');
      });
    }
  });

  group('Neon Pursuit', () {
    final song = Song.parse(shipped('neon_pursuit'));

    test('loops into the drive and not the intro', () {
      expect(song.songBar(song.bars - 1), song.bars - 1);
      expect(song.songBar(song.bars), 8);
      expect(song.songBar(song.bars * 2 - 9), song.bars - 1);
      expect(song.songBar(song.bars * 2 - 8), 8);
    });

    test('hits the bar length its tempo implies', () {
      final bar = SongStream(song).nextBar();
      expect(bar.seconds, closeTo(4 * 60 / 170, 0.001));
    });

    group('levels', () {
      List<double> bars(Song song, int from, int count, {MusicLevel level = MusicLevel.normal, void Function(SongStream, int)? each}) {
        final stream = SongStream(song, fromBar: from, level: level);
        return [
          for (var n = 0; n < count; n++) ...() {
            each?.call(stream, n);
            return stream.nextBar().left;
          }(),
        ];
      }

      double energy(List<double> samples) => samples.fold(0.0, (sum, x) => sum + x * x);

      final source = File('assets/songs/neon_pursuit.json').readAsStringSync();

      test('normal is the song without its high layers, sample for sample', () {
        final json = jsonDecode(source) as Map<String, dynamic>;
        (json['tracks'] as List).removeWhere((t) => (t as Map)['level'] == 'high');
        final without = Song.parse(jsonEncode(json));
        expect(bars(Song.parse(source), 24, 6), bars(without, 24, 6));
      });

      test('the high layer can be heard, and low takes away from the hook', () {
        // Measured on what the layer adds and not on loudness: the kick already
        // drives the limiter, so a louder mix barely reads as one. A first version
        // of this layer was all but silent, its notes eaten by the synths' 20 ms.
        // At the song's own tempo, so the two line up sample by sample.
        final song = Song.parse(jsonEncode((jsonDecode(source) as Map<String, dynamic>)..remove('highTempo')));
        final normal = bars(song, 24, 4);
        final high = bars(song, 24, 4, level: MusicLevel.high);
        final added = [for (var i = 0; i < normal.length; i++) high[i] - normal[i]];
        expect(energy(added), greaterThan(energy(normal) * 0.05));
        expect(energy(bars(song, 24, 4, level: MusicLevel.low)), lessThan(energy(normal)));
      });

      group('slowing at low', () {
        int barLength(SongStream stream) => stream.nextBar().left.length;

        test('glides down 2% a bar, and holds', () {
          final song = Song.parse(source);
          final stream = SongStream(song, fromBar: 24)..setLevel(MusicLevel.low);
          final normal = (song.secondsPerBeat * beatsPerBar * 44100).round();
          final steps = ((1 - song.lowTempo) / 0.02).round();
          final lengths = [for (var n = 0; n < steps + 2; n++) barLength(stream)];
          for (var n = 1; n < steps; n++) {
            expect(lengths[n], greaterThan(lengths[n - 1]));
          }
          expect(lengths[0], greaterThan(normal));
          expect(lengths[steps - 1], closeTo(normal / song.lowTempo, 2));
          expect(lengths[steps + 1], closeTo(lengths[steps - 1], 1));
        });

        test('comes back to the song\'s own tempo', () {
          final song = Song.parse(source);
          final stream = SongStream(song, fromBar: 24, level: MusicLevel.low);
          final slow = barLength(stream);
          stream.setLevel(MusicLevel.normal);
          for (var n = 0; n < 12; n++) {
            stream.nextBar();
          }
          expect(barLength(stream), closeTo((song.secondsPerBeat * beatsPerBar * 44100).round(), 1));
          expect(slow, greaterThan(barLength(stream)));
        });

        test('a chase does not wait for the glide', () {
          final song = Song.parse(source);
          final stream = SongStream(song, fromBar: 25, level: MusicLevel.low);
          stream.nextBar();
          stream.setLevel(MusicLevel.high, atOnce: true);
          expect(barLength(stream), closeTo((song.secondsPerBeat * beatsPerBar * 44100).round(), 1));
        });

        test('a song that names no other tempos keeps its own', () {
          final json = jsonDecode(source) as Map<String, dynamic>
            ..remove('lowTempo')
            ..remove('highTempo');
          final song = Song.parse(jsonEncode(json));
          final normal = barLength(SongStream(song, fromBar: 24));
          expect(barLength(SongStream(song, fromBar: 24, level: MusicLevel.low)), normal);
          expect(barLength(SongStream(song, fromBar: 24, level: MusicLevel.high)), normal);
        });

        test('high glides up over four bars, and holds', () {
          final song = Song.parse(source);
          final stream = SongStream(song, fromBar: 24)..setLevel(MusicLevel.high);
          final normal = (song.secondsPerBeat * beatsPerBar * 44100).round();
          final lengths = [for (var n = 0; n < 6; n++) barLength(stream)];
          expect(lengths[0], lessThan(normal));
          for (var n = 1; n < 4; n++) {
            expect(lengths[n], lessThan(lengths[n - 1]));
          }
          expect(lengths[3], closeTo(normal / song.highTempo, 2));
          expect(lengths[5], closeTo(lengths[3], 1));
        });

        test('a chase from low is back at the song\'s tempo at once, and glides on up', () {
          final song = Song.parse(source);
          final normal = (song.secondsPerBeat * beatsPerBar * 44100).round();
          final stream = SongStream(song, fromBar: 25, level: MusicLevel.low);
          stream.nextBar();
          stream.setLevel(MusicLevel.high, atOnce: true);
          expect(barLength(stream), closeTo(normal, 1));
          expect(barLength(stream), lessThan(normal));
        });

        test('the echo stays on the beat at another tempo', () {
          int arrival(double samplesPerBeat) {
            final echo = Echo(secondsPerBeat: 0.5, phaseBeats: 0.5, decayBeats: 2, mix: 1)
              ..setSamplesPerBeat(samplesPerBeat);
            // Long enough for the delay to settle before anything goes in.
            echo.process(Float32List(100000), 100000);
            final bus = Float32List(40000)..[0] = 1;
            echo.process(bus, bus.length);
            for (var i = 1; i < bus.length; i++) {
              if (bus[i] > 0.01) return i;
            }
            return -1;
          }

          const beat = 0.5 * 44100;
          expect(arrival(beat), (beat / 2).round());
          expect(arrival(beat / 1.08), (beat / 1.08 / 2).round());
          expect(arrival(beat / 0.88), (beat / 0.88 / 2).round());
        });
      });

      test('levels are optional: without them a song is the same at every level', () {
        final json = jsonDecode(source) as Map<String, dynamic>
          ..remove('lowTempo')
          ..remove('highTempo');
        for (final track in (json['tracks'] as List).cast<Map<String, dynamic>>()) {
          track.remove('level');
        }
        final song = Song.parse(jsonEncode(json));
        final normal = bars(song, 24, 3);
        expect(bars(song, 24, 3, level: MusicLevel.low), normal);
        expect(bars(song, 24, 3, level: MusicLevel.high), normal);
      });

      test('a change waits for the next phrase, unless it is asked for at once', () {
        final song = Song.parse(source);
        final plain = bars(song, 24, 4);
        // Bar 25 is inside a phrase that started on 24, and 28 starts the next.
        final late = bars(song, 24, 4, each: (s, n) {
          if (n == 1) s.setLevel(MusicLevel.high);
        });
        expect(late, plain, reason: 'nothing changes before bar 28');

        final atOnce = bars(song, 24, 4, each: (s, n) {
          if (n == 1) s.setLevel(MusicLevel.high, atOnce: true);
        });
        expect(atOnce, isNot(plain));
      });
    });

    test('renders the same samples every time', () {
      final a = SongStream(song, fromBar: 40), b = SongStream(song, fromBar: 40);
      for (var n = 0; n < 3; n++) {
        expect(a.nextBar().left, b.nextBar().left);
      }
    });

    test('keeps going past the end of its first pass', () {
      final stream = SongStream(song, fromBar: song.bars - 2);
      for (var n = 0; n < 4; n++) {
        expect(stream.nextBar().left, isNotEmpty);
      }
    });
  });

  group('a sequence of songs', () {
    Song named(String id, int bars) {
      final json = minimal()
        ..['id'] = id
        ..['bars'] = bars
        ..['loopFrom'] = 0;
      return Song.parse(jsonEncode(json));
    }

    test('one song just repeats, as a stream does', () {
      final song = named('a', 2);
      final sequence = SongSequence([song]);
      final stream = SongStream(song);
      for (var n = 0; n < 6; n++) {
        expect(sequence.nextBar().left, stream.nextBar().left);
      }
    });

    test('plays each through, rings out, hands over, and goes round', () {
      final sequence = SongSequence([named('a', 2), named('b', 2)]);
      final seen = <String>[];
      for (var n = 0; n < 8; n++) {
        sequence.nextBar();
        seen.add(sequence.current.id);
      }
      // Two bars of a, its ring-out, two of b, its ring-out, then a again.
      expect(seen, ['a', 'a', 'a', 'b', 'b', 'b', 'a', 'a']);
    });

    test('a ring-out fades to nothing and starts nothing new', () {
      final stream = SongStream(named('a', 2));
      stream.nextBar();
      expect(stream.firstPassDone, isFalse);
      stream.nextBar();
      expect(stream.firstPassDone, isTrue);
      final tail = stream.ringOut();
      expect(tail.left.last.abs(), lessThan(0.01));
    });

    test('the level carries over to the next song', () {
      final source = File('assets/songs/neon_pursuit.json').readAsStringSync();
      final high = Song.parse(source);
      final short = named('a', 2);
      final sequence = SongSequence([short, high])..setLevel(MusicLevel.high);
      for (var n = 0; n < 3; n++) {
        sequence.nextBar();
      }
      // A high song has a shorter first bar here than at its own tempo.
      final next = sequence.nextBar();
      expect(sequence.current.id, high.id);
      expect(next.left.length, lessThan(SongStream(high).nextBar().left.length));
    });
  });

  group('the chip voices', () {
    Float32List note(void Function(Voices, Float32List) play) {
      final bus = Float32List(44100);
      play(Voices(Random(1)), bus);
      return bus;
    }

    final env = Envelope(0, 0.5, 0);

    test('a pulse is high for its share of the cycle, and speaks at once', () {
      final bus = note(
        (v, b) => v.pulse(b, 0, 57, env: env, duty: 0.25, vibratoRate: 0, vibratoDepth: 0, amp: 1),
      );
      expect(bus[1].abs(), greaterThan(0.1), reason: 'no delay before the note');
      final sounding = bus.sublist(100, 22000);
      final high = sounding.where((x) => x > 0).length / sounding.length;
      expect(high, closeTo(0.25, 0.02));
    });

    test('a detuned pulse beats against itself, and a plain one does not change', () {
      Float32List play(double detune) => note(
        (v, b) => v.pulse(b, 0, 57, env: env, duty: 0.5, detune: detune, vibratoRate: 0, vibratoDepth: 0, amp: 1),
      );
      expect(play(0).sublist(0, 2000).map((x) => x.abs()).reduce(max), lessThan(0.5));
      final beating = play(0.3).sublist(0, 22000);
      expect(beating.map((x) => x.abs()).reduce(max), greaterThan(0.6));
      expect(beating.where((x) => x.abs() < 0.05).length, greaterThan(500), reason: 'the two waves cancel in turn');
    });

    test('a triangle moves in sixteen steps', () {
      final bus = note((v, b) => v.triangle(b, 0, 33, env: env, amp: 1));
      expect({for (final x in bus.sublist(0, 22000)) x.toStringAsFixed(4)}.length, lessThanOrEqualTo(17));
    });

    test('a sub is a tone with little above it', () {
      final bus = note((v, b) => v.sub(b, 0, 36, env: env, amp: 1));
      expect(bus[1000].abs(), lessThan(1));
      expect(bus.sublist(0, 22000).map((x) => x.abs()).reduce(max), greaterThan(0.5));
    });

    test('drive leaves silence alone and limits a loud signal softly', () {
      final bus = Float32List.fromList([0, 0.05, 0.2, 4, -4]);
      Drive(amount: 6, mix: 1).process(bus, bus.length);
      expect(bus[0], 0);
      expect(bus[1], greaterThan(0.05), reason: 'a quiet signal comes up');
      expect(bus[3], closeTo(1, 0.01));
      expect(bus[4], closeTo(-1, 0.01));
      expect(bus[2], lessThan(1));
    });

    test('spread holds one side back, and only above the bass', () {
      final left = Float32List(100)..[0] = 1;
      final right = Float32List(100)..[0] = 1;
      Spread(ms: 1).process(left, right, 100);
      expect(left[0], 1);
      expect(right[0], lessThan(0.1), reason: 'the click moves');
      expect(right[44], greaterThan(0.9), reason: 'one millisecond is 44 samples');

      final other = Float32List(100)..[0] = 1;
      final same = Float32List(100)..[0] = 1;
      Spread(ms: -1).process(other, same, 100);
      expect(same[0], 1);
      expect(other[44], greaterThan(0.9));

      // A low tone stays nearly together, so a mono speaker does not lose it.
      final lowLeft = Float32List(44100), lowRight = Float32List(44100);
      for (var i = 0; i < 44100; i++) {
        lowLeft[i] = lowRight[i] = sin(2 * pi * 50 * i / 44100);
      }
      final dry = Float32List.fromList(lowLeft);
      Spread(ms: 15).process(lowLeft, lowRight, 44100);
      var apart = 0.0, whole = 0.0;
      for (var i = 22050; i < 44100; i++) {
        apart += pow(dry[i] - lowRight[i], 2);
        whole += dry[i] * dry[i];
      }
      expect(apart / whole, lessThan(0.25));
    });

    test('drive can turn down what it limits', () {
      final loud = Float32List.fromList([4, -4]);
      Drive(amount: 6, mix: 1, level: 0.5).process(loud, 2);
      expect(loud[0], closeTo(0.5, 0.01));
      expect(loud[1], closeTo(-0.5, 0.01));
    });

    test('every drum in the kit builds, within range', () {
      for (final entry in drumBuilders.entries) {
        final table = entry.value();
        expect(table, isNotEmpty, reason: entry.key);
        expect(table.map((x) => x.abs()).reduce(max), inInclusiveRange(0.05, 1.5), reason: entry.key);
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

    test('a song can\'t take an id the music setting keeps for itself', () {
      for (final id in reservedSongIds) {
        expect(() => parse((json) => json['id'] = id), fails('taken by the music setting'));
      }
    });

    test('a track\'s level must be a known one', () {
      expect(() => parse((json) => (json['tracks'] as List).first['level'] = 'loud'), fails('unknown level'));
      expect(parse((json) => (json['tracks'] as List).first['level'] = 'high').tracks.first.level, MusicLevel.high);
    });

    test('the tempos at low and high stay within range', () {
      expect(() => parse((json) => json['lowTempo'] = 0.5), throwsA(isA<SongFormatException>()));
      expect(() => parse((json) => json['highTempo'] = 1.5), throwsA(isA<SongFormatException>()));
      expect(() => parse((json) => json['highTempo'] = 0.9), throwsA(isA<SongFormatException>()));
      expect(parse((json) => json['lowTempo'] = 0.9).lowTempo, 0.9);
    });

    test('a track names no level and plays at all of them', () {
      expect(parse((_) {}).tracks.first.level, MusicLevel.low);
    });

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

    test('a pulse wave\'s width stays within range', () {
      Song voice(double duty) => parse((j) => (j['tracks'] as List).last['voice'] = {'type': 'pulse', 'duty': duty});
      expect(voice(0.25).tracks.last.voice.duty, 0.25);
      expect(() => voice(0), throwsA(isA<SongFormatException>()));
      expect(() => voice(1), throwsA(isA<SongFormatException>()));
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

    test('drive stays within range', () {
      void withDrive(double amount) => parse(
        (j) => j['buses'] = [
          {
            'id': 'dry',
            'effects': [
              {'type': 'drive', 'amount': amount, 'mix': 1},
            ],
          },
        ],
      );
      withDrive(5);
      expect(() => withDrive(50), throwsA(isA<SongFormatException>()));
    });

    test('spread stays within range', () {
      void withSpread(double ms) => parse(
        (j) => j['buses'] = [
          {
            'id': 'dry',
            'effects': [
              {'type': 'spread', 'ms': ms},
            ],
          },
        ],
      );
      withSpread(-12);
      expect(() => withSpread(100), throwsA(isA<SongFormatException>()));
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
