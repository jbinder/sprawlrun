# Mission pack format

A mission pack is a single JSON file. The campaign that ships with the app —
`assets/missions/sprawl_prime.json`, and the second, `null_tide.json` — use
exactly the same format as anything
you add later, so it doubles as a worked example.

## Where packs are loaded from

1. **Bundled**: every path listed in `MissionRepository.bundledPacks`
   (`lib/data/mission_repository.dart`) and declared under `assets:` in
   `pubspec.yaml`.
2. **Imported**: **Settings → Mission packs → Import pack** opens the system
   file picker. No rebuild, no app update, no storage permission.

An imported pack is stored under its own `id`, so importing a revised version
replaces the old one — that is the edit-and-reload loop while writing a pack.
A pack whose `id` matches a bundled pack replaces that too, which is how you
patch shipped content; removing it brings the shipped version back. Removing a
pack never touches progress, which is recorded by mission id, so importing it
again picks up where the runner left off.

The `id` may only use letters, digits, `-` and `_`, since it becomes the file
name. A file that is not a pack, has no missions, or repeats a mission id is
refused at import with the reason, and nothing is stored. A pack that imports
but later fails to load is skipped, with the error listed in Settings.

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

Missions unlock strictly in `order` *within their pack*. Exactly one mission per
pack is playable at a time: the lowest-order one not yet completed. Packs are
independent — clearing one never gates another — and the runner chooses which
pack the ops screen shows from **All packs**. When the last mission of a pack is
cleared, the debrief offers the next pack in load order that still has missions
open.

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

### Signals

Messages a handler sends **between** runs, delivered as notifications. Optional,
and they can sit on the pack, on a mission, or both.

```jsonc
"signals": {
  "reminder": [                       // nudges to go running
    { "from": "KESTREL", "text": "Courier job is still open. One package, one pickup, no questions." }
  ],
  "ambient": [                        // unprompted traffic; the city talking
    { "from": "PACHINKO", "text": "Someone is selling your gait signature in the night market. Badly." }
  ]
}
```

A pack pool is required — it is the fallback for a finished campaign. Mission
pools are optional in the format, but the shipped campaigns give every mission
two of each, and `campaign_test.dart` holds them to it.

On the **pack** they are generic: valid at any point, and the only thing left to
say once the campaign is finished. On a **mission** they belong to that mission
*while it is the one waiting to be run*, so a runner between operations hears
about the operation ahead of them. Both pools are drawn on together, which is
what stops a runner who goes out daily from seeing the same two lines all week.

Three rules, none of which the app can check for you:

- **No spoilers.** A mission's signals may only lean on what its `brief`
  already tells the runner, or on missions they have finished. They are read
  before the mission is played, not after.
- **Never a repeat of a beat.** These are newly written lines. Nobody wants to
  be told again what they already heard on a run.
- **Never spoken.** Signals are text in the notification shade and are never
  passed to the narrator, so they do not have to scan when read aloud.

`from` must be a speaker the narrator knows, the same as a `StoryLine` — it sets
the name on the notification. Keep the text under 180 characters; Android
truncates beyond roughly that, and `campaign_test.dart` enforces it.

### The weekly debrief

A third pool, pack-level only, because a debrief is about the runner's week
rather than whichever operation is waiting:

```jsonc
"signals": {
  "debrief": {
    "met":    [ { "from": "KESTREL", "text": "Week's closed and you are on the right side of it." } ],
    "missed": [ { "from": "SIX",     "text": "Short. There is still road left, and it is still Sunday." } ],
    "idle":   [ { "from": "KESTREL", "text": "Nothing on the board from you this week." } ]
  }
}
```

Only the **opening line** is yours. The app appends the figures — how far
against the target, how long the streak has stood — because those are different
every week and cannot be written in advance. So keep an opener under ninety
characters, say nothing specific about the numbers, and let it work for any
week that went that way. `campaign_test.dart` enforces the length and that all
three outcomes have copy: a runner who missed their target gets a message
exactly when silence would be least welcome.

**Treat a shipped line as fixed.** The app keeps every signal it has sent in
an archive the runner can scroll back through, and it stores a reference to
the line rather than a copy of it. Reword a line in a later version of your
pack and every past instance of it quietly drops out of that archive. Adding
new lines is always safe; changing old ones costs runners their history.

Write plenty of ambient lines. Nothing repeats until the pool is exhausted, so
the pool size is how long the noise stays fresh: a runner who asks for the
maximum fourteen a week works through twenty lines in ten days. The shipped packs
carry twenty generic ones each, and that is a floor rather than a target.

## Validating a pack

`test/campaign_test.dart` checks the shipped campaign for ordering, dangling
codex references, missing sound effects, over-long lines, malformed chases and
more. Point it at your own file to get the same checks.
