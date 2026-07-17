import 'dart:io';

import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import 'templates.dart';

class FastlaneScaffolder {
  FastlaneScaffolder(this.project);

  final FlutterProject project;

  /// Files whose contents are fully generated from templates + config, so
  /// `torchinlane update` can safely re-render and diff them. Keyed by path
  /// relative to the project root. Does NOT include one-time/user-owned files
  /// (ExportOptions.plist, release notes, torchinlane.yaml).
  Map<String, String> managedFiles({
    required String appName,
    required IosConfig ios,
    required AndroidConfig android,
    required String sourceLocale,
  }) {
    return {
      'ios/fastlane/Appfile': renderTemplate(iosAppfileTemplate, {
        'bundle_id': ios.bundleId,
        'apple_id': ios.appleId,
        'itc_team_id': ios.itcTeamId,
        'team_id': ios.teamId,
      }),
      'ios/fastlane/Fastfile': renderTemplate(
        iosFastfileTemplate,
        {
          'asc_key_id': ios.ascKeyId,
          'asc_issuer_id': ios.ascIssuerId,
          'source_locale': sourceLocale,
        },
        flags: {'firebase': ios.firebaseCrashlytics},
      ),
      'android/fastlane/Appfile': renderTemplate(androidAppfileTemplate, {
        'service_account_json': _relativeToAndroidDir(android.serviceAccountJson),
        'package_name': android.packageName,
      }),
      'android/fastlane/Fastfile': androidFastfileTemplate,
      'fastlane/ChangelogHelper.rb': changelogHelperTemplate,
      'scripts/build.sh': renderTemplate(buildScriptTemplate, {
        'app_name': appName,
        'source_locale': sourceLocale,
        'changelogs_dir': 'changelogs',
        'ios_firebase_app_id': ios.firebaseAppId,
        'android_firebase_app_id': android.firebaseAppId,
      }),
    };
  }

  /// The subset of [managedFiles] paths that must be executable.
  static const executablePaths = {'scripts/build.sh'};

  void scaffold({
    required String appName,
    required IosConfig ios,
    required AndroidConfig android,
    required String sourceLocale,
  }) {
    final root = project.root.path;

    final files = managedFiles(
      appName: appName,
      ios: ios,
      android: android,
      sourceLocale: sourceLocale,
    );
    files.forEach((rel, content) {
      final path = '$root/$rel';
      _write(path, content);
      if (executablePaths.contains(rel)) _makeExecutable(path);
    });

    final exportOptions = File('$root/ios/ExportOptions.plist');
    if (!exportOptions.existsSync()) {
      _write(exportOptions.path, renderTemplate(exportOptionsPlistTemplate, {'team_id': ios.teamId}));
    }

    for (final locale in defaultLocales) {
      final file = File('$root/changelogs/$locale/release_notes.txt');
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
    }

    final configFile = project.torchinlaneConfigFile;
    configFile.writeAsStringSync(TorchinlaneConfig.render(
      appName: appName,
      ios: ios,
      android: android,
      changelogsDir: 'changelogs',
      sourceLocale: sourceLocale,
    ));

    _updateGitignore(root, ios, android);
  }

  /// [path] is relative to the project root (e.g. `android/fastlane/x.json`).
  /// The Android Appfile runs with cwd `android/`, so strip that prefix.
  String _relativeToAndroidDir(String path) {
    return path.startsWith('android/') ? path.substring('android/'.length) : path;
  }

  void _write(String path, String content) {
    final file = File(path);
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void _makeExecutable(String path) {
    if (Platform.isWindows) return;
    Process.runSync('chmod', ['+x', path]);
  }

  void _updateGitignore(String root, IosConfig ios, AndroidConfig android) {
    final gitignore = File('$root/.gitignore');
    final entries = <String>[
      ios.ascKeyPath,
      android.serviceAccountJson,
      '**/fastlane/report.xml',
      '**/fastlane/README.md',
      '**/*.bak',
      'build/debug-info-archive/',
    ];

    final existing = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    final toAdd = entries.where((e) => !existing.contains(e)).toList();
    if (toAdd.isEmpty) return;

    final addition = '\n# torchinlane\n${toAdd.join('\n')}\n';
    gitignore.writeAsStringSync(existing + addition);
  }
}
