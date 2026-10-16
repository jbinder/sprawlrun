import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'generated/l10n.dart';

export 'generated/l10n.dart';

/// The interface strings in the language the app is showing, for code that has
/// no [BuildContext]: services, models, notification text, [Fmt].
///
/// Widgets read `L.of(context)` instead. Both see the same language: AppState
/// resolves it and applies it here before computing or planning anything,
/// MaterialApp is handed the same locale, and its builder calls [useLocale]
/// again beneath the localisations.
///
/// English until something says otherwise, so tests and pure code need no
/// setup. The English text lives in `app_en.arb`; never write a literal for
/// something a runner reads.
L get l10n => _debugStrings ?? _current;
L _current = lookupL(const Locale('en'));
L? _debugStrings;

/// Puts [strings] behind [l10n], or English back with null. For tests that
/// render in a language the app does not ship, such as the pseudo-locale the
/// overflow test and the screenshot tool use; the app itself goes through
/// [useLocale], which this outranks. Named `debug` in the Flutter sense:
/// nothing in the app calls it.
void debugUseStrings(L? strings) => _debugStrings = strings;

/// The language to show: [preferred] if the app has it, otherwise the first of
/// the [system] languages it has, otherwise English. By language alone, so a
/// phone set to `es_MX` gets Spanish; there are no regional variants yet.
Locale resolveLocale(String? preferred, List<Locale> system) {
  bool shipped(String code) => L.supportedLocales.any((l) => l.languageCode == code);
  if (preferred != null && shipped(preferred)) return Locale(preferred);
  for (final locale in system) {
    if (shipped(locale.languageCode)) return Locale(locale.languageCode);
  }
  return const Locale('en');
}

/// Makes [locale] the language of [l10n] and of `intl`'s date formatting.
void useLocale(Locale locale) {
  if (_current.localeName == Intl.canonicalizedLocale(locale.toString())) return;
  _current = lookupL(locale);
  Intl.defaultLocale = _current.localeName;
}
