import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sprawl_run/l10n/l10n.dart';

import 'pseudo_l10n.dart';

export 'pseudo_l10n.dart';

/// Puts [strings] where `L.of(context)` looks, whatever the locale. Material's
/// own strings stay English; they are Flutter's to translate, not ours.
class _FixedDelegate extends LocalizationsDelegate<L> {
  const _FixedDelegate(this.strings);

  final L strings;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<L> load(Locale locale) => SynchronousFuture<L>(strings);

  @override
  bool shouldReload(_FixedDelegate old) => old.strings != strings;
}

/// A `MaterialApp`'s delegates for rendering in [strings]. Widgets read them
/// through these; everything else needs `debugUseStrings(strings)` too.
List<LocalizationsDelegate<dynamic>> delegatesFor(L strings) => [
  _FixedDelegate(strings),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The pseudo-locale's delegates.
final List<LocalizationsDelegate<dynamic>> pseudoDelegates = delegatesFor(PseudoL());
