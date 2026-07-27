import 'dart:convert';
import 'dart:io';

import '../models/profile.dart';

/// Stores the [Profile] — identity, settings, and campaign progress — as a
/// single JSON document.
///
/// Written whole on every change. The file is small (a few kilobytes even with
/// a finished campaign) and a whole-document write cannot leave progress and
/// achievements disagreeing with each other.
class ProfileRepository {
  ProfileRepository(this.root);

  final Directory root;

  File get _file => File('${root.path}/profile.json');

  Profile? _cache;

  Future<Profile> load() async {
    if (_cache != null) return _cache!;
    if (!await _file.exists()) return _cache = const Profile();
    try {
      return _cache = Profile.fromJson(Map<String, dynamic>.from(jsonDecode(await _file.readAsString()) as Map));
    } on Object {
      return _cache = const Profile();
    }
  }

  Future<void> save(Profile profile) async {
    _cache = profile;
    await root.create(recursive: true);
    await _file.writeAsString(jsonEncode(profile.toJson()));
  }

  Future<void> reset() async {
    _cache = const Profile();
    if (await _file.exists()) await _file.delete();
  }
}
