# Translating SPRAWL//RUN

Thank you for helping. Translations happen on **Weblate** — no git, no code, just
the strings and a description of where each one appears:

**→ https://hosted.weblate.org/engage/sprawlrun/**

<a href="https://hosted.weblate.org/engage/sprawlrun/"><img src="https://hosted.weblate.org/widget/sprawlrun/multi-auto.svg" alt="Translation status"></a>

Whatever you translate arrives in the app as a pull request the maintainer
reviews. A language does not have to be finished to ship: any string not yet
translated simply shows in English.

## How it works, step by step

1. Open the project on Weblate and sign in (a GitHub account works).
2. Pick your language, or **Start new translation** if it is not listed yet.
   Before you begin a new one, read [Languages and fonts](#languages-and-fonts).
3. Start with the **App** component. It is most of the work and what runners
   see. **Android** and **Store listing** are short, and can wait.
4. Translate string by string. Each one comes with a description of where it
   appears, and the glossary terms are shown beside it. Weblate saves as you go,
   so you can stop at any point.
5. Read the [Rules](#rules) below once before starting. They are short.

Your work reaches the app with the next release after the maintainer merges it.
To review an existing language rather than add one, use the same steps: open
the language and use **Suggest** on any string that reads wrong.

### Without Weblate

If you would rather not use Weblate, translate the file directly. Download
[`lib/l10n/app_en.arb`](../lib/l10n/app_en.arb) and save it as
`app_<code>.arb`, where the code is your language's two-letter code, e.g.
`app_fr.arb`. Change the text after each `"key":` and leave everything else
alone: the keys, the lines starting with `"@"`, and every `{placeholder}`.
Save the file as UTF-8, then attach it to a new
[issue](https://github.com/jbinder/sprawlrun/issues), or open a pull request
if you know how. It is imported into Weblate, so none of the work is lost.

## What there is to translate

| Weblate component | What it is | Where it shows |
|---|---|---|
| **App** | Every word of the interface: buttons, labels, settings, achievements, notifications, the spoken kilometre readout | The app |
| **Android** | Notification channel names, the run notification's buttons, the paused-run reminders | Android's notification shade and settings |
| **Store listing** | Title, one-line summary and description | F-Droid |
| **Sprawl Prime**, **Null Tide**, **Samhain Protocol** | One per campaign: mission briefings, every spoken line, codex entries, and the messages characters send between runs | The app, and spoken during a run |

The story files are `assets/missions/l10n/<pack>_<language>.arb`. They are
the largest part: about 1,250 strings and 20,000 words across the three
campaigns. Each string's description says who speaks it, in which mission
and scene, and its length limit.

**A mission is shown translated only once all of it is.** Until every string
of a mission has a translation, the whole mission plays in English, so a
scene never switches language partway through. Translate a mission start to
finish before moving on. The pack's own text (its tagline, codex categories
and general messages) is used string by string.

**Story strings are identified by their position**, such as
`sp01.sp01_b4.2` (mission `sp01`, scene `sp01_b4`, third line). If the
English of a line changes later, your translation keeps showing until you
update it.

**Spoken lines** are read by the phone's offline voice for your language,
with each character's pitch and pace. If the phone has no such voice, the
English original is spoken while the translation is shown. Write lines for
the ear, as with the rest of the spoken text.

## Rules

- **Names stay as they are, in every language.** Places, characters, campaigns,
  mission codenames, gangs and organisations — the Sprawl, the Ninsei strip, the
  Drowned Mile, Ossuary Row, Pump House Seven, KESTREL, SPRAWL PRIME, NULL TIDE,
  PANTHER MODERN, SAMHAIN PROTOCOL, Vantar, the Harbour Authority, the Dredge,
  SPRAWL//RUN itself. Runners talk to each other about these places; they should
  all call them the same thing. Grammar around a name is yours to adapt ("el
  Sprawl", "la Harbour Authority"). A mission's *title* ("Dead Drop on Ninsei")
  is translated; its codename (DEAD DROP) is not offered for translation at all.
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
- **"At most N characters" is a hard limit.** A story string's description ends
  with it where one applies: 90 for the weekly debrief openers, since the app
  adds the week's figures after them in the notification; 180 for other
  messages sent between runs; 260 for lines spoken aloud. Weblate counts the
  characters under the text box. A longer translation fails the app's checks
  and cannot be released until it is shortened.
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
