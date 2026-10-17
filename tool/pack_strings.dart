import 'dart:convert';
import 'dart:io';

import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/pack_strings.dart';

/// Writes the English source of each bundled pack's translation,
/// `assets/missions/l10n/<pack>_en.arb`, and reports how far every other
/// language has got.
///
///     fvm dart run tool/pack_strings.dart
///
/// Run it after changing a pack's text; `pack_strings_test` fails while a
/// source file is stale. Translators work from the English file — on Weblate
/// or by hand — and their `<pack>_<lang>.arb` is what the app loads.
///
///     fvm dart run tool/pack_strings.dart my_pack.json
///
/// prints any pack's strings the same way instead, for an author writing a
/// `translations` block into their own pack.
void main(List<String> args) {
  if (args.isNotEmpty) {
    for (final path in args) {
      stdout.write(packSourceArb(MissionPack.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)));
    }
    return;
  }
  final packs = Directory('assets/missions').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in packs) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    final pack = MissionPack.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    final source = File('assets/missions/l10n/${name}_en.arb');
    final arb = packSourceArb(pack);
    if (!source.existsSync() || source.readAsStringSync() != arb) {
      source
        ..createSync(recursive: true)
        ..writeAsStringSync(arb);
      stdout.writeln('wrote ${source.path}');
    }
    final strings = packStrings(pack);
    for (final translation in source.parent.listSync().whereType<File>()) {
      final match = RegExp('^${name}_(\\w+)\\.arb\$').firstMatch(translation.uri.pathSegments.last);
      if (match == null || match[1] == 'en') continue;
      final texts = {
        for (final MapEntry(:key, :value) in (jsonDecode(translation.readAsStringSync()) as Map).entries)
          if (!(key as String).startsWith('@') && value is String && value.trim().isNotEmpty) key: value,
      };
      final done = translatedMissions(pack, texts);
      final unknown = texts.keys.where((k) => !strings.containsKey(k));
      stdout.writeln(
        '${match[1]} $name: ${texts.keys.where(strings.containsKey).length}/${strings.length} strings, '
        '${done.length}/${pack.missions.length} missions complete',
      );
      for (final key in unknown) {
        stdout.writeln('  not in the pack: $key');
      }
    }
  }
}

/// The English source of [pack]'s translation, as an ARB file: every string
/// with a note on where it appears, in reading order.
String packSourceArb(MissionPack pack) {
  final out = <String, Object>{'@@locale': 'en'};
  for (final MapEntry(:key, :value) in packStrings(pack).entries) {
    out[key] = value.english;
    out['@$key'] = {'description': value.note};
  }
  return '${const JsonEncoder.withIndent('  ').convert(out)}\n';
}
