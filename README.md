<div align="center">

<img src="docs/icon.png" width="104" alt="">

# SPRAWL//RUN

### Your running app should not be a spreadsheet. It should be chasing you.

Two campaigns, twenty story missions through a rain-slick megacity — and every
October, a third that only opens while the dead are on the network. GPS-tracked,
voice-acted by your phone, and built around one idea: *somebody is waiting for
you to slow down.*

**Android · Flutter · completely offline · no Google Play Services · no accounts, no ads, no tracking**

<br>

<a href="https://f-droid.org/packages/io.github.jbinder.sprawlrun"><img src="https://fdroid.gitlab.io/artwork/badge/get-it-on.png" alt="Get it on F-Droid" height="80"></a>
<a href="https://github.com/jbinder/sprawlrun/releases/latest"><img src="https://raw.githubusercontent.com/Kunzisoft/Github-badge/main/get-it-on-github.png" alt="Get it on GitHub" height="80"></a>

<a href="https://hosted.weblate.org/engage/sprawlrun/"><img src="https://hosted.weblate.org/widget/sprawlrun/svg-badge.svg" alt="Translation status"></a>

<br>

<img src="docs/screenshots/dashboard.png" width="248" alt="Dashboard">
<img src="docs/screenshots/run-hud.png" width="248" alt="Run HUD during a pursuit">
<img src="docs/screenshots/briefing.png" width="248" alt="Mission briefing">

</div>

---

## You are a courier in the Sprawl

A job on the Ninsei strip. One package, no questions. It pays enough to matter
and it is almost certainly a trap.

Twenty minutes later you are running through a drainage tunnel with a
containment shell that will not stop transmitting, and a voice you have never
heard says:

> *"Oh. You are very loud. I mean that kindly. Your heart is the loudest thing
> I have heard in nineteen years, four months, and some days I did not count
> properly. Please do not stop. I am using it to know which way is up."*

Ten missions later you are forty floors up a corporate arcology, and the only
thing keeping an intelligence alive is whether you keep running.

That's **Sprawl Prime**. Finish it and **Null Tide** opens: the southern
districts went under eleven years ago, something in Pump House Seven has been
apologising for nine seconds a night ever since, and a salvage broker with a
bad knee wants a piece of paper carried across the Drowned Mile before the sea
comes home.

---

## Somebody is chasing you

<table>
<tr>
<td width="58%">

A drone tags your gait on Ninsei. Collections kick in a clinic door. A corporate
trace walks the cooling loop toward you.

**You have ninety seconds.**

Here is the part that matters: the chase is scaled to *you*. To escape, you have
to beat your own pace from the last three minutes — not some number a designer
picked. It is a genuine effort whether you run 4:00/km or 7:00/km, and it is
never impossible.

Don't want that? Switch pursuits off. The story still plays.

</td>
<td width="42%"><img src="docs/screenshots/run-hud.png" alt="A pursuit in progress"></td>
</tr>
</table>

## You set the target

<table>
<tr>
<td width="42%"><img src="docs/screenshots/target.png" alt="Choosing a target"></td>
<td width="58%">

Before every mission you choose: a time, or a distance. Twelve minutes or
twenty-one kilometres — **the story paces itself to fit whatever you pick.**

Hit the target and the operation succeeds. Stop short and it fails, stays open,
and you run it again whenever you like.

And if you're having a good day, just keep going. Everything past the target
still counts, and your handler will have something to say about it.

</td>
</tr>
</table>

## The numbers, when you want them

<table>
<tr>
<td width="33%"><img src="docs/screenshots/stats.png" alt="Stats"></td>
<td width="33%"><img src="docs/screenshots/history.png" alt="History"></td>
<td width="33%"><img src="docs/screenshots/achievements.png" alt="Achievements"></td>
</tr>
<tr>
<td>Distance, time, calories and cleared missions for this week and this month,
with per-day bars and your full run log. Swipe either card to step back through
earlier weeks and months, all the way to your first run. Calories come from the
ACSM metabolic equations and your body mass — no invented multipliers.</td>
<td>The long view: distance per month since day one, and every month as a dot
calendar lit by how far you ran. Tap a month or a day to see the runs behind
it.</td>
<td><b>73 achievements</b> across eight categories and four tiers. Progress is
recomputed from your run log every time, so it can never drift out of step with
what you actually did.</td>
</tr>
</table>

