import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed build, as Android sees it.
///
/// Read from the package rather than hard-coded, so it can never disagree with
/// what is actually installed — and so the build number shows which ABI split
/// this is (`versionCode * 10 + abi` since 0.2.2).
class AppVersion {
  const AppVersion({required this.version, required this.build});

  /// `versionName`, e.g. `0.2.2`.
  final String version;

  /// `versionCode`, e.g. `42`.
  final String build;

  String get label => 'v$version · build $build';

  /// Null when the platform cannot say — never a reason to fail a screen.
  static Future<AppVersion?> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersion(version: info.version, build: info.buildNumber);
    } on Object catch (e) {
      debugPrint('version unavailable: $e');
      return null;
    }
  }
}
