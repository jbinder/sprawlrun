import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where Settings → Contribute leads, on GitHub.
///
/// [bug] and [idea] open the issue forms in `.github/ISSUE_TEMPLATE/`, with
/// what the app already knows filled in by the id of each form field, so the
/// runner is not sent to the bottom of Settings to look up the version.
/// `contribute_test` checks those files and ids are still there.
class ProjectLinks {
  ProjectLinks._();

  static const String _repo = '/jbinder/sprawlrun';

  static final Uri contributing = Uri.https('github.com', '$_repo/blob/main/CONTRIBUTING.md');

  /// The form for suggesting a track or album for [findMusic].
  static final Uri suggestMusic = Uri.https('github.com', '$_repo/issues/new', {'template': 'music_suggestion.yml'});

  /// Where to get music for a folder. The browser goes there; the app does not.
  static final Uri findMusic = Uri.https('github.com', '$_repo/blob/main/docs/FIND_MUSIC.md');

  static Uri bug({String? version, String? language}) => Uri.https('github.com', '$_repo/issues/new', {
    'template': 'bug_report.yml',
    'version': ?version,
    'language': ?language,
  });

  static final Uri idea = Uri.https('github.com', '$_repo/issues/new', {'template': 'feature_request.yml'});
}

/// Hands [url] to the phone's browser, answering whether one took it.
///
/// The browser does the fetching: the app still has no `INTERNET` permission,
/// and this is an intent rather than `url_launcher` so that it stays free of
/// one more plugin to check for proprietary code.
Future<bool> openInBrowser(Uri url) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  const channel = MethodChannel('io.github.jbinder.sprawlrun/notifications');
  try {
    return await channel.invokeMethod<bool>('openLink', {'url': url.toString()}) ?? false;
  } on PlatformException catch (e) {
    debugPrint('openLink failed: $e');
    return false;
  } on MissingPluginException {
    return false;
  }
}