**Streaks that don't punish you for Monday.** Pick your own weekly commitment —
minutes, kilometres, or missions. A week still in progress never breaks a
streak; only a finished week that fell short does.

**And it is yours to take with you.** Settings → Data exports everything the app
knows — profile, campaign progress, achievements, codex, and every run with its
GPS trace — as one plain JSON file, handed to the share sheet. Importing it back
either *replaces* this device (a clean restore onto a new phone) or *merges*,
adding runs and progress this device is missing while keeping its own settings.
Merging only ever adds, so bringing in an old backup cannot relock a mission.
No storage permission is involved in either direction: export goes out through
the share sheet, import comes in through the system document picker.

**Or let it back itself up.** Optionally, choose a folder once and a backup is
written there after every run, keeping the three newest. Pick one that Syncthing
or a similar app copies to another device, and the run log survives losing the
phone, without the app ever going online. Android's folder picker grants access
to that one folder and nothing else.

**Single routes travel too.** Any stored run opens onto its map; the share
action there writes the trace as a **GPX 1.1** track, which OsmAnd, Strava,
Komoot or any other map app will open.

## A world worth reading

<table>
<tr>
<td width="58%">

Black clinics. The Turing Registry. Simstim. The service spine of an arcology
that nobody admits exists.

Entries unlock only once a character has actually mentioned them to you — the
codex is a record of what you have been told, not a wiki you can read ahead in.

Forty-eight entries across the three packs.

</td>
<td width="42%"><img src="docs/screenshots/codex.png" alt="Codex"></td>
</tr>
</table>

## Every October, the dead come back online

From 10 October to All Souls the city dresses for it: the neon turns to
pumpkin and violet, a graveyard rises on the skyline under a low moon, ghosts
drift across the screen and the sound effects take on bells and whispers. A
four-run operation opens for the season only, **SAMHAIN PROTOCOL**, about a
courier three years dead whose last delivery is still on the board. Its
handlers cut in on whichever campaign you are playing, and progress keeps until
next October if you do not finish. One switch in Settings turns it all off.

## Everything it does

**Story**
- Twenty missions across two campaigns, paced to the target you pick
- Seasonal events: from 10 October to 2 November the app takes on a Halloween
  look and sound, with a four-mission operation of its own — switchable off
- Four colour themes to pick from in Settings — neon, synthwave, glacier and
  volt — or import your own; a season dresses over them while it lasts
- Optional reminders from your handler on the days and at the time you choose,
  written in the voice of the campaign you are playing
- Optional signal noise: the city talking between runs, silent, never overnight,
  as often or as rarely as you like
- The wire: everything, newest first — your handler's messages, runs, cleared
  operations, achievements and intel. Tapping a notification opens it there,
  and a dot on its icon says a signal came in since you last looked
- A weekly debrief on Sunday evening — on by default, switchable off — reading
  your week back against your own target while there is still time to save it
- Eleven characters across the packs, each with its own synthesised voice,
  generated on the device
- Pursuits scaled to your own pace from the last three minutes — or switched off
- A codex of forty-eight entries that unlock only once a character has mentioned them
- Every run keeps a story log; cleared missions open onto a debriefing of every attempt
- Importable mission packs: pick a JSON file and it appears; import a newer version to
  update it, remove it without losing progress

**Running**
- GPS tracking that keeps going with the screen off, or with the app swiped away, with
  auto-pause; a run the app dies in is kept and offered back
- Pause, resume or stop from the notification, without unlocking into the app;
  a run left paused is brought up after 15, 30 and 60 minutes, then left alone
