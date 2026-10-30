# Colour themes

A colour theme is one small JSON file. The app ships NEON, its year-round look,
plus every theme in `assets/themes/`, and runners can import their own. Each
one is a swatch under **Settings → Identity → Colours**, drawn in its own
colours. Picking one recolours the whole app at once.

`assets/themes/glacier.json` is a worked example. Copy it to start your own.

## Where themes come from

1. **Built in.** NEON is defined in code (`CyPalette.standard`), because it is
   the default and draws the app before anything has loaded.
2. **Shipped.** Every `.json` file in `assets/themes/`. The app finds them
   through the asset manifest, so contributing a theme means adding one file,
   with no code to change. See [Contributing a theme](#contributing-a-theme).
3. **Imported.** **Settings → Identity → Colours → Import theme** opens the
   system file picker. You don't need a rebuild, an app update or a storage
   permission, and the theme is put on as soon as it imports.

An imported theme is stored under its `id`, so importing a revised version
replaces the old one. That is the edit-and-reimport loop while you make one.
An import may not take the id of a built-in or shipped theme. Removing an
imported theme (the bin beside it while it is picked) goes back to NEON.

Imported themes are part of a backup (Settings → Data), so a new phone gets them
back with everything else. Restoring a backup in full leaves exactly the themes
it carried. Merging one adds the themes this phone lacks and keeps its own
version of any it already has. A theme that no longer passes the rules below,
or whose id a shipped theme has taken since, is skipped. A profile whose theme
is gone draws NEON.

A season, such as SAMHAIN PROTOCOL from 10 October to 2 November, wears its
own colours over whichever theme is picked, and the theme comes back when it
ends. Settings says so under the swatches. Switching off **Seasonal events**
puts the picked theme back at once.

## Shape

```jsonc
{
  "id": "glacier",              // a–z, 0–9, "-" and "_", up to 32; the file name
  "name": "GLACIER",            // 1–16 characters; shown upper-cased
  "names": { "es": "GLACIAR" }, // optional: the name in other languages
  "author": "Your name",        // optional for an import, required to contribute
  "colours": {
    "background":  "#04080F",
    "panel":       "#0A121E",
    "panelRaised": "#111C2C",
    "rule":        "#1F3048",
    "primary":     "#6EA8FF",
    "primaryDim":  "#2F5A99",
    "hostile":     "#FF4D6D",
    "hostileDim":  "#8A2238",
    "story":       "#FFD27A",
    "success":     "#4DFFC3",
    "failure":     "#FF6A3D",
    "locked":      "#3A4C63",
    "text":        "#E4EEFA",
    "textDim":     "#8095AE"
  }
}
```

The file itself is plain JSON, so leave out the comments. `colours` is spelled
the British way. Every colour is opaque `#RRGGBB`. Partly transparent panels
would let the animated backdrop show through every screen.

`names` gives the name in other languages, keyed by language code. A name that
reads as a name everywhere, like SYNTHWAVE, needs none. Names are never sent to
the translation platform: they belong to the theme, like a pack's title.

## The roles

Colours are named for what they mean, not for their hue. A theme only changes
the hue.

| Role | What it is for |
| --- | --- |
| `background` | The deepest background: the space between panels, and the backdrop |
| `panel` | Panel fill. Everything you read sits on it |
| `panelRaised` | Nested surfaces and list rows, one step lighter than `panel` |
| `rule` | Hairlines, dividers and inactive borders |
| `primary` | "You": what is interactive and alive, your figures and the selected item |
| `primaryDim` | A quieter `primary`, for icons and secondary accents |
| `hostile` | Pursuits, urgency, anything coming for you |
| `hostileDim` | A quieter `hostile` |
| `story` | The story voice: handlers, transmissions, the streak |
| `success` | A goal met or a mission cleared |
| `failure` | A failed mission, damage, a hard stop |
| `locked` | Locked, disabled and redacted things. Meant to be dim |
| `text` | Body text |
| `textDim` | Secondary text |

## What every theme must pass

Both an import and the test suite refuse a theme that cannot be read mid-run.
The error names the role at fault:

- `text` has a contrast of at least **7:1** against `panel`, as WCAG measures it.
- `textDim` has at least **4.5:1**.
- `primary`, `hostile`, `story`, `success` and `failure` each have at least
  **4:1**, and no two of them are the same colour.

Every shipped theme clears these with room, so they rule out only themes that
would be hard to read. Any WCAG contrast checker gives the same ratios as the
app.

## Contributing a theme

To ship a theme with the app, open a pull request that adds one file,
`assets/themes/<id>.json`. Before you do:

1. **Import it and live with it.** Look at the dashboard, a run, the summary,
   the achievement wall and Settings. A colour that looks fine in a swatch can
   still glare on a full screen.
2. **Keep `success` a green** (hue 80–165°), so a met goal looks met in every
   theme. Keep the roles apart in hue as well as in value: `hostile` must not
   read as `primary`, and `failure` must not read as `hostile`.
3. **Set `author`.** It is shown under the swatch while the theme is picked.
4. **Run the tests.** `flutter test test/theme_test.dart` checks the file name
   matches the `id`, the id and name are unique, the contrast rules above hold,
   `success` is green, `names` only uses languages the app ships, and `author`
   is there. You need Flutter for this. If you don't have it, importing the
   file in the app checks the format and the contrast rules, so open the pull
   request anyway and the maintainer runs the rest.

Then add the theme to the list in the README's *Everything it does* section and
to the store descriptions in `fastlane/metadata/android/*/full_description.txt`.
