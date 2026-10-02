import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../changelog/locale_maps.dart';
import 'store_templates.dart';

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
    String changelogsDir = 'changelogs',
  }) {
    return {
      'ios/fastlane/Appfile': renderTemplate(iosAppfileTemplate, {
        'bundle_id': ios.bundleId,
        'apple_id': ios.appleId,
        'itc_team_id': ios.itcTeamId,
        'team_id': ios.teamId,
      }),
      'ios/fastlane/Fastfile': renderTemplate(
        _withLanes(iosFastfileTemplate, iosStoreLanes),
        {
          'asc_key_id': ios.ascKeyId,
          'asc_issuer_id': ios.ascIssuerId,
          'source_locale': sourceLocale,
        },
        flags: {'firebase': ios.firebaseCrashlytics},
      ),
      'android/fastlane/Appfile': renderTemplate(androidAppfileTemplate, {
        'service_account_json':
            _relativeToAndroidDir(android.serviceAccountJson),
        'package_name': android.packageName,
      }),
      'android/fastlane/Fastfile':
          _withLanes(androidFastfileTemplate, androidStoreLanes),
      'fastlane/ChangelogHelper.rb': newChangelogHelperTemplate,
      'fastlane/StoreHelper.rb': storeHelperTemplate,
      'fastlane/locales.json': const JsonEncoder.withIndent('  ')
          .convert({'ios': appStoreLocaleMap, 'android': googlePlayLocaleMap}),
      'scripts/build.sh': renderTemplate(buildScriptTemplate, {
        'app_name': _shellDouble(appName),
        'source_locale': _shellDouble(sourceLocale),
        'changelogs_dir': _shellDouble(changelogsDir),
        'ios_firebase_app_id': _shellDouble(ios.firebaseAppId),
        'android_firebase_app_id': _shellDouble(android.firebaseAppId),
      }),
    };
  }

  String _shellDouble(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll('`', r'\`')
      .replaceAll('"', r'\"');

  String _withLanes(String template, String lanes) {
    final last = template.lastIndexOf('end');
    return '${template.substring(0, last)}$lanes\nend\n';
  }

  /// The subset of [managedFiles] paths that must be executable.
  static const executablePaths = {'scripts/build.sh'};

  void scaffold({
    required String appName,
    required IosConfig ios,
    required AndroidConfig android,
    required String sourceLocale,
    String changelogsDir = 'changelogs',
  }) {
    final root = project.root.path;

    final files = managedFiles(
      appName: appName,
      ios: ios,
      android: android,
      sourceLocale: sourceLocale,
      changelogsDir: changelogsDir,
    );
    files.forEach((rel, content) {
      final path = '$root/$rel';
      _write(path, content);
      if (executablePaths.contains(rel)) _makeExecutable(path);
    });

    final exportOptions = File('$root/ios/ExportOptions.plist');
    if (!exportOptions.existsSync()) {
      _write(exportOptions.path,
          renderTemplate(exportOptionsPlistTemplate, {'team_id': ios.teamId}));
    }

    for (final locale in defaultLocales) {
      final file = File('$root/$changelogsDir/$locale/release_notes.txt');
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
    }

    final configFile = project.torchinlaneConfigFile;
    configFile.writeAsStringSync(TorchinlaneConfig.render(
      appName: appName,
      ios: ios,
      android: android,
      changelogsDir: changelogsDir,
      sourceLocale: sourceLocale,
    ));

    _updateGitignore(root, ios, android);
  }

  void ensureGitignore(IosConfig ios, AndroidConfig android) {
    _updateGitignore(project.root.path, ios, android);
  }

  /// [path] is relative to the project root (e.g. `android/fastlane/x.json`).
  /// The Android Appfile runs with cwd `android/`, so strip that prefix.
  String _relativeToAndroidDir(String path) {
    return path.startsWith('android/')
        ? path.substring('android/'.length)
        : path;
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
      if (!p.isAbsolute(ios.ascKeyPath) || p.isWithin(root, ios.ascKeyPath))
        p.isAbsolute(ios.ascKeyPath)
            ? p.relative(ios.ascKeyPath, from: root)
            : ios.ascKeyPath,
      if (!p.isAbsolute(android.serviceAccountJson) ||
          p.isWithin(root, android.serviceAccountJson))
        p.isAbsolute(android.serviceAccountJson)
            ? p.relative(android.serviceAccountJson, from: root)
            : android.serviceAccountJson,
      '**/fastlane/report.xml',
      '**/fastlane/README.md',
      '**/*.bak',
      'store/.snapshots/',
      '.torchinlane/',
      'gha-creds-*.json',
      'build/debug-info-archive/',
    ];

    final existing = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    final ignoredLines = existing.split('\n').toSet();
    final toAdd = entries.where((e) => !ignoredLines.contains(e)).toList();
    if (toAdd.isEmpty) return;

    final addition = '\n# torchinlane\n${toAdd.join('\n')}\n';
    gitignore.writeAsStringSync(existing + addition);
  }
}
