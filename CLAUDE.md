# Working in this repo

SPRAWL//RUN — a Flutter cyberpunk running tracker. **[README.md](README.md)** has
the product description, architecture and design rationale;
**[docs/MISSION_PACKS.md](docs/MISSION_PACKS.md)** has the story-content format.
Don't duplicate either here.

This file is only for things that will otherwise waste your time.

## Commands

```bash
fvm flutter analyze                                 # must stay clean
fvm flutter test                                    # 144 tests
fvm flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk   # never `flutter install`
fvm dart run tool/gen_sfx.dart                      # assets/sfx/*.wav
fvm dart run tool/gen_icons.dart                    # launcher icons + docs/icon.png
fvm flutter test tool/screenshots/capture_test.dart # docs/screenshots/*.png
```

Android builds take 3–6 minutes. Run them in the background with a monitor rather
than blocking on a foreground timeout.

**Never deploy with `flutter install`.** It uninstalls the existing app before
installing, and Android deletes the private data directory on uninstall — so it
silently destroys the run log, which lives in `getApplicationDocumentsDirectory()`.
`adb install -r` upgrades in place. Confirm it did by checking that
`firstInstallTime` in `adb shell dumpsys package io.github.jbinder.sprawlrun` did
not move.

## Test traps

These four cost an hour between them. All are harness behaviour, not app bugs:

- **Real file I/O in a widget test hangs** unless it runs inside
  `tester.runAsync(...)`. The fake-async zone never completes those futures.
- **Awaiting a broadcast `StreamSubscription.cancel()` hangs under `fakeAsync`.**
  `RunEngine` deliberately fire-and-forgets its cancels in `_detachStreams()`.
  Don't "fix" that by adding `await`.
- **Lazy lists only build what's visible.** Widget tests that assert on a whole
  mission chain set a tall viewport (`tester.view.physicalSize`) instead of
  scrolling.
- **The harness substitutes a placeholder font**, so icons render as `□`. The
  screenshot tool registers every family from `FontManifest.json` to fix this.

`tool/screenshots/capture_test.dart` is a tool, not a test. It lives outside
`test/` so `flutter test` does not run it and write files as a side effect. Keep
it there.

## Generated, never hand-edited

`assets/sfx/*.wav`, all launcher icons, `docs/icon.png` and `docs/screenshots/*`
are produced by the scripts in `tool/`. Edit the generator and re-run it. The
only third-party binaries in the repo are the three OFL fonts.

## Conventions worth preserving

- **`RunEngine` owns no persistence and no UI.** It takes a `LocationSource`, a
  `Narrator` and a clock by injection. That is what makes whole missions testable
  in milliseconds — keep new dependencies injectable.
- **Derived data stays derived.** Stats, streaks and achievement progress are pure
  functions of the run log. Never cache them as counters that can drift.
- **`test/campaign_test.dart` is the contract for story content.** If you add a
  field to the mission format, add validation for it there too — a broken beat
  otherwise only surfaces twenty minutes into a real run.
- **`AudioNarrator` is the only thing that touches audio focus.** Both
  `AudioPlayer`s are constructed with `handleAudioSessionActivation: false` for
  that reason: just_audio otherwise calls `setActive(true)` on every `play()` and
  never calls `setActive(false)`, so a bare sound effect takes focus under the
  configured gain type, pauses the runner's music and never hands it back. That
  was a real bug — a chase-start sting killed the music for the whole chase.
  Construct any new player the same way.
- **Persisted JSON is written through `writeAtomically`.** `writeAsString`
  truncates before it streams, so a process death mid-write leaves a torn file
  that no longer parses — and both repositories read an unparseable file as
  empty, which turns a crash into total data loss. Write to a sibling and rename.
  A file that still fails to parse is quarantined rather than overwritten.
- **Every field in `Profile` and `RunRecord` must decode from JSON that lacks
  it.** `test/upgrade_test.dart` holds frozen 0.1.0 documents and asserts they
  still load; add a required field with no default and an update wipes the
  runner's history. Do not regenerate those fixtures from `toJson`.
- **A backup is the whole device.** `data/backup.dart` exports profile plus every
  run *with its trace*, which is complete precisely because stats, streaks and
  achievements are derived. Add a field to `Profile` or `RunRecord` and it rides
  along for free; add a new persisted *file* and it will not, so extend
  `BackupService.collect` and `import` at the same time.

## Gradle config that looks wrong but isn't

- `android/app/build.gradle.kts` sets `ndkVersion`. It is genuinely required:
  `path_provider_android` pulls in `package:jni`, which compiles `dartjni.c`.
  Removing it breaks the build.
- `android/build.gradle.kts` raises every plugin module to the app's `compileSdk`.
  Several plugins still pin `android-35`; without this the machine needs every
  historical SDK platform installed.
- `android/app/build.gradle.kts` excludes the `com.google.android.gms` group, and
  `location_service.dart` sets `forceLocationManager: true`. That pair is what
  keeps the app free of Play Services. `proguard-rules.pro` exists only to
  `-dontwarn` the references this leaves dangling. Removing any one of the three
  silently reintroduces a proprietary dependency — verify with a dexdump for
  classes under `com/google` before believing otherwise. Re-run that check after
  adding any plugin, not just after touching these three.

## Untested on real hardware

Two things cannot be exercised by the test suite. Treat any report about either as
new information rather than a regression:

- **Audio focus** — the runner's music pausing and cleanly resuming around each
  story beat. Two things now stand between the app and the known failure where a
  player never resumes: focus is taken in exactly one place (see the conventions
  above), and `MusicResumeGuard` presses a media-button PLAY when a player that
  *was* running is still silent after focus went back. The guard's decision logic
  is unit-tested; whether the media key actually reaches Spotify et al. is not.
- **GPS acquisition via the AOSP `LocationManager`.** Since dropping Play
  Services the app no longer uses the fused provider. Startup is verified clean
  on device (no `NoClassDefFoundError`), but that fixes actually arrive has only
  been shown in tests against synthetic data. Needs one real run outdoors.
