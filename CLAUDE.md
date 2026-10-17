# Working in this repo

SPRAWL//RUN — a Flutter cyberpunk running tracker. **[README.md](README.md)** has
the product description, architecture and design rationale;
**[docs/MISSION_PACKS.md](docs/MISSION_PACKS.md)** has the story-content format.
Don't duplicate either here.

This file is only for things that will otherwise waste your time.

## Commands

```bash
fvm flutter analyze                                 # must stay clean
fvm flutter test                                    # 570 tests
fvm flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk   # never `flutter install`
fvm dart run tool/gen_sfx.dart                      # assets/sfx/*.wav
fvm dart run tool/gen_icons.dart                    # launcher icons + docs/icon.png
fvm flutter test tool/screenshots/capture_test.dart # docs/ + every language's store shots
fvm flutter test --dart-define=PSEUDO=true tool/screenshots/capture_test.dart  # build/screenshots-pseudo/
fvm flutter test --dart-define=LOCALE=es tool/screenshots/capture_test.dart    # build/screenshots-es/
fvm dart run tool/gen_pseudo_l10n.dart              # after any ARB change
fvm dart run tool/pack_strings.dart                 # after any pack text change; reports translations
```

Android builds take 3–6 minutes. Run them in the background with a monitor rather
than blocking on a foreground timeout.

**Never deploy with `flutter install`.** It uninstalls the existing app before
installing, and Android deletes the private data directory on uninstall — so it
silently destroys the run log, which lives in `getApplicationDocumentsDirectory()`.
`adb install -r` upgrades in place. Confirm it did by checking that
`firstInstallTime` in `adb shell dumpsys package io.github.jbinder.sprawlrun` did
not move — and check the install actually succeeded first; a failed install
leaves the timestamp untouched too.

Two more ways a deploy fails without touching data, both seen:

- **Deploy the arm64 split, not the universal APK.** Released builds carry the
  split versionCode (`versionCode * 10 + abi`), so a device that installed a
  release refuses the universal build's plain versionCode as a downgrade. Build
  with `--split-per-abi --target-platform=android-arm64` and install
  `app-arm64-v8a-release.apk`.
- **An APK signed with a different key blocks every local build.** fdroiddata's
  CI signs its test APKs with a throwaway key, and F-Droid's own builds carry
  F-Droid's key; once either is installed, nothing signed with the release key
  can replace it (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). The only way back is an
  uninstall, which deletes the run log — export a backup from Settings → Data
  first.

## Test traps

These four cost an hour between them. All are harness behaviour, not app bugs:

- **Real file I/O in a widget test hangs** unless it runs inside
  `tester.runAsync(...)`. The fake-async zone never completes those futures.
  When the I/O starts *from the UI* — a dialog's answer resuming a handler
  that then writes files — wrapping the tap is not enough, because the
  continuation resumes inside the fake zone. Alternate
  `tester.runAsync(() => Future.delayed(...))` with `tester.pump()` in a short
  loop until the effect lands; `settings_test`'s pack removal does this.
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

`assets/sfx/*.wav`, all launcher icons, the status-bar icon
(`res/drawable-*/ic_notification.png`), `docs/icon.png`, `docs/screenshots/*`
and the store's `fastlane/.../phoneScreenshots/*` are produced by the scripts in
`tool/`. The two screenshot sets are written by the same run, because copying
them across by hand is what left the published listing on 0.1.0 shots — taken
before the second campaign existed — until 2026-09-30. Edit the generator and re-run it. The
only third-party binaries in the repo are the three OFL fonts.

Regenerating is repeatable: the tool pins `appNow()` (`lib/util/clock.dart`) to
a Sunday evening and seeds its data from that instant, so two runs produce
byte-identical images whatever the day. Anything on screen derived from the
time — this week, streaks, "ago", the greeting — must read `appNow()`, not
`DateTime.now()`, or the store shots start drifting with the weekday again.

## Conventions worth preserving

- **Nothing a runner reads is a literal.** Interface text lives in
  `lib/l10n/app_en.arb`, every key with a description (translators never see
  the screen; `l10n_test` insists for short strings), and plurals as ICU
  messages, never `'s'` concatenation. Widgets read `L.of(context)`; code
  without a context — `Fmt`, models, notification and spoken text — reads
  the global `l10n`, kept in step by `MaterialApp.builder`. The generated
  `lib/l10n/generated/` is gitignored and rebuilt by `pub get` and every
  build. Kotlin's text is in `res/values/strings.xml`; the three signal
  channels are named on both sides and `l10n_test` keeps them equal. Codes
  that get *stored* stay codes: the streak unit (`MIN`/`KM`/`OPS`) goes into
  THE WIRE's archive untranslated and is only worded when shown. Story text
  is translated separately, below.
