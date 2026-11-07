import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/song.dart';

import '../models/mission.dart';
import '../models/profile.dart';
import '../theme/season.dart';
import 'music_player.dart';
import 'music_resume.dart';

/// Voice colouring per character. Real device voices vary wildly between
/// phones, so identity is carried primarily by pitch and rate — which every
/// TTS engine supports — and only secondarily by picking distinct system
/// voices where enough of them exist.
class VoiceProfile {
  const VoiceProfile({required this.pitch, required this.rateScale});

  final double pitch;

  /// Multiplied against the runner's configured speech rate.
  final double rateScale;

  static const Map<String, VoiceProfile> bySpeaker = {
    // Dry, unhurried, two decades of not being surprised by anything.
    'KESTREL': VoiceProfile(pitch: 0.82, rateScale: 0.94),
    // Precise, slightly high, translating from something with more tenses.
    'HALCYON': VoiceProfile(pitch: 1.18, rateScale: 1.0),
    // Clipped. Rations words.
    'SIX': VoiceProfile(pitch: 0.92, rateScale: 1.12),
    // Talks too fast because standing still is how you get caught.
    'PACHINKO': VoiceProfile(pitch: 1.32, rateScale: 1.28),
    // Corporate, cold, plural.
    'VANTAR': VoiceProfile(pitch: 0.68, rateScale: 0.86),

    // -- NULL TIDE ------------------------------------------------------------
    // Ex-Dredge diver turned salvage broker. Low, unhurried, counts everything.
    'MARROW': VoiceProfile(pitch: 0.76, rateScale: 0.9),
    // Sixteen, runs a pirate station from a water tower, never finishes a
    // sentence at the speed she started it.
    'WREN': VoiceProfile(pitch: 1.26, rateScale: 1.22),
    // The tide-control intelligence. Deep, slow, speaks in measurements.
    'LEVEE': VoiceProfile(pitch: 0.7, rateScale: 0.8),
    // Harbour Authority security. Procedural, flat, plural.
    'DREDGE': VoiceProfile(pitch: 0.62, rateScale: 0.88),

    // -- SAMHAIN PROTOCOL ----------------------------------------------------
    // A courier three years dead, speaking through a retention server. Soft,
    // a little slow, as if every word had to be fetched from somewhere.
    'LANTERN': VoiceProfile(pitch: 1.08, rateScale: 0.84),
    // The city's identity-retention archive. Lowest voice in the app; reads
    // everything like an inscription.
    'OSSUARY': VoiceProfile(pitch: 0.56, rateScale: 0.76),

    // The app's own readout voice.
    'SYSTEM': VoiceProfile(pitch: 1.0, rateScale: 1.06),
  };

  static VoiceProfile of(String speaker) =>
      bySpeaker[speaker.toUpperCase()] ?? const VoiceProfile(pitch: 1.0, rateScale: 1.0);
}

/// Emitted while a beat plays so the HUD can show what is being said.
class NarrationEvent {
  const NarrationEvent(this.line);

  final StoryLine? line;

  bool get isEnd => line == null;
}

/// Speaks the story and interrupts whatever else is playing to do it.
abstract class Narrator {
  Future<void> init(Profile profile);

  /// Applies changed audio settings without a restart.
  Future<void> applyProfile(Profile profile);

  /// Plays a full interlude: takes audio focus, speaks every line in order,
  /// then hands focus back. Completes when the last line has finished.
  Future<void> speakBeat(List<StoryLine> lines);

  /// Whether a line in [language] would be spoken in a voice of it. Without
  /// one, a translated story line is spoken in its English original — what
  /// the briefing warns about. Only meaningful once [init] has run.
  bool hasVoiceFor(String language);

  /// One-off effect, without taking exclusive focus.
  Future<void> sfx(String name);

  Future<void> setAmbientBed(bool on);

  /// Starts the song the profile asks for, if any. Takes the run's audio from
  /// the runner's own player, and [stopAll] gives it back.
  ///
  /// [queue] is the songs to play, in order, when the choice is more than one
  /// song. Empty means the one song the profile names.
  Future<void> startMusic({List<String> queue = const []});

  /// Holds or lets go of the music for a paused run. It keeps its place.
  Future<void> setMusicPaused(bool paused);

  /// How much of the song plays, from its next phrase or with [atOnce] its next bar.
  Future<void> setMusicLevel(MusicLevel level, {bool atOnce = false});