- A time or distance target per run, and free runs with no story at all
- Walk instead of run, chosen on the briefing: the same missions at walking pace, with
  pursuits scaled to a brisk walk rather than a jog. Walks count for totals and the
  streak, earn their own achievements and set no pace record
- Kilometre (or mile) splits read out with the split and total time — on a mission they
  wait for the scene to end; switchable off
- Live HUD: distance, pace, elapsed, goal ring, and the pursuit bar
- Calories from the ACSM metabolic equations and your body mass
- Optional step counting from the phone's own step sensor: steps and cadence per run,
  and moving time that keeps counting when the GPS drops out. Off by default, since it
  needs Android's physical-activity permission, which is asked for only when you turn it on
- Distance from steps where there is no GPS — a treadmill, a tunnel, a run indoors — at
  a stride learned from your own runs with GPS, starting from your height until it has
  measured enough. Marked `≈`, and never a pace record
- Route drawn as a neon trace, replayed at the pace you actually ran it

**Progress**
- This week and this month at a glance, steppable back to your first run
- A long-term history: distance per month, and every month as a dot calendar
- 73 achievements across eight categories and four tiers — walks earn their own
- A weekly streak you define yourself — minutes, kilometres or missions
- Full run log, grouped by month, with every run's detail and trace

**Audio**
- Your music ducks for a transmission and is forced back if the player sulks
- Optional ambient synth bed for when you bring no music of your own
- Adjustable speech rate and effects volume; story voice can be silenced

**Language**
- English and Spanish, following the phone's language or picked in Settings; the
  split readout is spoken in it too
- The story too: all three campaigns are in Spanish, and a community pack can carry
  its own translations. A mission switches language only when all of it is
  translated, so a scene never changes language partway through
- Translated lines are spoken by an offline voice of that language when the phone
  has one; otherwise in the English original, and the briefing says why
- Place and character names stay as they are, so every runner calls them the same

**Your data**
- Export and import everything as one JSON file — profile, progress, runs, traces
- Import either replaces this device or merges, and merging can never relock a mission
- Optional automatic backup after every run to a folder you choose, keeping the three newest
- A reminder to export once your log holds runs that exist nowhere else, dismissable
- Any single route exports as a GPX 1.1 track for OsmAnd, Strava or Komoot
- No accounts, no ads, no analytics, no network permission, no Play Services

---

<div align="center">

### Twenty-four missions. Three packs. 592 lines of dialogue. No network required.

</div>

---

<br>

# Technical

Flutter, targeting Android first with iOS scaffolding already in place. Built
against Flutter 3.44.8 / Dart 3.12.

## Building

```bash
flutter pub get
flutter run                    # debug, on a connected device
flutter build apk --release    # or: flutter build appbundle
```

Grant location when asked. Missions with a **time** target work fine without it;
distance targets obviously do not.

Requires **JDK 17**. Newer JDKs break AGP's `jdkImage` transform, so if your
default JDK is newer, point Flutter at a JDK 17 installation with
`flutter config --jdk-dir <path-to-jdk-17>`.

Release builds are signed from `android/key.properties` — copy
`android/key.properties.example` and fill it in. Without that file the release
APK comes out **unsigned**, which is what F-Droid's build server needs; sign it
yourself before installing one.

Android SDK notes, learned the hard way:

- `path_provider_android` pulls in `package:jni`, which compiles native code, so
  the **NDK is required** (`ndk;28.2.13676358` and `cmake;3.22.1`).
- `android/build.gradle.kts` raises every plugin module to the app's
  `compileSdk`. Several plugins still pin `android-35`, and without this you
  would need every historical SDK platform installed just to build. `minSdk` and
  `targetSdk`, which actually affect runtime behaviour, are untouched.

## Tests

```bash
flutter analyze                # clean
flutter test                   # 618 tests
```