- **The language is resolved in `AppState`, not left to `MaterialApp`.**
  `AppState.locale` is `Profile.language` (empty = follow the phone) or the
  phone's first shipped language, and `_applyLocale` puts it behind `l10n`
  before `_recompute` and before signals are planned — notification text is
  fixed in whatever language `l10n` speaks at that moment. `MaterialApp` gets
  the same locale. A phone language change arrives through `HomeShell`'s
  `didChangeLocales` and re-plans. Adding a language is `app_<lang>.arb`,
  `values-<lang>/strings.xml` and a line in `res/xml/locales_config.xml`;
  `l10n_test` checks the last against the ARB files.
- **Translations arrive from Weblate as pull requests; the source does not.**
  `app_en.arb`, `values/strings.xml`, the en-US listing and the generated
  `assets/missions/l10n/<pack>_en.arb` are edited here only — Weblate has
  source editing off. Before merging a Weblate PR run `l10n_test`,
  `pack_strings_test` and `overflow_test` (the latter renders every shipped language
  at 360 dp, so a long Spanish word that breaks a screen fails there). A *new*
  language also needs its line in `res/xml/locales_config.xml` — `l10n_test`
  names it — and a `languageName`, then a screenshot run for its listing.
  Rules and glossary for translators: `docs/TRANSLATING.md`.
- **A line is spoken in its `StoryLine.language`, or in English.** The split
  readout and the intel notice carry the interface language; the narrator
  gives them an installed offline voice of it (or lets the engine pick) and
  sets the engine back to English for the next English line, since the engine
  keeps the last language it was given. A translated pack line carries its
  language *and* its English (`original`): with an offline voice of the
  language it is spoken in one, spread across speakers by `_speakerOrder`
  with each speaker's pitch and rate; with none, `spokenForm` swaps in the
  English, in the speaker's own English voice, and the briefing says why
  (`Narrator.hasVoiceFor`). The screen shows the translation either way.
- **Story translations are overlays on the English pack, applied whole
  missions at a time.** `models/pack_strings.dart` walks a pack once to offer
  its strings (`packStrings`) and once to answer them (`localizePack`), so the
  keys a translator sees and the keys the app reads cannot drift. Keys are
  paths (`sp01.sp01_b4.2`), so a translation outlives a reworded English line
  instead of falling back. Names — pack title, codename, location, speakers,
  pursuers — are never offered. A mission is translated only when all of its
  strings are; the pack's own text (tagline, categories, pack signals) goes
  string by string. `AppState.packs` is the localized view of
  `_sourcePacks`, rebuilt when the language changes. A translated signal keeps
  its English as `Signal.original`, and `Signal.ref` hashes that, so THE
  WIRE's archive never depends on the language a signal was sent in. Bundled
  translations are `assets/missions/l10n/<pack>_<lang>.arb`; the `_en.arb`
  beside them is generated and `pack_strings_test` fails while it is stale.
- **`test/overflow_test.dart` renders every screen in a pseudo-locale.**
  English accented, 40% longer and bracketed (`test/support/pseudo.dart`),
  at 360 dp with the real fonts; an overflow fails it. Its `PseudoL` is
  generated from the ARB and checked for staleness — re-run
  `gen_pseudo_l10n` after adding a message. Fix a label that grows by letting
  it wrap, ellipsize or scale down, never by shortening the English. The
  pseudo screenshots show what the test cannot: text without brackets never
  went through the ARB. Orbitron has no `Ø`, so the pseudo `O` is `Ö`.
- **`Cy` colours are getters, not constants.** A season swaps the palette at
  runtime (`theme/season.dart`, `Cy.use`), so a `const` that captures a `Cy`
  colour does not compile, and a colour cached in a field or a `static final`
  keeps the old palette after the swap. Read `Cy.x` at build or paint time;
  a widget's colour parameter is nullable with a `?? Cy.x` fallback in
  `build`. `SprawlRunApp` rebuilds the whole tree when the season changes.
- **A season's window is read from the calendar, never stored.** `Season.at`
  decides from `appNow()` and `Profile.seasonalEvents`; a seasonal pack is
  hidden outside it, but its missions still resolve so old runs keep their
  titles, and the seasonal achievements count runs by the same window.
  `packs_test` pins `debugNow` to July for that reason — a test that leaves
  the clock real starts failing every October.

