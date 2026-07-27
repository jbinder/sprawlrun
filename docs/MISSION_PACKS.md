# Mission pack format

A mission pack is a single JSON file. The campaign that ships with the app —
`assets/missions/sprawl_prime.json` — uses exactly the same format as anything
you add later, so it doubles as a worked example.

## Where packs are loaded from

1. **Bundled**: every path listed in `MissionRepository.bundledPacks`
   (`lib/data/mission_repository.dart`) and declared under `assets:` in
   `pubspec.yaml`.
2. **Side-loaded**: any `*.json` inside the app's documents directory at
   `sprawlrun/mission_packs/`, loaded alphabetically after the bundled ones.

Side-loading needs no rebuild — drop the file in and hit **Settings → Mission
packs → Reload packs**. A pack whose `id` matches a bundled pack replaces it,
which is how you patch shipped content.

A malformed pack never breaks the app: it is skipped, and the parse error is
listed in Settings.

## Shape

```jsonc
{
  "id": "sprawl_prime",              // stable; used for replacement
  "title": "SPRAWL PRIME",
  "tagline": "Ten runs through the BAMA corridor.",
  "missions": [ /* Mission */ ]
}
```

### Mission

```jsonc
{
  "id": "sp01",                       // unique across the pack
  "order": 1,                         // 1-based; drives the locked chain
  "codename": "DEAD DROP",            // short, shown large
  "title": "Dead Drop on Ninsei",
  "location": "Night Market / Ninsei Strip",
  "objective": "One line: what the runner is doing.",
  "brief": "Pre-run text. Newlines are fine.",
  "debrief": "Shown after a successful run.",
  "epilogue": "Optional. Shown after the last mission of a pack.",
  "suggestedGoal": { "type": "time", "value": 900 },
  "codex": [ /* CodexEntry */ ],
  "beats": [ /* StoryBeat */ ]
}
```

`suggestedGoal.type` is `time` (seconds) or `distance` (metres). It is only a
default — the runner picks their own target on the brief screen, and everything
below scales to whatever they choose.

Missions unlock strictly in `order`. Exactly one mission is playable at a time:
the lowest-order one not yet completed.

### StoryBeat

A beat is one interlude. It takes audio focus, speaks its lines in order, then
hands focus back.

```jsonc
{
  "id": "sp01_b4",                    // unique within the mission
  "headline": "TAIL DETECTED",        // optional HUD banner
  "at": { "fraction": 0.46 },         // when it fires — see below
  "unlocksCodex": "cdx_courier",      // optional
  "lines": [ /* StoryLine */ ],
  "chase": { /* Chase */ }            // optional
}
```

**Triggers.** `at` accepts any combination of:

| key | meaning |
|---|---|
| `fraction` | 0..1 of goal completion. Scales to the runner's chosen target. |
| `seconds` | absolute elapsed seconds |
| `meters` | absolute distance covered |

The beat fires as soon as *any* present threshold is crossed. `fraction` is the
right default: it makes a mission pace itself the same whether the runner picked
15 minutes or 10 kilometres.

Beats fire strictly in array order — a beat never overtakes an earlier one — and
at least 45 seconds apart, so two beats coming due together are spaced out rather
than stacked. Write them in ascending trigger order.

Convention used by the shipped campaign: a beat at `fraction: 0.0` to open, eight
or so in between, one at `fraction: 1.0` for the moment the target is met, and
one more at `fraction: 1.0` that lands about a minute later for runners who keep
going.

### StoryLine

```jsonc
{
  "speaker": "KESTREL",
  "text": "Channel's clean. Good.",
  "sfxBefore": "alert",               // optional, filename in assets/sfx/
  "sfxAfter": null,
  "pauseAfterMs": 260
}
```

`speaker` selects both the on-screen colour and the synthesised voice (pitch and
rate). The shipped voices are `KESTREL`, `HALCYON`, `SIX`, `PACHINKO`, `VANTAR`
and `SYSTEM`; see `VoiceProfile.bySpeaker` in `lib/services/narrator.dart` to add
more. An unknown speaker still works — it just gets the neutral voice.

Keep lines short. They are spoken aloud to someone who is running, and the tests
enforce a 260-character ceiling.

Available effects are whatever `tool/gen_sfx.dart` produces: `alert`,
`chase_start`, `chase_clear`, `chase_failed`, `glitch`, `objective`,
`goal_reached`, `heartbeat`, `unlock`, `comm_open`, `comm_close`,
`mission_success`, `mission_fail`, `ui_tap`, `ui_back`, `drone`.

`comm_open` and `comm_close` are played automatically around every beat — you do
not need to add them.

### Chase

Attaching a `chase` to a beat opens a timed pursuit as soon as the beat's lines
finish.

```jsonc
{
  "seconds": 60,
  "paceFactor": 1.1,
  "pursuer": "MAINTENANCE DRONE",
  "escaped": [ /* StoryLine */ ],
  "caught":  [ /* StoryLine */ ]
}
```

The runner escapes if they cover `baseline × paceFactor × seconds` metres inside
the window, where `baseline` is *their own* speed over the preceding three
minutes. A chase is therefore equally hard for a 7:00/km jogger and a 4:00/km
racer, and impossible for neither. `paceFactor` between 1.1 and 1.25 is a real
effort without being a sprint.

Chases can be turned off entirely in Settings; a mission with all its chases
disabled still plays every line.

### CodexEntry

```jsonc
{
  "id": "cdx_courier",
  "title": "Meat Courier",
  "category": "TRADE",                // free text; groups the codex screen
  "body": "A paragraph of world-building."
}
```

Entries appear in the Codex tab only after the beat whose `unlocksCodex` names
them has actually played. Define an entry in the same mission that unlocks it.

## Validating a pack

`test/campaign_test.dart` checks the shipped campaign for ordering, dangling
codex references, missing sound effects, over-long lines, malformed chases and
more. Point it at your own file to get the same checks.
