import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../models/mission.dart';
import '../models/profile.dart';

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

  /// One-off effect, without taking exclusive focus.
  Future<void> sfx(String name);

  Future<void> setAmbientBed(bool on);

  /// Cuts everything immediately — used when the runner ends a mission.
  Future<void> stopAll();

  Stream<NarrationEvent> get events;

  Future<void> dispose();
}

/// Production implementation: flutter_tts for speech, just_audio for effects,
/// audio_session for focus.
class AudioNarrator implements Narrator {
  AudioNarrator();

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final AudioPlayer _bedPlayer = AudioPlayer();
  final StreamController<NarrationEvent> _events = StreamController<NarrationEvent>.broadcast();

  AudioSession? _session;
  Profile _profile = const Profile();
  bool _ready = false;

  /// Distinct system voices assigned to speakers, when the device has enough.
  final Map<String, Map<String, String>> _voiceAssignments = {};

  /// Serialises beats: a chase result arriving mid-interlude queues up behind
  /// it rather than talking over it.
  Future<void> _queue = Future.value();

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Future<void> init(Profile profile) async {
    _profile = profile;
    try {
      _session = await AudioSession.instance;
      await _configureSession();

      await _tts.awaitSpeakCompletion(true);
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
    final duck = _profile.audioInterrupt == AudioInterrupt.duck;
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
      final voices = raw
          .whereType<Object>()
          .map((v) => Map<String, String>.from((v as Map).map((k, v) => MapEntry('$k', '$v'))))
          .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en'))
          .toList();
      if (voices.length < 2) return;

      const order = ['KESTREL', 'HALCYON', 'SIX', 'PACHINKO', 'VANTAR', 'SYSTEM'];
      for (var i = 0; i < order.length; i++) {
        _voiceAssignments[order[i]] = voices[i % voices.length];
      }
    } on Object catch (e) {
      debugPrint('Voice enumeration unavailable: $e');
    }
  }

  @override
  Future<void> applyProfile(Profile profile) async {
    final interruptChanged = profile.audioInterrupt != _profile.audioInterrupt;
    _profile = profile;
    if (interruptChanged) await _configureSession();
    await _bedPlayer.setVolume(profile.sfxVolume * 0.35);
    await _sfxPlayer.setVolume(profile.sfxVolume);
    await setAmbientBed(profile.ambientBed);
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
      await _releaseFocus();
    }
  }

  Future<void> _speak(StoryLine line) async {
    if (!_ready || !_profile.voiceEnabled) {
      // Muted: still hold the line on screen for about as long as it would
      // have taken to say, so the HUD paces the same way.
      final ms = (line.text.length * 55).clamp(900, 9000);
      await Future<void>.delayed(Duration(milliseconds: ms));
      return;
    }
    final voice = VoiceProfile.of(line.speaker);
    try {
      final assigned = _voiceAssignments[line.speaker.toUpperCase()];
      if (assigned != null) await _tts.setVoice(assigned);
      await _tts.setPitch(voice.pitch.clamp(0.5, 2.0));
      await _tts.setSpeechRate((_profile.speechRate * voice.rateScale).clamp(0.1, 1.0));
      await _tts.speak(line.text);
    } on Object catch (e) {
      debugPrint('TTS failed for ${line.speaker}: $e');
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  @override
  Future<void> sfx(String name) => _playSfx(name);

  Future<void> _playSfx(String name) async {
    if (_profile.sfxVolume <= 0) return;
    try {
      await _sfxPlayer.setAsset('assets/sfx/$name.wav');
      await _sfxPlayer.setVolume(_profile.sfxVolume);
      await _sfxPlayer.play();
      await _sfxPlayer.stop();
    } on Object catch (e) {
      debugPrint('SFX $name failed: $e');
    }
  }

  @override
  Future<void> setAmbientBed(bool on) async {
    try {
      if (on) {
        if (_bedPlayer.audioSource == null) await _bedPlayer.setAsset('assets/sfx/drone.wav');
        await _bedPlayer.setVolume(_profile.sfxVolume * 0.35);
        if (!_bedPlayer.playing) await _bedPlayer.play();
      } else if (_bedPlayer.playing) {
        await _bedPlayer.pause();
      }
    } on Object catch (e) {
      debugPrint('Ambient bed failed: $e');
    }
  }

  Future<void> _takeFocus() async {
    try {
      await _session?.setActive(true);
      if (_bedPlayer.playing) await _bedPlayer.setVolume(_profile.sfxVolume * 0.08);
    } on Object catch (e) {
      debugPrint('Audio focus request failed: $e');
    }
  }

  Future<void> _releaseFocus() async {
    try {
      if (_bedPlayer.playing) await _bedPlayer.setVolume(_profile.sfxVolume * 0.35);
      // Handing focus back is what tells the music app to resume.
      await _session?.setActive(false);
    } on Object catch (e) {
      debugPrint('Audio focus release failed: $e');
    }
  }

  @override
  Future<void> stopAll() async {
    _queue = Future.value();
    try {
      await _tts.stop();
      await _sfxPlayer.stop();
      await _bedPlayer.stop();
    } on Object catch (e) {
      debugPrint('Narrator stop failed: $e');
    }
    await _releaseFocus();
  }

  @override
  Future<void> dispose() async {
    await stopAll();
    await _sfxPlayer.dispose();
    await _bedPlayer.dispose();
    await _events.close();
  }
}