- **`RunEngine` owns no persistence and no UI.** It takes a `LocationSource`, a
  `Narrator` and a clock by injection. That is what makes whole missions testable
  in milliseconds — keep new dependencies injectable.
- **Derived data stays derived.** Stats, streaks and achievement progress are pure
  functions of the run log. Never cache them as counters that can drift.
- **A streak week is judged against the target it had.** Stats, the 12-week
  strip and the streak achievements take `profile.streakTargets` (the dated
  `streakGoalChanges`), never `profile.streakGoal` alone — judging every past
  week against today's target once showed a real 4-week streak as 0 after the
  target was raised. Settings changes it through `Profile.withStreakGoal`,
  which records the change from the current week on.
- **Repairs to stored data are migrations, not one-off flags.**
  `data/migrations.dart` holds numbered steps; `Profile.dataVersion` records
  how far a device has come, and 0 means "written before migrations existed".
  Add a step and bump `Migrations.current` — a step must survive being run
  twice, since a crash between migrating and saving repeats it.
- **Adding an achievement is safe: `AppState.load` dates it.**
  `AchievementEngine.backfill` replays the run log and dates each achievement
  to the run that crossed its threshold — filling in ones whose definition did
  not exist yet, and never moving a date later. Without it the next completed
  run sweeps up everything history already satisfied and reveals it as if that
  one run had earned it, stamped with that day. That shipped once; the runner
  noticed. The replay only runs when something is undated, because it costs a
  stats pass per run; keep it that way.
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
- **Every vertical scroller fades the edge that still hides content.** It is
  `CyberScrollBehavior` (`widgets/edge_fade.dart`), set on `MaterialApp` and on
  the screenshot tool's, not a wrapper per screen — so a new screen gets it
  without asking. Horizontal scrollers are left to `FilterRail`, which fades and
  adds a chevron. A test that builds its own `MaterialApp` without it will not
  see the fade, which is fine unless the test is about the fade.
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
  `BackupService.collect` and `import` at the same time. There is one such
  store so far: `signals/<year>.json`, the archive behind THE WIRE — the only
  thing on it that is stored, since runs, clears, achievements and intel all
  project from the run log and profile. (`active_run.json` is deliberately
  left out: it exists only while a run does.) Exported as *sent* entries only; the
  pending plan is rebuilt by whichever device restores it.
- **The archive is split by year so launching never pays for it.** A re-plan
  reads and writes only the years that can hold a pending signal — this one,
  and next year across New Year — so its cost is flat however much history
  exists; earlier years are never written again. The whole history is read
  only by `AppState.loadSignalArchive`, which THE WIRE calls when it opens.
  Measured: a launch re-plan stays around 20 ms from one year of history to
  ten, while opening THE WIRE grows from 30 ms to 150 ms. That second figure
  is wall-clock: the closed years are parsed in one `Isolate.run`, so the UI
  thread is never blocked for more than ~4 ms by it (it was ~20 ms per year,
  a dropped frame each). Do not make `AppState.load` read the whole archive.
- **What is new on THE WIRE is one timestamp, not a flag per signal.**
  `Profile.wireReadAt` is when THE WIRE was last opened; every signal sent
  after it is new, of whatever kind. Opening THE WIRE is the only thing that
  marks them read. It is started at the current moment wherever a profile
  arrives without one — first launch after the update *and* a restored backup
  from before it, which carries the latest `dataVersion` and so never meets a
  numbered migration. Android shows a signal without running Dart, so the
  shell re-checks when the next one is due and on resume; nothing else would
  light the dot while the app sits open.
- **The signal archive stores references, so rewording a line orphans it.**
  Each entry holds `signalRef(text)` — FNV-1a of the authored line — not the
  line itself, the same way a run's story log holds beat ids. That is what
  lets the archive go uncapped at a few dozen bytes an entry. The price: edit
  a signal's text in a pack and every archived instance of it stops resolving
  and drops off THE WIRE. Fix typos before a release, not after. And never
  change `signalRef` itself — `signal_library_test` pins its output against an
  independently computed value, and a change would orphan every archive in
  the field at once. Debrief *figures* are stored as numbers, since nobody
  authored them.
- **`MainActivity` creates `geolocator_channel_01` before geolocator can.**
  geolocator builds that channel at `IMPORTANCE_NONE`, which Android treats as
  blocked: the foreground-service notification never reaches the shade and the
  app appears only inside the grouped "running in the background" notice.
  Importance cannot be lowered by a later `createNotificationChannel`, so
  creating it first at `IMPORTANCE_LOW` wins. The app also has to request
  `POST_NOTIFICATIONS` itself — no plugin here does, and without the grant the
  service runs with its notification suppressed. Both were shipped broken
  through 0.2.1. A device that already has the channel keeps its old settings
  across delete and recreate, so verify the fix on a fresh install.