The run engine takes its location source, narrator and clock by injection, so
`test/run_engine_test.dart` plays whole missions against synthetic GPS in
milliseconds — distance filtering, auto-pause, beat ordering, chase adjudication
and degraded-GPS behaviour. `test/campaign_test.dart` validates the shipped story
JSON. The widget tests drive the real screens against real storage.

## Generated assets

Nothing in this repo is a binary of uncertain origin. The sound effects, the
launcher icons and the screenshots above are all produced by code:

```bash
dart run tool/gen_sfx.dart                      # synthesises assets/sfx/*.wav
dart run tool/gen_icons.dart                    # renders every launcher icon
flutter test tool/screenshots/capture_test.dart # regenerates docs + store screenshots
```

The screenshot tool drives the real widgets with seeded data, so the images in
this README cannot drift from what the app actually looks like.

## Contributing

Translations, mission packs, colour themes, bug reports and code are all
welcome, and only code needs Flutter installed. **[CONTRIBUTING.md](CONTRIBUTING.md)** says how.
Translators go straight to **[docs/TRANSLATING.md](docs/TRANSLATING.md)**.

### Translations

<a href="https://hosted.weblate.org/engage/sprawlrun/"><img src="https://hosted.weblate.org/widget/sprawlrun/multi-auto.svg" alt="Translation status"></a>