  /// Cuts everything immediately — used when the runner ends a mission.
  Future<void> stopAll();

  Stream<NarrationEvent> get events;

  /// The song being heard, as each one starts, and null once there is none.
  Stream<String?> get songPlaying;

  Future<void> dispose();
}

/// Production implementation: flutter_tts for speech, just_audio for effects,
/// audio_session for focus.
class AudioNarrator implements Narrator {
  AudioNarrator({MusicResumeGuard? resumeGuard, MusicPlayer? music, @visibleForTesting AudioPlayer? bedPlayer})
    : _resume = resumeGuard ?? MusicResumeGuard.platform(),
      _music = music ?? const SilentMusicPlayer(),
      _bedPlayer = bedPlayer ?? AudioPlayer(handleAudioSessionActivation: false);

  final FlutterTts _tts = FlutterTts();

  // Both players are built with session activation *off*. just_audio otherwise
  // calls setActive(true) on every play() and never calls setActive(false) —
  // so a bare sound effect would take audio focus under the configured gain
  // type, pause the runner's music, and never give it back. Focus in this
  // class is taken and released in exactly one place.
  final AudioPlayer _sfxPlayer = AudioPlayer(handleAudioSessionActivation: false);
  final AudioPlayer _bedPlayer;
  final StreamController<NarrationEvent> _events = StreamController<NarrationEvent>.broadcast();

  final MusicResumeGuard _resume;
  final MusicPlayer _music;

  /// True for a whole run with generated music. Focus is then taken once, at
  /// the start, and story lines only lower the music: giving focus back after
  /// each would start the runner's own player underneath the song.
  bool _musicHoldsFocus = false;

  bool _runPaused = false, _interrupted = false, _unplugged = false;
  bool _bedOn = false;

  bool get _musicHeld => _runPaused || _interrupted || _unplugged;
  bool _speaking = false, _askedToDuck = false;
  final List<StreamSubscription<Object?>> _sessionEvents = [];

  AudioSession? _session;
  Profile _profile = const Profile();
  bool _ready = false;

  /// Mirrors the session's active state so take/release stay balanced even when
  /// a beat is cut short.
  bool _focusHeld = false;

  /// Distinct system voices assigned to speakers, when the device has enough.
  final Map<String, Map<String, String>> _voiceAssignments = {};

  /// The voice for every speaker without one of their own. Without it they
  /// spoke in whichever voice the previous line had left set, so a character
  /// changed voice depending on who had spoken before them.
  Map<String, String>? _fallbackVoice;

  /// Every voice the engine listed, kept for lines in another language.
  List<Map<String, String>> _allVoices = const [];

  /// The voice for each non-English language a line has asked for; null where
  /// the device has no usable one, so the engine picks.
  final Map<String, Map<String, String>?> _languageVoices = {};

  /// What `setLanguage` last told the engine, which keeps it.
  String _engineLanguage = 'en-US';

  /// Completed when the engine reports the line in progress failed or was
  /// stopped, which the plugin otherwise never passes back to `speak`.
  Completer<void>? _utteranceEnded;

  /// Whether the line in progress ended in an engine error, as opposed to
  /// finishing or being stopped.
  bool _utteranceFailed = false;

  // Error and cancel can both arrive for one line.
  void _endUtterance() {
    final ended = _utteranceEnded;
    if (ended != null && !ended.isCompleted) ended.complete();
  }

  /// Serialises beats: a chase result arriving mid-interlude queues up behind
  /// it rather than talking over it.
  Future<void> _queue = Future.value();

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Stream<String?> get songPlaying => _music.nowPlaying;

  @override
  Future<void> init(Profile profile) async {
    _profile = profile;
    try {
      _session = await AudioSession.instance;
      await _configureSession();
      _watchSession();

      await _tts.awaitSpeakCompletion(true);
      // flutter_tts completes `speak` only from onDone. An utterance the engine
      // fails or stops never answers, so these end the wait instead — see
      // [_speak].
      _tts
        ..setErrorHandler((message) {
          debugPrint('TTS error: $message');
          _utteranceFailed = true;
          _endUtterance();
        })
        ..setCancelHandler(_endUtterance);
      await _tts.setLanguage('en-US');
      await _tts.setVolume(1.0);
      await _assignVoices();

      await _bedPlayer.setLoopMode(LoopMode.all);
      _ready = true;
    } on Object catch (e, s) {
      // A device with no TTS engine must still be able to run missions; the
      // HUD keeps showing the lines as text.
      debugPrint('Narrator init failed, continuing muted: $e\n$s');
      _ready = false;
    }
  }

