/// A short, stable reference to an authored signal line: 32-bit FNV-1a over the
/// text, as eight hex digits.
///
/// Not `String.hashCode`, which Dart does not promise to keep the same between
/// runs or versions — and these are written to disk and into backups.
String signalRef(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