- **`MissionService` is the app's only foreground service.** geolocator can post
  its own, and deliberately is not asked to: `location_service.dart` passes no
  `foregroundNotificationConfig`, because that text is fixed when the stream
  opens and so can never count a goal down, and two configs would put two
  notices on screen for one run. Ours starts before `engine.start`, which blocks
  on GPS readiness and the ambient bed, and claims `specialUse` until the
  readiness answer arrives — then `startForeground` runs again to promote it to
  `location`, which is what keeps fixes coming with the screen off. A repeat
  call that only changes the text goes through `notify` instead. It holds a
  partial wake lock too: being in the foreground does not keep the CPU awake,
  and a frozen process stalls the ticker that fires story beats.
- **Signals are notifications and are never spoken.** The messages handlers
  send between runs (`lib/services/signal_planner.dart`) use their own `Signal`
  type rather than `StoryLine`, precisely so nothing can hand one to the
  narrator — `speakBeat` takes `StoryLine`s and is the only route into TTS.
  Keep the types apart. Their text is fixed when the notification is
  *scheduled*, not when it fires, since no Dart runs at fire time; that is why
  `AppState` re-plans on load, on a settings change and after every run.
- **A notification body is one line unless you ask for more.** Android collapses
  it and truncates the rest, so every signal needs
  `BigTextStyleInformation`; signals run to 180 characters and most of one was
  being cut. Tapping opens the timeline at that message. The notification's
  `payload` carries speaker and text, which is how the tap knows *which* entry
  to scroll to — and, for a notification scheduled before the signal log
  existed, the only record of what was said, so the timeline shows it at the
  top rather than not at all. `SignalScheduler.decodePayload` returns null rather
  than throwing for anything it does not recognise: a tap must not be able to
  take the app down.
- **`onDidReceiveNotificationResponse` never fires for a cold start.** The
  plugin forwards a plain `SELECT_NOTIFICATION` only through `onNewIntent`,
  which needs an activity that was already running; its `onAttachedToActivity`
  handles foreground action buttons and nothing else. So a tap that *launched*
  the app reaches Dart only via `getNotificationAppLaunchDetails`, and that is
  the usual case — a signal arrives hours after the app was last open and
  Android has long since killed the process. `SignalTaps` reads both routes and
  de-duplicates, since a warm tap can be reported twice. Relying on the
  callback alone looked fine in every test and failed on every real tap.
- **A re-plan cancels only what is still pending.** It runs on every launch,
  and Android's `cancel(id)` also removes a notification already on screen —
  so sweeping the whole id range made opening the app (without tapping the
  notification) wipe the unread message. `SignalScheduler` cancels the ids
  `pendingNotificationRequests` lists, and `sparingShown` moves a new signal
  off any id still in the shade, since a later notification under the same id
  would replace it when it fires.
- **After an upgrade the first signal is the *old* build's.** The manifest
  declares `MY_PACKAGE_REPLACED`, so the plugin re-arms the stored schedule
  after an install — and what it stored was written by the previous version,
  payload, style and all. Testing a change to how signals are built means
  opening the app once first, which re-plans and replaces ids 7000–7199.
  Otherwise the next notification still behaves the old way and looks like the
  change did not work. That cost a round trip.
- **Notification channel importance is frozen at creation.** `signals_reminder`
  is `IMPORTANCE_DEFAULT` (an ordinary alert) and `signals_ambient` is
  `IMPORTANCE_LOW` (silent). So is `run_paused`, the paused-run reminder
  `MissionService` posts itself — audible because the run's own channel is
  silent by design. A later update cannot raise any of them, only the
  runner can in Android settings, so changing them means a new channel id.
- **Three things about that notification are load-bearing**, and none of them
  fail loudly: `FOREGROUND_SERVICE_IMMEDIATE`, or Android 12+ defers it by up
  to ten seconds; `R.drawable.ic_notification` plus `res/raw/keep.xml`, or the
  resource shrinker strips an icon only ever resolved by name, the small icon
  resolves to 0, and Android silently replaces the whole notification with its
  own "app is running" placeholder; and that icon being a transparent
  silhouette, since only its alpha channel survives.

## A run must survive the app being closed

A runner lost a whole run by swiping the app away mid-run: `onTaskRemoved`
stopped the service, and the Flutter engine — where the run lives — died with
the activity. Two things now prevent that, and both are needed:

