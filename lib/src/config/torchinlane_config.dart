import 'dart:io';

import 'package:yaml/yaml.dart';

const defaultLocales = [
  'ar', 'bn', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi',
  'fr', 'he', 'hi', 'hu', 'id', 'it', 'ja', 'ko', 'nl', 'no',
  'pl', 'pt', 'ro', 'ru', 'sk', 'sv', 'th', 'tl', 'tr', 'uk',
  'vi', 'zh',
];

class IosConfig {
  IosConfig({
    required this.bundleId,
    required this.teamId,
    required this.itcTeamId,
    required this.appleId,
    required this.ascKeyId,
    required this.ascIssuerId,
    required this.ascKeyPath,
    required this.firebaseCrashlytics,
  });

  final String bundleId;
  final String teamId;
  final String itcTeamId;
  final String appleId;
  final String ascKeyId;
  final String ascIssuerId;
  final String ascKeyPath;
  final bool firebaseCrashlytics;
}

class AndroidConfig {
  AndroidConfig({required this.packageName, required this.serviceAccountJson});

  final String packageName;
  final String serviceAccountJson;
}

class ChangelogsConfig {
  ChangelogsConfig({required this.dir, required this.sourceLocale, required this.locales});

  final String dir;
  final String sourceLocale;
  final List<String> locales;
}

class TorchinlaneConfig {
  TorchinlaneConfig({
    required this.appName,
    required this.ios,
    required this.android,
    required this.changelogs,
    this.obfuscate = true,
    this.splitDebugInfo = 'build/debug-info',
  });

  final String appName;
  final IosConfig ios;
  final AndroidConfig android;
  final ChangelogsConfig changelogs;
  final bool obfuscate;
  final String splitDebugInfo;

  static TorchinlaneConfig load(File file) {
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final iosMap = doc['ios'] as YamlMap;
    final androidMap = doc['android'] as YamlMap;
    final changelogsMap = doc['changelogs'] as YamlMap?;
    final buildMap = doc['build'] as YamlMap?;

    return TorchinlaneConfig(
      appName: doc['app_name'] as String,
      ios: IosConfig(
        bundleId: iosMap['bundle_id'] as String,
        teamId: iosMap['team_id'] as String,
        itcTeamId: (iosMap['itc_team_id'] as String?) ?? iosMap['team_id'] as String,
        appleId: iosMap['apple_id'] as String,
        ascKeyId: iosMap['asc_key_id'] as String,
        ascIssuerId: iosMap['asc_issuer_id'] as String,
        ascKeyPath: (iosMap['asc_key_path'] as String?) ?? 'ios/api_key.p8',
        firebaseCrashlytics: (iosMap['firebase_crashlytics'] as bool?) ?? false,
      ),
      android: AndroidConfig(
        packageName: androidMap['package_name'] as String,
        serviceAccountJson: (androidMap['service_account_json'] as String?) ??
            'android/fastlane/fastlane-service-account.json',
      ),
      changelogs: ChangelogsConfig(
        dir: (changelogsMap?['dir'] as String?) ?? 'changelogs',
        sourceLocale: (changelogsMap?['source_locale'] as String?) ?? 'en',
        locales: changelogsMap?['locales'] != null
            ? List<String>.from(changelogsMap!['locales'] as YamlList)
            : defaultLocales,
      ),
      obfuscate: (buildMap?['obfuscate'] as bool?) ?? true,
      splitDebugInfo: (buildMap?['split_debug_info'] as String?) ?? 'build/debug-info',
    );
  }

  static String render({
    required String appName,
    required IosConfig ios,
    required AndroidConfig android,
    required String changelogsDir,
    required String sourceLocale,
  }) {
    final localesYaml = defaultLocales.map((l) => '  - $l').join('\n');
    return '''
app_name: $appName
ios:
  bundle_id: ${ios.bundleId}
  team_id: ${ios.teamId}
  itc_team_id: ${ios.itcTeamId}
  apple_id: ${ios.appleId}
  asc_key_id: ${ios.ascKeyId}
  asc_issuer_id: ${ios.ascIssuerId}
  asc_key_path: ${ios.ascKeyPath}
  firebase_crashlytics: ${ios.firebaseCrashlytics}
android:
  package_name: ${android.packageName}
  service_account_json: ${android.serviceAccountJson}
changelogs:
  dir: $changelogsDir
  source_locale: $sourceLocale
  locales:
$localesYaml
build:
  obfuscate: true
  split_debug_info: build/debug-info
screenshots:
  output_dir: screenshots
  ios_devices: []
  android_devices: []
  locales: [$sourceLocale]
''';
  }
}
