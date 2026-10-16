import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'generated/l10n.dart';

export 'generated/l10n.dart';

/// The interface strings in the language the app is showing, for code that has
/// no [BuildContext]: services, models, notification text, [Fmt].
///
/// Widgets read `L.of(context)` instead. Both see the same language, because
/// [useLocale] runs on every build of the app's root, beneath the
/// localisations, and the whole tree rebuilds when the language changes.
///
/// English until something says otherwise, so tests and pure code need no
/// setup. The English text lives in `app_en.arb`; never write a literal for
/// something a runner reads.
L get l10n => _current;
L _current = lookupL(const Locale('en'));

/// Makes [locale] the language of [l10n] and of `intl`'s date formatting.
void useLocale(Locale locale) {
  if (_current.localeName == Intl.canonicalizedLocale(locale.toString())) return;
  _current = lookupL(locale);
  Intl.defaultLocale = _current.localeName;
}
