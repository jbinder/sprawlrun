/// Pseudo-localisation: English made to look and measure like a translation.
///
/// Every message is accented, lengthened by about 40% and bracketed, so a
/// screen rendered with it shows three things at a glance: text that would
/// overflow once translated (German and Spanish run 20–35% longer, more for
/// short labels), text that never went through the ARB (it has no brackets),
/// and text clipped at either end (a bracket is missing).
///
/// Accents stay within Latin-1, which every bundled font covers, so the
/// metrics are those of a real Western European translation.
String pseudo(String english) {
  if (english.isEmpty) return english;
  final buffer = StringBuffer('[');
  for (final rune in english.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accented[char] ?? char);
  }
  final letters = english.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
  final pad = (letters * 0.4).ceil();
  if (pad > 0) {
    final shout = english == english.toUpperCase();
    final filler = (_filler * (pad ~/ _filler.length + 1)).substring(0, pad);
    buffer
      ..write(' ')
      ..write(shout ? filler.toUpperCase() : filler);
  }
  buffer.write(']');
  return buffer.toString();
}

const _filler = 'lörém ípsüm dölör sít ámét çönséçtétür ádípísçíñg élít séd dö éíüsmöd témpör íñçídídüñt üt láböré ét dölöré mágñá álíqüá';

const _accented = {
  'a': 'á', 'c': 'ç', 'e': 'é', 'i': 'í', 'n': 'ñ', 'o': 'ö', 'u': 'ü', 'y': 'ý', //
  'A': 'Å', 'C': 'Ç', 'E': 'É', 'I': 'Î', 'N': 'Ñ', 'O': 'Ö', 'U': 'Ü', 'Y': 'Ý',
};
