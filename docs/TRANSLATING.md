# Translating SPRAWL//RUN

Thank you for helping. Translations happen on **Weblate** — no git, no code, just
the strings and a description of where each one appears:

**→ https://hosted.weblate.org/projects/sprawlrun/** *(project being set up)*

Whatever you translate arrives in the app as a pull request the maintainer
reviews. A language does not have to be finished to ship: any string not yet
translated simply shows in English.

## What there is to translate

| Weblate component | What it is | Where it shows |
|---|---|---|
| **App** | Every word of the interface: buttons, labels, settings, achievements, notifications, the spoken kilometre readout | The app |
| **Android** | Notification channel names, the run notification's buttons, the paused-run reminders | Android's notification shade and settings |
| **Store listing** | Title, one-line summary and description | F-Droid |

**The story is not translatable yet.** Mission briefings, dialogue, codex
entries and the messages characters send between runs live in the mission
packs, and stay in English for now. Translating them is planned; the interface
comes first.

## Rules

- **Names stay as they are, in every language.** Places, characters, campaigns,
  missions and gangs — the Sprawl, the Ninsei strip, the Drowned Mile, KESTREL,
  SPRAWL PRIME, NULL TIDE, PANTHER MODERN, SAMHAIN PROTOCOL, SPRAWL//RUN itself.
  Runners talk to each other about these places; they should all call them the
  same thing. Grammar around a name is yours to adapt ("el Sprawl").
- **Keep every `{placeholder}` exactly as written.** `{count}`, `{pack}`,
  `{date}` are filled in by the app. Move them wherever your grammar needs them.
- **Plurals: keep the structure, fill in every branch.** A message like
  `{count, plural, =1{1 run} other{{count} runs}}` needs both the `=1` and the
  `other` text in your language. If your language has more plural forms, Weblate
  offers them.
- **Uppercase stays uppercase.** Most labels are set in capitals on purpose.
  Write them in capitals, accents included (OPERACIÓN, not OPERACION).
- **Short stays short.** Navigation tabs, tags and tier names sit in small
  boxes. The description says when a string has little room. A test renders
  every screen with text 40% longer than English, so ordinary growth is fine —
  but a navigation tab that is three times longer will be cut.
- **Spoken text is written for the ear.** Strings marked *SPOKEN ALOUD* are read
  by the phone's speech engine during a run. Write durations as words
  ("5 minutos 41"), never as `5:41`, which engines read as a time of day.
- **Tone:** terse, a little noir, never cute. The app talks to the runner the way
  a handler would. Spanish uses informal *tú*; pick what a handler would use in
  your language and keep it consistent.

## Glossary

The recurring terms, with the Spanish choices as an example of how they were
handled. Add your language's column in Weblate's glossary.

| English | Keep or translate | Spanish | Notes |
|---|---|---|---|
| SPRAWL//RUN | keep | SPRAWL//RUN | the app's name |
| the Sprawl | keep | el Sprawl | the city; a name |
| THE WIRE | keep | THE WIRE | the scrollback of everything; a name |
| SAMHAIN PROTOCOL | keep | SAMHAIN PROTOCOL | the Halloween event; a name |
| runner | keep or translate | runner | how characters address the player |
| handler | translate | contacto | the character who runs your missions |
| operation / OPS | translate | operación / OPS | a mission; OPS is also the home tab |
| briefing | translate | informe | the screen before a mission |
| debrief(ing) | translate | informe final / informe semanal | after a mission / the Sunday message |
| codex | translate | códice | the world-building entries |
| intel | keep or translate | intel | information that unlocks a codex entry |
| transmission | translate | transmisión | a story scene spoken during a run |
| pursuit | translate | persecución | a timed chase |
| signal | translate | señal | a message from a character between runs |
| signal noise | translate | ruido de señal | ambient messages, "the city talking" |
| streak | translate | racha | consecutive weeks meeting the target |
| target | translate | objetivo | the distance or time a run aims for |
| split | translate | parcial | the time for one kilometre or mile |
| callsign | translate | alias | the runner's name in the story |
| STREET · CHROME · ICE · LEGEND | translate (ICE may stay) | CALLE · CROMO · ICE · LEYENDA | achievement tiers; ICE is hacker jargon |

## Languages and fonts

The app's typefaces cover Western European languages (Spanish, French,
German, Italian, Portuguese, Dutch, the Scandinavian languages except Danish
and Norwegian Ø). **Polish, Czech, Hungarian, Danish, Norwegian, Greek,
Cyrillic, Arabic, Hebrew and CJK need a font change first** — open an issue on
GitHub before starting one, so the work does not render as boxes.

## Checking your work

Before a pull request from Weblate is merged, the maintainer runs the test
suite, which checks that each translation keeps its placeholders and that no
screen overflows in any shipped language on a small phone. Weblate itself flags
a broken placeholder or plural as you type. If you can build the app yourself,
`flutter test --dart-define=LOCALE=<code> tool/screenshots/capture_test.dart`
writes screenshots of every screen in your language to `build/`.
