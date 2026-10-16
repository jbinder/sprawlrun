import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/achievement.dart';

import '../tool/gen_pseudo_l10n.dart';

/// The contract for translations. English is the source; every other language
/// arrives from Weblate as `app_<lang>.arb` and `values-<lang>/strings.xml`,
/// and may be partial — a missing key falls back to English — but may not
/// break a message that is there.
void main() {
  final arbDir = Directory('lib/l10n');
  Map<String, dynamic> read(File f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final english = read(File('lib/l10n/app_en.arb'));
  final messages = {for (final e in english.entries) if (!e.key.startsWith('@')) e.key: e.value as String};
  final translations = arbDir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'),
  );

  /// `{name}` and `{name, plural, …}` alike: the names a message takes. Not a
  /// branch of a select or plural (`KM{km}`, `=1{…}`), whose brace follows its
  /// case key directly.
  Set<String> placeholders(String message) =>
      RegExp(r'(?<![\w=])\{(\w+)(?=[,}])').allMatches(message).map((m) => m.group(1)!).toSet();

  test('every English message says what it is for', () {
    // Translators see a string without its screen; the description is all
    // they have. A one-word button is the least obvious of all.
    final undescribed = [
      for (final key in messages.keys)
        if ((english['@$key'] as Map?)?['description'] == null && messages[key]!.length < 25) key,
    ];
    expect(undescribed, isEmpty, reason: 'short strings need a description in app_en.arb');
  });

  test('a translation only has keys English has, with the same placeholders', () {
    for (final file in translations) {
      final arb = read(file);
      for (final MapEntry(:key, :value) in arb.entries) {
        if (key.startsWith('@')) continue;
        expect(messages, contains(key), reason: '${file.path}: $key is not an English key');
        expect(
          placeholders(value as String),
          placeholders(messages[key]!),
          reason: '${file.path}: $key changes its placeholders',
        );
      }
    }
  });

  test('the pseudo-locale is generated from the current messages', () {
    // A message added since misses an override and stops compiling on its own;
    // this catches the rest, such as a placeholder renamed.
    expect(
      File('test/support/pseudo_l10n.dart').readAsStringSync(),
      pseudoL10nSource(File('lib/l10n/generated/l10n.dart').readAsStringSync()),
      reason: 'run: fvm dart run tool/gen_pseudo_l10n.dart',
    );
  });

  test('every language names itself, so the picker never lists "English" twice', () {
    // A language fresh from Weblate falls back to English for anything not
    // yet translated — this string included.
    for (final locale in L.supportedLocales.where((l) => l.languageCode != 'en')) {
      expect(lookupL(locale).languageName, isNot('English'), reason: 'app_${locale.languageCode}.arb: languageName');
    }
  });

  test('every store listing F-Droid reads has a title and a short enough summary', () {
    // F-Droid rejects a summary over 80 characters, so one arriving from Weblate
    // would break the build of a release rather than this test.
    for (final dir in Directory('fastlane/metadata/android').listSync().whereType<Directory>()) {
      final title = File('${dir.path}/title.txt');
      final summary = File('${dir.path}/short_description.txt');
      if (!summary.existsSync() && !title.existsSync()) continue;
      expect(title.existsSync() && title.readAsStringSync().trim().isNotEmpty, isTrue, reason: '${dir.path}: no title');
      if (summary.existsSync()) {
        expect(summary.readAsStringSync().trim().length, lessThanOrEqualTo(80), reason: '${dir.path}: summary too long');
      }
    }
  });

  test('every achievement has a name and a description', () {
    final en = lookupL(const Locale('en'));
    for (final a in kAchievements) {
      expect(achievementTitle(en, a.id), isNot(a.id), reason: '${a.id} has no title in app_en.arb');
      expect(achievementDescription(en, a.id), isNotEmpty, reason: '${a.id} has no description in app_en.arb');
    }
  });

  group('Android strings', () {
    final res = Directory('android/app/src/main/res');
    Map<String, String> strings(File f) => {
      for (final m in RegExp(r'<string name="(\w+)">(.*?)</string>', dotAll: true).allMatches(f.readAsStringSync()))
        m.group(1)!: m.group(2)!,
    };
    final base = strings(File('${res.path}/values/strings.xml'));

    test('a translation only has names English has, with the same format arguments', () {
      final args = RegExp(r'%\d+\$[sd]');
      for (final dir in res.listSync().whereType<Directory>().where((d) => d.path.contains('/values-'))) {
        final file = File('${dir.path}/strings.xml');
        if (!file.existsSync()) continue;
        for (final MapEntry(:key, :value) in strings(file).entries) {
          expect(base, contains(key), reason: '${file.path}: $key is not an English name');
          expect(
            args.allMatches(value).map((m) => m[0]).toSet(),
            args.allMatches(base[key]!).map((m) => m[0]).toSet(),
            reason: '${file.path}: $key changes its format arguments',
          );
        }
      }
    });

    test('Android offers exactly the languages the app ships', () {
      // Android 13's per-app language setting lists what locales_config says;
      // one missing there is a language nobody can pick from system settings.
      final config = File('${res.path}/xml/locales_config.xml').readAsStringSync();
      final listed = RegExp(r'<locale android:name="([\w-]+)"').allMatches(config).map((m) => m[1]).toSet();
      expect(listed, {for (final l in L.supportedLocales) l.toLanguageTag()});
    });

    test('the signal channels are named the same on both sides', () {
      // The Dart side passes the names again whenever it schedules, and the
      // last one to call createNotificationChannel wins.
      for (final locale in L.supportedLocales) {
        final code = locale.languageCode;
        final file = File('${res.path}/${code == 'en' ? 'values' : 'values-$code'}/strings.xml');
        if (!file.existsSync()) continue;
        final android = {...base, ...strings(file)};
        final dart = lookupL(locale);
        final reason = '$code: the channel names differ between strings.xml and app_$code.arb';
        expect(android['channel_reminders'], dart.channelReminders, reason: reason);
        expect(android['channel_reminders_description'], dart.channelRemindersDescription, reason: reason);
        expect(android['channel_noise'], dart.channelNoise, reason: reason);
        expect(android['channel_noise_description'], dart.channelNoiseDescription, reason: reason);
        expect(android['channel_debrief'], dart.channelDebrief, reason: reason);
        expect(android['channel_debrief_description'], dart.channelDebriefDescription, reason: reason);
      }
    });
  });
}
