import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Reads a file from the system picker as UTF-8 text.
///
/// Not `XFile.readAsString`: on Android the picker hands back the file's bytes,
/// and for those cross_file ignores the encoding and decodes each byte as a
/// character — Latin-1 — so a translated pack's `año` arrived as `aÃ±o`.
Future<String> readPickedText(XFile file) async => decodeText(await file.readAsBytes());

/// Strict UTF-8, minus the byte-order mark some Windows editors write, which
/// `jsonDecode` would otherwise reject as an unexpected character.
String decodeText(List<int> bytes) {
  final text = utf8.decode(bytes);
  return text.startsWith('﻿') ? text.substring(1) : text;
}
