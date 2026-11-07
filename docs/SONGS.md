# Songs

A song is one JSON file. The app ships every file in `assets/songs/`, finding
them through the asset manifest, so adding a song means adding a file, with no
code to change. There are no recordings: the phone plays the file live, during
the run, with the synths in `lib/audio/synth/`.

`assets/songs/neon_pursuit.json` is a worked example.

A file holds notes and settings, never code. Voices and effects come from a fixed
list, and every value has a range, so a song can't run anything or be louder than
the master limiter allows. `Song.parse` in `lib/audio/song.dart` is the authority
on all of this, and `test/song_test.dart` checks every shipped file.

To hear a song without building the app:

```bash
fvm dart run tool/gen_music.dart assets/songs/neon_pursuit.json music/out.wav 24 44
```

The last two numbers are the first bar and how many to render.

## The file

| Field | Meaning |
|---|---|
| `format` | `1`. A newer number than the app knows is refused. |
| `id` | `a-z`, `0-9`, `_`, `-`. A shipped song's file is named after it. `off`, `ambient`, `shuffle`, `best` and `folder` are taken by the music setting. |
| `name`, `names` | The name, and optionally the name per language code. |
| `author` | Who wrote it. Optional for your own use, required to contribute one. |
| `licence` | Optional. |
| `bpm` | 60 to 200. Bars are always four beats. |
| `lowTempo`, `highTempo` | Optional, by default 1. The share of its tempo the song plays at at level `low` (0.88 to 1) and `high` (1 to 1.15), gliding there and back at 2% a bar. Pitch stays where it is, and echoes stay on the beat. |
| `key`, `moods`, `energy` | Optional, for choosing a song; they change nothing in the sound. `energy` is 0 to 1. Best match reads `moods`: `atmospheric` and `melancholic` suit walks, `aggressive`, `dark` and `tense` suit chase-heavy missions, `bombastic` suits long runs and finales, and `uplifting`, `retro` and `playful` suit an ordinary run. |
| `seed` | Fixes the song's small random movements, so it always renders the same. |
| `bars`, `loopFrom` | Bars in the first pass, and the bar it goes back to after them. |
| `sections` | Optional, in order: `{ "name", "from" }`. |
| `buses`, `patterns`, `tracks` | Below. |

## Buses

Tracks play into buses, and every bus goes to the master chain. A bus has an `id`
and optional `effects`, applied as slicer, drive, echo, reverb, then spread, whatever
order they are listed in. A reverb makes a bus stereo, so it has to come last.

| Effect | Settings |
|---|---|
| `slicer` | `mix`, and optional `mixClips` of `{ "from", "to", "mix" }` where it differs. A falling saw on every beat: what goes through is struck and fades. |
| `drive` | `amount` from 1 to 20, `mix`, and optional `level` from 0 to 1 for what comes out. Overdrive, for a harder edge. A voice driven into the limit hardly gets quieter when its `amp` drops, so use `level`. |
| `echo` | `phase` and `decay` in beats, `mix`. |
| `reverb` | `room`, `damp`, `mix`. |
| `spread` | `ms`, from -40 to 40. Width: holds the right channel back that long, or the left if negative. Two buses spread opposite ways make a wall. Below about 180 Hz stays in the centre. |

## Patterns

A pattern is a named list of bars, played as a cycle and indexed by the song's bar
number. Patterns of the same length therefore stay aligned, wherever a clip starts.

Each bar is one of these, plus an optional `repeat` to use it for several bars:

| Bar | Meaning |
|---|---|
| `{ "hits": "x...x..." }` | Drum hits on a grid, `every` 0.25 beats by default. Also `amp`, `ampStep` added per step, and `rate`. |
| `{ "notes": ["a1", "a2", null] }` | Notes on a grid, `every` 0.5 beats by default. `null` is a rest. |
| `{ "phrase": [["e5", 1.5], [null, 0.5]] }` | Notes one after another, as `[note, beats]`. |
| `{ "chord": ["a3", "c4", "e4"] }` | Notes together on the first beat, sharing their amp between them. |
| `{ "rest": true }` | Nothing. |

Notes are written as `c4`, `c#4` or `eb4`, and `a4` is 440 Hz.

## Tracks

A track has an `id`, a `bus`, a `voice` and `clips`. It plays whichever of its
clips covers the current bar.

A track may name a `level`: `low`, `normal` or `high`. It plays at that level and
above, and without one it always plays. `normal` should be the song as you mean it
to be heard: `low` is what is left when the runner eases off, so check that every
section still has something in it, and `high` adds to the song, for pushing hard
or being chased. A level changes only where a four-bar phrase starts, unless a
chase calls for it at the next bar. Levels are optional for every song: one that
names none simply plays through, whatever the runner is doing.

A clip is `{ "from", "to", "pattern" }`, up to but not including bar `to`. It may
add `amp`, `transpose` in semitones, and `cutoff`, as a number or as
`{ "from", "to" }` to move over the clip.

| Voice `type` | What it is | Settings |
|---|---|---|
| `saw` | One filtered saw. Sonic Pi's `:saw`. | `cutoff` |
| `dsaw` | Two detuned saws. `:dsaw`. | `cutoff`, `detune` |
| `prophet` | Five moving pulses through a resonant filter. `:prophet`. | `cutoff` |
| `blade` | A saw through three formants, with delayed vibrato. `:blade`. | `vibratoRate` in hertz, `vibratoDepth` |
| `pulse` | A square wave as an early sound chip made it, with no 20 ms delay. A delayed vibrato. | `duty`, the share of the cycle that is high (0.5 is hollow, 0.125 is thin), `detune` for a second wave beside it, `vibratoRate`, `vibratoDepth` |
| `triangle` | A triangle in sixteen steps, for chip bass. | |
| `sub` | A sine with a touch of its octave, for the very bottom. | |
| `drum` | `drum`: `kick`, `snare`, `dubSnare`, `hat`, `splash`, `boom`, `taiko`, `taikoHigh`, or the chip kit `chipKick`, `chipSnare`, `chipHat`. | `rate`, `cutoff` |
| `riser` | Noise with a sliding filter, for builds. Started by any note. | `cutoff`, `cutoffTo`, `slide` in beats |

Every voice takes `amp`. All but `drum` take an envelope in beats: `attack`,
`sustain` and `release`, each plus an optional share of the note's own length,
`attackOfNote`, `sustainOfNote` and `releaseOfNote`. So a phrase can breathe with
its rhythm. `cutoff` is a MIDI note number, as in Sonic Pi.

A note can last at most nine seconds; only `riser` runs longer.

## How the synths behave

They follow Sonic Pi's definitions, including what shapes the sound without
looking as if it would:

- `saw`, `dsaw` and `prophet` start 20 ms behind their envelope, so a very short
  note loses its beginning. A 42 ms note keeps about half of itself.
- A chord divides its `amp` by the number of notes.
- `boom` isn't a hit: it swells for 1.5 s, and its low end lands about 2 s after the
  bar it is played on.

**A synth's sound is part of the format.** A song has to go on sounding as its
author heard it, so a change that alters existing songs needs a new `format`
number, with the old behaviour kept for the old one.

## What it costs

Each note is computed in full when its bar comes up. On a mid-range phone, Neon
Pursuit takes about a quarter of one core and costs about 2% of battery an hour,
in a single comparison sitting still. `prophet` and `blade` cost the most, and
reverbs run constantly. If a phone can't keep up for several bars in a row, the
song drops a level for the rest of the run, and below `low` the music stops and the
run carries on. So a song's `low` should be clearly cheaper than the song.