Translated by the community on
[Weblate](https://hosted.weblate.org/engage/sprawlrun/), and improving as it
goes — corrections are welcome there. Thanks to
[Hosted Weblate](https://weblate.org/) for hosting the translations of this
libre project for free.

- **Spanish** — [@cristian01215](https://github.com/cristian01215)

## Adding missions

A mission pack is one JSON file. Import it with **Settings → Mission packs →
Import pack** — no rebuild, no app update, no storage permission. See **[docs/MISSION_PACKS.md](docs/MISSION_PACKS.md)** for
the format, and `assets/missions/sprawl_prime.json` or `null_tide.json` for a
worked example.

Every pack is its own campaign with its own chain of missions. The ops screen
shows one at a time; **All packs** lists them all, grouped into active and done,
and finishing the last mission of a pack offers the next one that's still open.

## Adding colour themes

A colour theme is one small JSON file: a name and fourteen colours, each
named for its role (`primary`, `hostile`, `story`, `success`…) rather than its
hue. Import your own with **Settings → Identity → Colours → Import theme**,
with no rebuild needed. To ship one with the app, add it to `assets/themes/` in
a pull request. The app finds it there by itself, and `test/theme_test.dart`
checks that it stays readable. See **[docs/THEMES.md](docs/THEMES.md)** for the
format, the rules and `glacier.json` as a worked example.

## Layout

```
lib/
  models/       Mission, StoryBeat, RunGoal, RunRecord, Profile, Achievement
  data/         JSON repositories (runs, profile, mission packs, themes) + backup + GPX
  services/     run_engine · narrator · location · stats · energy · achievements
  state/        AppState — the single source of truth the UI reads
  screens/      dashboard · brief · run HUD · summary · stats · history · wall · codex · settings
  widgets/      backdrop · panels · glitch text · rings & bars · route trace
  theme/        palette, colour themes, seasons and typography
  l10n/         interface text: app_en.arb is the source, app_<lang>.arb the translations
assets/missions/l10n/  story text: <pack>_en.arb is generated from the pack, <pack>_<lang>.arb translates it
assets/themes/  the shipped colour themes, one JSON file each
tool/           SFX, icon, screenshot, pseudo-locale and pack-string generators
```

Some notes on the shape of it:

- **`RunEngine` owns no persistence and no UI.** It consumes a `LocationSource`
  and a `Narrator` and emits state plus an event stream. That is what makes a
  25-minute mission testable in milliseconds.
- **Derived data is always derived.** Stats, streaks and achievement progress are
  pure functions of the run log, recomputed on change rather than maintained as
  counters that can fall out of step.
- **Elapsed time comes from the wall clock**, not from counting timer ticks, so
  backgrounding the app cannot lose time.
- **Distance is filtered, not trusted.** Fixes worse than 35 m accuracy are
  dropped; steps under the noise floor hold the reference point rather than
  advancing it, so slow movement accumulates instead of being thrown away;
  physically impossible jumps are rejected until several in a row suggest the
  device really did move.
- **Distance from steps is a fallback, and says so.** Steps become distance only
  after five seconds without a fix, and the first fix back starts the GPS over
  from where it is rather than adding the straight line across the gap. The
  stride is derived like everything else: each run stores what it measured —
  steps and GPS distance over the same seconds, split into walking and running
  by cadence — and the last 30 runs give the stride, with height only as the
  first guess. A run with a tenth or more of its distance from steps shows it
  as `≈` and sets no pace record; it has no trace to draw.
- **Auto-pause requires a live GPS.** With no fixes arriving there is no way to
  tell a stopped runner from a lost signal, and freezing the clock would quietly
  ruin a time-based mission.

## Deliberate omissions

- **No maps.** Tiles need a network. Routes are drawn from the stored trace as a
  neon filament on a grid.
- **No accounts or sync.** There is no `INTERNET` permission in the manifest.
  Backups move by hand: exporting hands a file to the system share sheet and
  importing reads one back through the system document picker, so the app needs
  no storage permission and never sees a file you did not choose. Automatic
  backups go to a folder chosen in the system folder picker, which grants that
  one folder; getting them off the phone is left to a sync app of your choice. The merged
  manifest carries two things it did not ask for directly — `ACCESS_NETWORK_STATE`,
  pulled in by ExoPlayer via `just_audio`, which reads connectivity status and
  grants no network access; and a self-defined
  `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` from `share_plus`, which only lets
  the app receive its own share-result broadcast. Without `INTERNET`, nothing
  here could reach the network regardless.
- **`android:allowBackup` is left at Android's default**, which is `true`. That
  means the OS backup agent may copy the run log to the user's Google account if
  they have device backup switched on — the app never does this itself and could
  not, but the data can still leave the device by that route. Setting it to
  `false` would close that path and also disable device-to-device transfer; the
  deliberate choice is to leave the platform behaviour alone and say so plainly
  rather than to claim more isolation than the app actually has.
- **No Google Play Services.** `geolocator_android` declares
  `play-services-location`, which is proprietary. The app module excludes the
  `com.google.android.gms` group so it never reaches the APK, and sets
  `forceLocationManager: true` so the AOSP `LocationManager` is used directly.
  Verified: zero classes under `com/google` are defined in the shipped dex. The
  cost is a slower first fix and marginally worse battery than the fused
  provider; the gain is that the app is free software all the way down and runs
  identically on a de-Googled ROM.
- **No `ACCESS_BACKGROUND_LOCATION`.** Tracking with the screen off works through
  a foreground service, which is the narrower permission and the one Play Store
  review does not treat as a special case. Every run holds one, and it posts the
  ongoing notification counting down whatever target you set — Android requires
  a notification for a foreground service, and it is the honest signal that a
  mission is live. It is the only notification the app ever shows, which is what
  `POST_NOTIFICATIONS` is asked for; refuse it and tracking is unaffected, only
  the notice is hidden. A mission started with no GPS keeps the same service
  under `FOREGROUND_SERVICE_SPECIAL_USE` rather than claiming a location it does
  not have, so a time-target run cannot be frozen in a pocket halfway through
  the story.
- **No heart rate or cadence.** Nothing here needs a strap, and inventing an
  effort metric from GPS alone would be worse than not having one.

## Licences

App code is **[MIT](LICENSE)**.

Bundled fonts are SIL Open Font License 1.1 — Orbitron, Rajdhani and Share Tech
Mono, with their licence texts alongside them in `assets/fonts/`. All audio and
artwork is generated by the scripts in `tool/` and carries the same MIT terms as
the rest of the code.
