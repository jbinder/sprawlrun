import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sprawl_run/l10n/l10n.dart';

import 'pseudo_l10n.dart';

export 'pseudo_l10n.dart';

/// Puts [PseudoL] where `L.of(context)` looks. Material's own strings stay
/// English; they are Flutter's to translate, not ours.
class _PseudoDelegate extends LocalizationsDelegate<L> {
  const _PseudoDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<L> load(Locale locale) => SynchronousFuture<L>(PseudoL());

  @override
  bool shouldReload(_PseudoDelegate old) => false;
}

/// A `MaterialApp`'s delegates for rendering in the pseudo-locale. Widgets
/// read it through these; everything else needs `debugUseStrings(PseudoL())`.
const List<LocalizationsDelegate<dynamic>> pseudoDelegates = [
  _PseudoDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