  Future<void> _configureSession() async {
    final session = _session;
    if (session == null) return;
    // Music for a whole run can't sit on top of the runner's own, so it always
    // asks their player to pause, whatever the setting says for a story line.
    final duck = _profile.audioInterrupt == AudioInterrupt.duck && !_musicHoldsFocus;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: duck
            ? AVAudioSessionCategoryOptions.duckOthers
            : AVAudioSessionCategoryOptions.interruptSpokenAudioAndMixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceNavigationGuidance,
        ),
        // gainTransient asks the music app to *pause* and resume afterwards;
        // gainTransientMayDuck asks it to drop under us instead.
        androidAudioFocusGainType: duck
            ? AndroidAudioFocusGainType.gainTransientMayDuck
            : AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  /// Hands out up to four distinct English voices so characters do not all
  /// sound like the same synthesiser at different pitches. Silently does
  /// nothing when the device has too few.
  Future<void> _assignVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      final all = raw.whereType<Map<Object?, Object?>>().map((v) => v.map((k, v) => MapEntry('$k', '$v'))).toList();
      _allVoices = all;
      final voices = usableVoices(all);
      // One line in logcat, so a report of slow or missing speech can be read
      // against what the device actually offered.
      debugPrint(
        'TTS voices: ${all.length} listed, ${voices.length} usable: '
        '${all.where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en')).map((v) => '${v['name']}${v['network_required'] == '1' ? ' (network)' : ''}${(v['features'] ?? '').contains('notInstalled') ? ' (not installed)' : ''}').join(', ')}',
      );
      if (voices.length < 2) return;

      const order = _speakerOrder;
      for (var i = 0; i < order.length; i++) {
        _voiceAssignments[order[i]] = voices[i % voices.length];
      }
      _fallbackVoice = voices[order.length % voices.length];
    } on Object catch (e) {
      debugPrint('Voice enumeration unavailable: $e');
    }
  }

  /// Voices in [language] (English unless said) that can speak with no
  /// connection and are on the device.
  ///
  /// The engine lists every voice it could offer, including ones it streams
  /// from a server and ones not yet downloaded. Given one of those mid-run,
  /// on a patchy signal, it either waits on the network — silence after the
  /// squelch — or fails the line.
  @visibleForTesting
  static List<Map<String, String>> usableVoices(Iterable<Map<String, String>> voices, {String language = 'en'}) => [
    for (final v in voices)
      if ((v['locale'] ?? '').toLowerCase().startsWith(language.toLowerCase()) &&
          v['network_required'] != '1' &&
          !(v['features'] ?? '').split('\t').contains('notInstalled'))
        v,
  ];

  /// The longest a line may take before it is given up on: generous enough
  /// for the slowest voice at the slowest speech rate, with room for the
  /// engine waking up.
  @visibleForTesting
  static Duration speechBudget(String text, double rate) =>
      Duration(milliseconds: 8000 + (text.length * 90 * 0.5 / rate.clamp(0.1, 1.0)).round());

  @override
  Future<void> applyProfile(Profile profile) async {
    final interruptChanged = profile.audioInterrupt != _profile.audioInterrupt;
    _profile = profile;
    if (interruptChanged) await _configureSession();
    await _music.setVolume(profile.musicVolume);
    if (_musicHoldsFocus && !profile.generatedMusicOn) await _stopMusic();
    await _bedPlayer.setVolume(_bedVolume);
    await _sfxPlayer.setVolume(profile.sfxVolume);
    // Only ever turns it off: the bed belongs to a run, which starts it, and a
    // change in Settings must not start a drone with no run to stop it.
    if (!profile.ambientBedOn) await setAmbientBed(false);
  }

  @override
  Future<void> speakBeat(List<StoryLine> lines) {
    if (lines.isEmpty) return Future.value();
    // Chain onto the queue so overlapping triggers never overlap in the ear.
    final next = _queue.then((_) => _speakBeatNow(lines)).catchError((Object e, StackTrace s) {
      debugPrint('Beat playback failed: $e\n$s');
    });
    _queue = next;
    return next;
  }

  Future<void> _speakBeatNow(List<StoryLine> lines) async {
    await _takeFocus();
    _speaking = true;
    await _applyDuck();
    try {
      await _playSfx('comm_open');
      for (final line in lines) {
        _events.add(NarrationEvent(line));
        if (line.sfxBefore != null) await _playSfx(line.sfxBefore!);
        await _speak(line);
        if (line.sfxAfter != null) await _playSfx(line.sfxAfter!);
        if (line.pauseAfterMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: line.pauseAfterMs));
        }
      }
      await _playSfx('comm_close');
    } finally {
      _events.add(const NarrationEvent(null));
      _speaking = false;
      await _applyDuck();
      await _releaseFocus();
    }
  }

  @override
  bool hasVoiceFor(String language) =>
      language == 'en' || usableVoices(_allVoices, language: language).isNotEmpty;

  Future<void> _speak(StoryLine line) async {
    if (!_ready || !_profile.voiceEnabled) {
      // Muted: still hold the line on screen for about as long as it would
      // have taken to say, so the HUD paces the same way.
      final ms = (line.text.length * 55).clamp(900, 9000);
      await Future<void>.delayed(Duration(milliseconds: ms));
      return;
    }
    final voice = VoiceProfile.of(line.speaker);
    line = spokenForm(line, hasVoiceFor: hasVoiceFor);
    final language = _languageOf(line);
    final foreign = language != null && language != 'en';
    try {
      await _setEngineLanguage(foreign ? language : 'en-US');
      final key = line.speaker.toUpperCase();
      final own = foreign ? null : _voiceAssignments[key];
      // A story line is spread across the language's voices by speaker, the
      // way English ones are; a line the app wrote takes the first.
      final assigned = foreign
          ? (line.original != null ? _voiceIn(language, speaker: key) : _voiceIn(language))
          : own ?? _fallbackVoice;
      // Always set one way or the other: the engine keeps the last voice it
      // was given, which is somebody else's.
      if (assigned != null) {
        await _tts.setVoice(assigned);
      } else {
        await _tts.clearVoice();
      }
      await _tts.setPitch(voice.pitch.clamp(0.5, 2.0));
      final rate = (_profile.speechRate * voice.rateScale).clamp(0.1, 1.0);
      await _tts.setSpeechRate(rate);
      if (await _say(line, rate) || assigned == null) return;
      // The voice failed. Say it again in the engine's default, and keep that
      // for the rest of the session rather than paying for the same failure on
      // every line.
      debugPrint('Voice ${assigned['name']} failed for ${line.speaker}; using the default');
      if (foreign) {
        _languageVoices[language] = null;
        _speakerVoices.removeWhere((k, _) => k.startsWith('$language/'));
      } else if (own != null) {
        _voiceAssignments.remove(key);
      } else {
        _fallbackVoice = null;
      }
      await _tts.clearVoice();
      await _say(line, rate);
    } on Object catch (e) {
      debugPrint('TTS failed for ${line.speaker}: $e');
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  /// What is actually said for [line]: the line itself, or — for a
  /// translated story line with no voice of its language on the phone — the
  /// English it was made from, in the speaker's own voice, rather than the
  /// translation read by whatever the engine falls back to. The screen still
  /// shows the translation, and the briefing said why.
  @visibleForTesting
  static StoryLine spokenForm(StoryLine line, {required bool Function(String language) hasVoiceFor}) {
    final language = _languageOf(line);
    if (line.original case final english? when language != null && !hasVoiceFor(language)) {
      return StoryLine(
        speaker: line.speaker,
        text: english,
        sfxBefore: line.sfxBefore,
        sfxAfter: line.sfxAfter,
        pauseAfterMs: line.pauseAfterMs,
      );
    }
    return line;
  }

  static String? _languageOf(StoryLine line) => line.language?.split(RegExp('[-_]')).first.toLowerCase();

  /// A voice of [language], or null to let the engine pick. With a
  /// [speaker], each speaker keeps one of the language's voices, so two
  /// characters differ by more than pitch where the phone has several.
  Map<String, String>? _voiceIn(String language, {String? speaker}) {
    final first = _languageVoices.putIfAbsent(language, () => usableVoices(_allVoices, language: language).firstOrNull);
    // Null after a voice failed: the engine's default from then on.
    if (first == null || speaker == null) return first;
    return _speakerVoices.putIfAbsent('$language/$speaker', () {
      final voices = usableVoices(_allVoices, language: language);
      final at = _speakerOrder.indexOf(speaker);
      return voices[(at < 0 ? _speakerOrder.length : at) % voices.length];
    });
  }

  final Map<String, Map<String, String>> _speakerVoices = {};

  static const _speakerOrder = ['KESTREL', 'HALCYON', 'SIX', 'PACHINKO', 'VANTAR', 'SYSTEM'];

  Future<void> _setEngineLanguage(String language) async {
    if (language == _engineLanguage) return;
    _engineLanguage = language;
    await _tts.setLanguage(language);
  }

  /// Speaks [line] and waits for it, never unbounded: a line the engine
  /// fails, stops or simply never finishes would otherwise hold its beat open
  /// for the rest of the run — no further beats or splits, and the music never
  /// handed back. Returns whether it was spoken; false when the engine
  /// reported an error.
  Future<bool> _say(StoryLine line, double rate) async {
    _utteranceFailed = false;
    final ended = _utteranceEnded = Completer<void>();
    await Future.any([_tts.speak(line.text), ended.future]).timeout(
      speechBudget(line.text, rate),
      onTimeout: () async {
        debugPrint('TTS gave no answer for ${line.speaker}; moving on');
        await _tts.stop();
      },
    );
    return !_utteranceFailed;
  }

  @override
  Future<void> sfx(String name) => _playSfx(name);

  Future<void> _playSfx(String name) async {
    if (_profile.sfxVolume <= 0) return;
    try {
      await _sfxPlayer.setAsset(sfxAsset(name, Season.active));
      await _sfxPlayer.setVolume(_profile.sfxVolume);
      // Every effect is a few seconds at most; the bound only matters if the
      // player never reports the end, which would stall the beat behind it.
      await _sfxPlayer.play().timeout(const Duration(seconds: 8), onTimeout: () {});
      await _sfxPlayer.stop();
    } on Object catch (e) {
      debugPrint('SFX $name failed: $e');
    }
  }

  String? _bedAsset;

  /// Where an effect is played from: the season's own version when it has
  /// one, the ordinary one otherwise. Story packs name effects plainly and
  /// get the seasonal sound for free.
  static String sfxAsset(String name, Season? season) => season != null && season.sfxVariants.contains(name)
      ? 'assets/sfx/${season.sfxFolder}/$name.wav'
      : 'assets/sfx/$name.wav';

  /// The drone is run music like a song, so it answers to the same slider. It
  /// sits well under it, being a bed rather than something to listen to.
  double get _bedVolume => _profile.musicVolume * 0.45;

  double get _bedVolumeUnderSpeech => _profile.musicVolume * 0.1;

  @override
  Future<void> setAmbientBed(bool on) async {
    try {
      if (on) {
        if (!_bedOn) _runPaused = _interrupted = _unplugged = false;
        // Reloaded when the season has changed since, so the bed follows it.
        final asset = sfxAsset('drone', Season.active);
        if (_bedAsset != asset) {
          await _bedPlayer.setAsset(asset);
          _bedAsset = asset;
        }
        await _bedPlayer.setVolume(_bedVolume);
      }
      _bedOn = on;
      await _syncBed();
    } on Object catch (e) {
      debugPrint('Ambient bed failed: $e');
    }
  }

  /// Plays the bed only while it is the choice and nothing is holding the music.
  Future<void> _syncBed() async {
    final play = _bedOn && !_musicHeld;
    if (play && !_bedPlayer.playing) {
      // Not awaited: play() completes when playback ends, and a loop never
      // does. Awaiting it left every caller hanging for as long as it played.
      unawaited(_bedPlayer.play().catchError((Object e) => debugPrint('Ambient bed failed: $e')));
    } else if (!play && _bedPlayer.playing) {
      await _bedPlayer.pause();
    }
  }

  Future<void> _takeFocus() async {
    if (_focusHeld) return;
    // Recorded before the music stops, so the guard knows there was something
    // to put back. Either call also invalidates a nudge still pending from the
    // previous beat, which must not land in the middle of this one.
    if (_profile.resumeMusic) {
      await _resume.beforeInterrupt();
    } else {
      _resume.cancel();
    }
    try {
      await _session?.setActive(true);
      _focusHeld = true;
      if (_bedPlayer.playing) await _bedPlayer.setVolume(_bedVolumeUnderSpeech);
    } on Object catch (e) {
      debugPrint('Audio focus request failed: $e');
    }
  }

  Future<void> _releaseFocus() async {
    if (_musicHoldsFocus) return;
    if (!_focusHeld) {
      _resume.cancel();
      return;
    }
    _focusHeld = false;
    try {
      if (_bedPlayer.playing) await _bedPlayer.setVolume(_bedVolume);
      // Let the last effect's tail finish before abandoning focus. Handing it
      // back while audio is still coming out of us is what makes some players
      // miss the AUDIOFOCUS_GAIN entirely.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // Handing focus back is what tells the music app to resume.
      await _session?.setActive(false);
    } on Object catch (e) {
      debugPrint('Audio focus release failed: $e');
    }
    // Deliberately not awaited: the guard sits watching for a couple of
    // seconds, and the next beat must not be held up behind it.
    if (_profile.resumeMusic) {
      unawaited(_resume.afterInterrupt());
    } else {
      _resume.cancel();
    }
  }

  @override
  Future<void> startMusic({List<String> queue = const []}) async {
    if (!_profile.generatedMusicOn || _musicHoldsFocus) return;
    _runPaused = _interrupted = _unplugged = _askedToDuck = false;
    _musicHoldsFocus = true;
    await _music.setVolume(_profile.musicVolume);
    try {
      await _configureSession();
      // Before the song starts, so the guard records the runner's player and
      // not our own.
      await _takeFocus();
      final started = queue.isEmpty
          ? await _music.start(_profile.music)
          : await _music.start(queue.first, then: queue.sublist(1));
      if (started) return;
    } on Object catch (e) {
      debugPrint('Music failed to start: $e');
    }
    await _stopMusic();
  }

  /// Our own track is released first, so that whatever the guard then sees
  /// playing is the runner's player coming back.
  Future<void> _stopMusic() async {
    if (!_musicHoldsFocus) return;
    await _music.stop();
    _musicHoldsFocus = false;
    await _releaseFocus();
    try {
      await _configureSession();
    } on Object catch (e) {
      debugPrint('Audio session reset failed: $e');
    }
  }

  @override
  Future<void> setMusicPaused(bool paused) async {
    _runPaused = paused;
    await _applyMusicHold();
  }

  @override
  Future<void> setMusicLevel(MusicLevel level, {bool atOnce = false}) async {
    if (_musicHoldsFocus) await _music.setLevel(level, atOnce: atOnce);
  }

  Future<void> _applyMusicHold() async {
    try {
      await _syncBed();
    } on Object catch (e) {
      debugPrint('Ambient bed failed: $e');
    }
    if (!_musicHoldsFocus) return;
    await _music.setPaused(_musicHeld);
  }

  Future<void> _applyDuck() async {
    if (_musicHoldsFocus) await _music.setDucked(_speaking || _askedToDuck);
  }

  /// A phone call, another app taking over, and headphones coming out: Android
  /// tells us, and playing on would be wrong in each case.
  void _watchSession() {
    final session = _session;
    if (session == null) return;
    _sessionEvents
      ..add(
        session.interruptionEventStream.listen((event) {
          if (event.type == AudioInterruptionType.duck) {
            _askedToDuck = event.begin;
            unawaited(_applyDuck());
          } else {
            _interrupted = event.begin;
            unawaited(_applyMusicHold());
          }
        }),
      )
      ..add(
        session.becomingNoisyEventStream.listen((_) {
          _unplugged = true;
          unawaited(_applyMusicHold());
        }),
      )
      ..add(
        session.devicesChangedEventStream.listen((event) {
          // The speaker is always there, so anything added is what came back.
          if (_unplugged && event.devicesAdded.any((d) => d.isOutput)) {
            _unplugged = false;
            unawaited(_applyMusicHold());
          }
        }),
      );
  }

  @override
  Future<void> stopAll() async {
    _queue = Future.value();
    _bedOn = false;
    // Each on its own: a phone with no speech engine must still lose the drone.
    for (final stop in [_tts.stop, _sfxPlayer.stop, _bedPlayer.stop]) {
      try {
        await stop();
      } on Object catch (e) {
        debugPrint('Narrator stop failed: $e');
      }
    }
    // One or the other. A second release finds nothing held and cancels the
    // guard's nudge, which is what the first has just set going.
    if (_musicHoldsFocus) {
      await _stopMusic();
    } else {
      await _releaseFocus();
    }
  }

  @override
  Future<void> dispose() async {
    await stopAll();
    for (final sub in _sessionEvents) {
      await sub.cancel();
    }
    await _sfxPlayer.dispose();
    await _bedPlayer.dispose();
    await _events.close();
  }
}
