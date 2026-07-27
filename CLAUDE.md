# Working in this repo

SPRAWL//RUN — a Flutter cyberpunk running tracker. **[README.md](README.md)** has
the product description, architecture and design rationale;
**[docs/MISSION_PACKS.md](docs/MISSION_PACKS.md)** has the story-content format.
Don't duplicate either here.

This file is only for things that will otherwise waste your time.

## Commands

```bash
fvm flutter analyze                                 # must stay clean
fvm flutter test                                    # 117 tests
fvm flutter build apk --release
fvm dart run tool/gen_sfx.dart                      # assets/sfx/*.wav
fvm dart run tool/gen_icons.dart                    # launcher icons + docs/icon.png
fvm flutter test tool/screenshots/capture_test.dart # docs/screenshots/*.png
```

Android builds take 3–6 minutes. Run them in the background with a monitor rather
than blocking on a foreground timeout.

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
  classes under `com/google` before believing otherwise.

## Untested on real hardware

Audio focus — the runner's music pausing and cleanly resuming around each story
beat — has never been verified on a device. It cannot be exercised in tests. Treat
any report about it as new information rather than a regression.
