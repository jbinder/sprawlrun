# Contributing to SPRAWL//RUN

Thanks for wanting to help. There are three ways in, and none of them needs
Flutter installed.

## Translate the interface

The interface is in English and Spanish so far. Translation happens on Weblate,
in the browser, without git. Fixing a word in an existing language is as
welcome as adding a new one.

**[docs/TRANSLATING.md](docs/TRANSLATING.md)** has the link, step-by-step
instructions, the rules, a glossary, and how to translate without Weblate.

Names of places and characters stay as they are in every language, so runners
can talk about the same streets. The story packs are translated on Weblate
too, one component per campaign.

## Write missions

A mission pack is one JSON file. Import it in the app with **Settings → Mission
packs → Import pack** and play it, with no build needed.
**[docs/MISSION_PACKS.md](docs/MISSION_PACKS.md)** describes the format, and
`assets/missions/sprawl_prime.json` is a worked example.

## Report a bug or suggest something

Open an [issue](https://github.com/jbinder/sprawlrun/issues). For a problem
during a run, say what the phone is and whether the screen was off.

## Code

Pull requests are welcome. Before opening one, run:

```bash
flutter analyze   # must stay clean
flutter test
```

The [README](README.md) explains the architecture and what the tests cover.
Text a runner reads never goes into the code as a literal. It goes into
`lib/l10n/app_en.arb`, with a description for translators.
