import 'package:package_info_plus/package_info_plus.dart';

/// Version of the installed build, read from the platform (pubspec `version:`)
/// so screens never hard-code it.
class AppInfo {
  AppInfo._();

  static Future<String>? _version;

  /// e.g. "1.0.0" - build number omitted.
  static Future<String> version() => _version ??=
      PackageInfo.fromPlatform().then((p) => p.version).catchError((_) => '');
}