- **The engine outlives the activity while a run is active.** `MainActivity`
  provides its engine from `FlutterEngineCache` and destroys it only when
  `MissionService.running` is false, decided in `onDestroy` (Flutter also asks
  when another activity takes the engine over, and answering true then is an
  `AssertionError`). Every platform channel is installed once per engine, with
  the application context, in `provideFlutterEngine` — not in
  `configureFlutterEngine`, which runs again per activity and would orphan the
  GPS listener under a live run. Don't reintroduce `stopSelf()` in
  `onTaskRemoved`.
- **The run in progress is on disk.** The run screen saves
  `RunEngine.snapshot()` to `active_run.json` every 15 s of running, and at once
  when the goal is met, and clears it after the finish is recorded. A snapshot
  left on the next launch is a run the process died in, offered back on the home
  screen to keep or discard. `clearIf` takes the run's id, so a late decision
  about an old run never deletes a newer run's copy.

The notification's Pause/Resume and Stop ride on the same arrangement:
`MissionService.onAction` is set once per engine in `installChannels` and calls
`noticeAction` on the engine's channel, so the buttons reach the run with no
activity attached. Pause and Resume go to the service directly; Stop opens the
app with an extra, because ending short of the goal asks first; past the goal
it is labelled Complete and finishes at once, as the screen's Complete does. The actions
have no icons on purpose — Android has not drawn them since 7.0, and an icon
resolved only there is one more thing for the shrinker to strip.

Neither is reachable from the test suite: swipe a live run away on a device
before believing the first one works.

## Gradle config that looks wrong but isn't

- `android/app/build.gradle.kts` sets `ndkVersion`. It is genuinely required:
  `path_provider_android` pulls in `package:jni`, which compiles `dartjni.c`.
  Removing it breaks the build.
- `android/build.gradle.kts` raises every plugin module to the app's `compileSdk`.
  Several plugins still pin `android-35`; without this the machine needs every
  historical SDK platform installed.
- `android/app/build.gradle.kts` excludes the `com.google.android.gms` group,
  and position fixes come from the app's own `GpsStream.kt`, which asks the
  `LocationManager` for the GPS provider by name. That pair is what keeps the
  app free of Play Services. `proguard-rules.pro` exists only to `-dontwarn`
  the references this leaves dangling. Removing any one of the three silently
  reintroduces a proprietary dependency — verify with a dexdump for classes
  under `com/google` before believing otherwise. Re-run that check after adding
  any plugin, not just after touching these three.
- **Do not go back to geolocator's position stream.** geolocator is kept only
  for the permission and location-service checks. Its `LocationManager` client
  prefers the ROM's *fused* provider on Android 12+ regardless of
  `forceLocationManager`, and on a de-Googled device that provider is whatever
  the vendor shipped: on at least one such device it accepted requests and
  never delivered a fix, so a run watched a healthy, empty stream.
  `appops get <pkg>` tells the two apart — a request that reached the GNSS
  chip shows `MONITOR_HIGH_POWER_LOCATION`, a fused one only
  `MONITOR_LOCATION`.
- **`isLocationServiceEnabled()` does not mean GPS works.** It answers "is
  location on at all", and battery-saver location mode leaves network location
  on while switching the GPS provider off: permission granted, service enabled,
  readiness `ready`, and not one fix. `GpsStream.kt` reports it as a
  `gpsDisabled` stream error — both at subscription and via
  `onProviderDisabled` mid-run — which `location_service.dart` turns into
  `LocationUnavailable` and the engine into a `LocationTrouble` the run screen
  can show. Keep the error codes on those two sides in step; nothing checks
  them for you. A swallowed stream error here recorded a real two-hour run as
  time-only with nothing on screen to explain it.
- **The location warning has to clear as well as appear.** `GpsStream.kt`
  registers the `LocationListener` *before* reporting a disabled provider, and
  `RunEngine` subscribes to `fixes()` whether or not `prepare` said yes —
  returning early, or subscribing only on success, leaves nothing watching, so
  the provider can come back on and no fix ever arrives to say so. The warning
  then sticks for the whole run, which it did on the 0.4.0 release run. Recovery
  is `LocationRestored`, emitted on the first fix of *any* accuracy, since the
  warning is about no fixes at all; `LocationTrouble` is raised once per change,
  because a provider will report itself off repeatedly.

## Before a release: one real outdoor run

The test suite cannot exercise audio focus or GPS, so every release is preceded
by a real run outdoors on a device: fixes arrive and distance accumulates with
the screen off, music ducks for a line and comes back afterwards, and the story
beats fire. Treat a report about any of those as a regression, not as new
information.
